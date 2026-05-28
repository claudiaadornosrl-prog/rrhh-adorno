-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Cálculo real de sueldo de vendedoras (#98)
--
--  Modelo de datos para reemplazar el Excel mensual de sueldos:
--    - Config por local: % de comisión + modo de reparto.
--    - Config por empleada: fijo, viáticos, premio fich+uni, fracción de
--      comisión y modo de prorrateo (con histórico por vigencia).
--    - Ventas del local por mes (base de la comisión).
--    - Liquidación mensual: recibo blanco (CCT) + cálculo en negro (fórmula
--      Adorno) en una sola fila por empleada/período.
--    - Conceptos del recibo (básico, antig, presentismo, no rem, descuentos)
--      como detalle hijo para emitir el PDF y auditar el cálculo.
--
--  Decisiones JP (sesión 28/05/2026):
--    - Alcanza con emitir el recibo PDF; AFIP/declaraciones siguen en el estudio.
--    - Comisión por local: Alcorta 0,25% · Unicenter 0,5% · Oficina 2% dividido
--      entre los empleados activos del local.
--    - Premio fichadas+uniforme: regla todo-o-nada.
--        · Locales: ≤4 puntos del mes → cobra. ≥5 → pierde.
--        · Oficina: ≤3 → cobra. ≥4 → pierde.
--        · Uniforme NO OK (flag de la encargada): siempre pierde.
--    - Director (Adorno C.V.) y fuera de convenio (Simonelli) NO entran en
--      este módulo, se manejan aparte.
--    - Casos especiales temporales (asterisco): activa_en_modulo = false.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. CONFIG POR LOCAL ───
CREATE TABLE IF NOT EXISTS rrhh_sueldo_local_config (
    id              bigserial PRIMARY KEY,
    local           text NOT NULL,                   -- 'unicenter'/'alcorta'/'oficina'
    vigente_desde   date NOT NULL,
    tasa_comision   numeric(8,5) NOT NULL,           -- ej 0.00250 = 0,25%
    modo_reparto    text NOT NULL CHECK (modo_reparto IN ('completo','dividido_activos')),
    -- 'completo': cada empleada cobra (ventas × tasa)
    -- 'dividido_activos': cada una cobra (ventas × tasa) / cantidad_activos_del_local_y_mes
    umbral_premio   int NOT NULL DEFAULT 4,          -- puntos máximos del mes para mantener premio
    notas           text,
    UNIQUE(local, vigente_desde)
);

INSERT INTO rrhh_sueldo_local_config (local, vigente_desde, tasa_comision, modo_reparto, umbral_premio) VALUES
    ('alcorta',   '2026-01-01', 0.00250, 'completo',          4),
    ('unicenter', '2026-01-01', 0.00500, 'completo',          4),
    ('oficina',   '2026-01-01', 0.02000, 'dividido_activos',  3)
ON CONFLICT (local, vigente_desde) DO NOTHING;

-- ─── 2. CONFIG POR EMPLEADA (con histórico) ───
CREATE TABLE IF NOT EXISTS rrhh_sueldo_empleada_config (
    id                          bigserial PRIMARY KEY,
    empleado_id                 bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    vigente_desde               date NOT NULL,
    fijo                        numeric(12,2) NOT NULL DEFAULT 0,
    viaticos                    numeric(12,2) NOT NULL DEFAULT 0,
    premio_fichadas_uniforme    numeric(12,2) NOT NULL DEFAULT 0,
    -- fracción del % del local que cobra esta empleada (1 = 100%, 0.5 = 50%, 0 = no cobra)
    fraccion_comision           numeric(5,4) NOT NULL DEFAULT 1.0000,
    -- 'mes_completo' (default) o 'por_dias_trabajados' (caso franquera Escasany)
    modo_prorrateo_comision     text NOT NULL DEFAULT 'mes_completo'
                                  CHECK (modo_prorrateo_comision IN ('mes_completo','por_dias_trabajados')),
    -- ¿se incluye en la liquidación del mes? Falso para directores, fuera de
    -- convenio, asteriscos/casos especiales que no entran al módulo.
    activa_en_modulo            boolean NOT NULL DEFAULT true,
    notas                       text,
    UNIQUE(empleado_id, vigente_desde)
);
CREATE INDEX IF NOT EXISTS idx_sueldoemp_vigente
    ON rrhh_sueldo_empleada_config(empleado_id, vigente_desde DESC);

-- Función helper: config vigente al período
CREATE OR REPLACE FUNCTION rrhh_sueldo_empleada_vigente(p_empleado bigint, p_periodo date)
RETURNS rrhh_sueldo_empleada_config
LANGUAGE sql STABLE AS $func$
    SELECT * FROM rrhh_sueldo_empleada_config
     WHERE empleado_id = p_empleado AND vigente_desde <= p_periodo
     ORDER BY vigente_desde DESC LIMIT 1;
$func$;

CREATE OR REPLACE FUNCTION rrhh_sueldo_local_vigente(p_local text, p_periodo date)
RETURNS rrhh_sueldo_local_config
LANGUAGE sql STABLE AS $func$
    SELECT * FROM rrhh_sueldo_local_config
     WHERE local = p_local AND vigente_desde <= p_periodo
     ORDER BY vigente_desde DESC LIMIT 1;
$func$;

-- ─── 3. VENTAS DEL LOCAL POR MES (base de la comisión) ───
CREATE TABLE IF NOT EXISTS rrhh_ventas_local_mes (
    id              bigserial PRIMARY KEY,
    local           text NOT NULL,
    periodo         date NOT NULL,                   -- siempre día 1 del mes
    monto_ventas    numeric(14,2) NOT NULL,
    origen          text DEFAULT 'manual',           -- 'manual'/'sheet_ventas'/'crm'
    cargado_at      timestamptz DEFAULT now(),
    cargado_por     text,
    UNIQUE(local, periodo)
);

-- ─── 4. LIQUIDACIÓN MENSUAL ───
CREATE TABLE IF NOT EXISTS rrhh_liquidacion (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    periodo             date NOT NULL,               -- día 1 del mes
    local               text NOT NULL,               -- snapshot del local en ese mes
    estado              text NOT NULL DEFAULT 'borrador'
                          CHECK (estado IN ('borrador','revisada','firmada','anulada')),

    -- Inputs editables por la encargada/admin en el cierre del mes
    dias_trabajados     int  NOT NULL DEFAULT 30,    -- unidades del CCT (30 = mes completo)
    mercaderia          numeric(12,2) NOT NULL DEFAULT 0,
    ajuste              numeric(12,2) NOT NULL DEFAULT 0,
    uniforme_ok         boolean NOT NULL DEFAULT true,
    puntos_mes          int    NOT NULL DEFAULT 0,   -- snapshot de los puntos al cierre
    observaciones       text,

    -- Calculados del RECIBO BLANCO (CCT 130/75)
    recibo_basico       numeric(12,2),
    recibo_antiguedad   numeric(12,2),
    recibo_presentismo  numeric(12,2),
    recibo_sumafija_nr  numeric(12,2),
    recibo_antig_nr     numeric(12,2),
    recibo_pres_nr      numeric(12,2),
    recibo_recompos_nr  numeric(12,2),
    recibo_otros_rem    numeric(12,2) DEFAULT 0,
    recibo_jubilacion   numeric(12,2),
    recibo_ley19032     numeric(12,2),
    recibo_obra_social  numeric(12,2),
    recibo_sec          numeric(12,2),
    recibo_faecys       numeric(12,2),
    recibo_total_rem    numeric(12,2),
    recibo_total_nr     numeric(12,2),
    recibo_bruto        numeric(12,2),
    recibo_descuentos   numeric(12,2),
    recibo_neto         numeric(12,2),

    -- Calculados del NEGRO (fórmula Adorno)
    fijo                numeric(12,2),
    comision            numeric(12,2),
    premio_cobra        boolean,                     -- ¿se le paga el premio este mes?
    premio_monto        numeric(12,2),               -- 0 si no lo cobra
    viaticos            numeric(12,2),
    extras              numeric(12,2) DEFAULT 0,     -- vacaciones pagadas, plus puntual, etc.
    total_negro         numeric(12,2),               -- fijo+comision+premio+viaticos+extras
    efectivo            numeric(12,2),               -- max(0, total_negro − recibo_neto − mercaderia − ajuste)

    -- Auditoría
    calculado_at        timestamptz,
    firmado_at          timestamptz,
    firmado_por         text,
    pdf_url             text,                        -- URL del recibo PDF generado
    UNIQUE(empleado_id, periodo)
);
CREATE INDEX IF NOT EXISTS idx_liq_periodo_local ON rrhh_liquidacion(periodo, local);
CREATE INDEX IF NOT EXISTS idx_liq_emp_periodo   ON rrhh_liquidacion(empleado_id, periodo DESC);

-- ─── 5. CONCEPTOS DEL RECIBO (detalle hijo para el PDF) ───
CREATE TABLE IF NOT EXISTS rrhh_liquidacion_concepto (
    id              bigserial PRIMARY KEY,
    liquidacion_id  bigint NOT NULL REFERENCES rrhh_liquidacion(id) ON DELETE CASCADE,
    codigo          text NOT NULL,                   -- '0001','0022','0025','0490','0491','0492','0493','0496','0497','1001','1002','1011','1012','1031', etc.
    nombre          text NOT NULL,                   -- 'Sueldo Básico','Antigüedad','Presentismo','Suma fija no rem',...
    base            numeric(12,2),                   -- base de cálculo (informativo)
    porcentaje      numeric(7,4),                    -- % aplicado (informativo)
    importe         numeric(12,2) NOT NULL,
    remunerativo    boolean NOT NULL,
    es_descuento    boolean NOT NULL DEFAULT false,
    orden           int NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_concepto_liq ON rrhh_liquidacion_concepto(liquidacion_id, orden);

-- ═══════════════════════════════════════════════════════════════════════
--  RLS
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE rrhh_sueldo_local_config     ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_sueldo_empleada_config  ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_ventas_local_mes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_liquidacion             ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_liquidacion_concepto    ENABLE ROW LEVEL SECURITY;

-- Configs y ventas: solo admin lee/escribe (data sensible)
DROP POLICY IF EXISTS slc_admin ON rrhh_sueldo_local_config;
CREATE POLICY slc_admin ON rrhh_sueldo_local_config FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

DROP POLICY IF EXISTS sec_admin ON rrhh_sueldo_empleada_config;
CREATE POLICY sec_admin ON rrhh_sueldo_empleada_config FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

DROP POLICY IF EXISTS vlm_admin ON rrhh_ventas_local_mes;
CREATE POLICY vlm_admin ON rrhh_ventas_local_mes FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- Liquidación:
--   - admin todo;
--   - empleada ve la suya;
--   - encargada (gerente) ve la liquidación de su local (totales + componentes
--     del negro). La UI le oculta el desglose del recibo blanco (descuentos
--     del CCT) — los conceptos hijos están protegidos por su propia RLS.
DROP POLICY IF EXISTS liq_admin   ON rrhh_liquidacion;
CREATE POLICY liq_admin   ON rrhh_liquidacion FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

DROP POLICY IF EXISTS liq_self    ON rrhh_liquidacion;
CREATE POLICY liq_self    ON rrhh_liquidacion FOR SELECT TO authenticated
    USING (empleado_id = rrhh_mi_empleado_id());

DROP POLICY IF EXISTS liq_gerente ON rrhh_liquidacion;
CREATE POLICY liq_gerente ON rrhh_liquidacion FOR SELECT TO authenticated
    USING (rrhh_is_gerente() AND local = rrhh_gerente_local());

-- Conceptos del recibo blanco:
--   - admin todo;
--   - la propia empleada ve los suyos;
--   - la encargada ve los de las liquidaciones de su local (los necesita
--     para imprimir recibos y hacer firmar a las vendedoras).
DROP POLICY IF EXISTS liqc_admin   ON rrhh_liquidacion_concepto;
CREATE POLICY liqc_admin   ON rrhh_liquidacion_concepto FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

DROP POLICY IF EXISTS liqc_self    ON rrhh_liquidacion_concepto;
CREATE POLICY liqc_self    ON rrhh_liquidacion_concepto FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM rrhh_liquidacion l
         WHERE l.id = liquidacion_id AND l.empleado_id = rrhh_mi_empleado_id()
    ));

DROP POLICY IF EXISTS liqc_gerente ON rrhh_liquidacion_concepto;
CREATE POLICY liqc_gerente ON rrhh_liquidacion_concepto FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM rrhh_liquidacion l
         WHERE l.id = liquidacion_id
           AND rrhh_is_gerente() AND l.local = rrhh_gerente_local()
    ));

-- ═══════════════════════════════════════════════════════════════════════
--  AUMENTOS DE SUELDO (flujo encargada propone → JP aprueba)
--
--  JP abre un pedido de aumento con un rango (% min – % max) y una fecha de
--  vigencia para un local. La encargada asigna automáticamente el tope para
--  sí misma y distribuye un % a cada vendedora dentro del rango según
--  desempeño. JP revisa y aprueba. Al aplicar, se generan filas nuevas en
--  rrhh_sueldo_empleada_config con los Fijos actualizados.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rrhh_aumento_pedido (
    id              bigserial PRIMARY KEY,
    local           text NOT NULL,                   -- 'unicenter'/'alcorta'/'oficina'
    fecha_vigencia  date NOT NULL,                   -- desde cuándo aplica el nuevo Fijo
    pct_min         numeric(5,2) NOT NULL,           -- ej 5.00
    pct_max         numeric(5,2) NOT NULL,           -- ej 10.00
    estado          text NOT NULL DEFAULT 'abierto'
                      CHECK (estado IN ('abierto','propuesto','aprobado','rechazado','aplicado')),
    notas           text,
    abierto_at      timestamptz DEFAULT now(),
    abierto_por     text,
    propuesto_at    timestamptz,
    aprobado_at     timestamptz,
    aprobado_por    text,
    aplicado_at     timestamptz
);
CREATE INDEX IF NOT EXISTS idx_aumento_local_estado ON rrhh_aumento_pedido(local, estado);

CREATE TABLE IF NOT EXISTS rrhh_aumento_pedido_detalle (
    id              bigserial PRIMARY KEY,
    pedido_id       bigint NOT NULL REFERENCES rrhh_aumento_pedido(id) ON DELETE CASCADE,
    empleado_id     bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fijo_anterior   numeric(12,2) NOT NULL,
    pct_propuesto   numeric(5,2),                    -- NULL hasta que la encargada lo cargue
    fijo_nuevo      numeric(12,2),                   -- = fijo_anterior * (1 + pct/100)
    notas_encargada text,
    UNIQUE(pedido_id, empleado_id)
);

ALTER TABLE rrhh_aumento_pedido          ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_aumento_pedido_detalle  ENABLE ROW LEVEL SECURITY;

-- Pedido: admin abre/cierra; encargada ve y propone sobre los pedidos de su local
DROP POLICY IF EXISTS aum_admin   ON rrhh_aumento_pedido;
CREATE POLICY aum_admin   ON rrhh_aumento_pedido FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

DROP POLICY IF EXISTS aum_gerente_select ON rrhh_aumento_pedido;
CREATE POLICY aum_gerente_select ON rrhh_aumento_pedido FOR SELECT TO authenticated
    USING (rrhh_is_gerente() AND local = rrhh_gerente_local());

-- La encargada solo puede mover de 'abierto' a 'propuesto' (UPDATE acotado, validado en RPC)
DROP POLICY IF EXISTS aum_gerente_update ON rrhh_aumento_pedido;
CREATE POLICY aum_gerente_update ON rrhh_aumento_pedido FOR UPDATE TO authenticated
    USING (rrhh_is_gerente() AND local = rrhh_gerente_local() AND estado IN ('abierto','propuesto'))
    WITH CHECK (rrhh_is_gerente() AND local = rrhh_gerente_local() AND estado IN ('abierto','propuesto'));

-- Detalle: admin todo; encargada ve y edita los detalles de los pedidos de su local
DROP POLICY IF EXISTS aumd_admin    ON rrhh_aumento_pedido_detalle;
CREATE POLICY aumd_admin    ON rrhh_aumento_pedido_detalle FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

DROP POLICY IF EXISTS aumd_gerente ON rrhh_aumento_pedido_detalle;
CREATE POLICY aumd_gerente ON rrhh_aumento_pedido_detalle FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM rrhh_aumento_pedido p
                    WHERE p.id = pedido_id
                      AND rrhh_is_gerente() AND p.local = rrhh_gerente_local()
                      AND p.estado IN ('abierto','propuesto')))
    WITH CHECK (EXISTS (SELECT 1 FROM rrhh_aumento_pedido p
                         WHERE p.id = pedido_id
                           AND rrhh_is_gerente() AND p.local = rrhh_gerente_local()
                           AND p.estado IN ('abierto','propuesto')));

-- ═══════════════════════════════════════════════════════════════════════
--  SEED — Configs por empleada con los Fijos de Abril 2026
--  Tomado de tus planillas Sueldos {Local} 2026.xlsx, hoja "Abril".
--  Vigentes desde 2026-04-01. JP puede actualizar cada paritaria
--  insertando una nueva fila con otra vigente_desde.
-- ═══════════════════════════════════════════════════════════════════════
INSERT INTO rrhh_sueldo_empleada_config
    (empleado_id, vigente_desde, fijo, viaticos, premio_fichadas_uniforme,
     fraccion_comision, modo_prorrateo_comision, activa_en_modulo, notas)
SELECT e.id, '2026-04-01'::date, v.fijo, v.viaticos, v.premio, v.frac, v.modo, v.activa, v.notas
FROM (VALUES
    -- ALCORTA (7 vendedoras + Adorno aparte)
    ('BENITEZ',  'ROMINA SOLANGE',    1670000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('COPA',     'LILIANA TERESA',    1490000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('QUIROGA',  'ELISABETH LAURA',   1490000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('VERON',    'GEORGINA ELIZABETH', 760000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('NICOLA',   'VALERIA ALCIRA',    1350000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('BIANCHI',  'MARIA SOLEDAD',     1490000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('NOGUERA PARRA','ADRIAN',        1150000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    -- UNICENTER (vendedoras + Encargada Donzelli)
    ('DONZELLI',  'SORAYA BEATRIZ',   1400000, 44000, 60500, 1.00, 'mes_completo',         true,  'Encargada'),
    ('ESCASANY',  'ANGELES',           350000, 44000, 60500, 1.00, 'por_dias_trabajados',  true,  'Franquera: comisión por días trabajados'),
    ('FRECCERO MEZA','ESTEFANIA NOEMI', 755000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('DAMELA',    'SILVINA ALICIA',    665000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('GODOY',     'CINTIA PAMELA',     615000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('SANCHEZ',   'SONIA LUZ',         990000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('MOREIRA',   'GABRIELA LILIANA', 1150000, 44000, 60500, 0.50, 'mes_completo',         true,  'Acuerdo individual: fijo alto + comisión al 50%'),
    -- OFICINA (Administrativos + Maestranza; sin Simonelli ni Adorno C.V.)
    ('RIVERA',    'ANALIA BEATRIZ',   1800000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('CONTRERAS', 'MARISA ISABEL',    2200000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL),
    ('MONZON',    'CARLOS IVAN',      1800000, 44000, 60500, 1.00, 'mes_completo',         true,  NULL)
) AS v(apellido, nombre, fijo, viaticos, premio, frac, modo, activa, notas)
JOIN rrhh_empleados e
  ON upper(e.apellido) = v.apellido AND upper(e.nombre) = v.nombre
ON CONFLICT (empleado_id, vigente_desde) DO NOTHING;

-- Directores y fuera de convenio: marcados como NO activos en este módulo.
-- (No hace falta cargarles configuración; al estar fuera, no se generan liquidaciones.)
-- Si en algún momento querés mostrar su Fijo para histórico, los podés agregar
-- con activa_en_modulo = false.
