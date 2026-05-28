-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Módulo de préstamos a empleadas
--
--  Modelo: Adorno presta capital a una empleada y se lo descuenta en
--  cuotas mensuales con sistema francés (cuotas iguales, interés sobre saldo).
--
--  Reparto en la liquidación:
--    - Cuota de CAPITAL → se descuenta del "Monto a acreditar en banco"
--      (es decir, del recibo blanco, vía concepto 1031 "Préstamos").
--    - Cuota de INTERÉS → se descuenta del efectivo (negro).
--
--  Permisos:
--    - SOLO admin (JP) puede crear, modificar, cancelar préstamos.
--    - La empleada ve sus propios préstamos y cuotas (transparencia).
--    - La encargada NO ve los préstamos de su local (decisión sensible).
--
--  Si una empleada renuncia con saldo:
--    - El admin marca el préstamo como 'cancelado_anticipado'.
--    - El sistema NO descuenta automático en la liquidación final — esa
--      lógica queda para el módulo de liquidación final / SAC.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Cabecera del préstamo ───
CREATE TABLE IF NOT EXISTS rrhh_prestamo (
    id                   bigserial PRIMARY KEY,
    empleado_id          bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE RESTRICT,

    -- Términos pactados al otorgar
    fecha_otorgamiento   date          NOT NULL,
    capital              numeric(12,2) NOT NULL CHECK (capital > 0),
    tasa_mensual         numeric(6,4)  NOT NULL DEFAULT 0
                              CHECK (tasa_mensual >= 0 AND tasa_mensual < 1),
                              -- ej 0.05 = 5% mensual. 0 = sin interés.
    cuotas_totales       int           NOT NULL CHECK (cuotas_totales > 0 AND cuotas_totales <= 60),
    cuota_monto          numeric(12,2) NOT NULL,
                              -- Calculada al crear con sistema francés:
                              -- cuota = capital * (i*(1+i)^n) / ((1+i)^n - 1)
                              -- Si i = 0: cuota = capital / n
    mes_primer_descuento date          NOT NULL,
                              -- YYYY-MM-01 — desde qué período se empieza a descontar

    -- Estado
    estado               text          NOT NULL DEFAULT 'activo'
                              CHECK (estado IN ('activo','pagado','cancelado_anticipado')),

    -- Auditoría
    otorgado_por         text,
    otorgado_at          timestamptz   DEFAULT now(),
    notas                text,

    -- Si se cancela antes del final
    cancelado_at         timestamptz,
    cancelado_motivo     text,
    cancelado_por        text
);
CREATE INDEX IF NOT EXISTS idx_prestamo_emp_estado ON rrhh_prestamo(empleado_id, estado);
CREATE INDEX IF NOT EXISTS idx_prestamo_estado     ON rrhh_prestamo(estado);

COMMENT ON TABLE  rrhh_prestamo IS
'Préstamos otorgados por Adorno SRL a empleadas. Sistema francés con tasa mensual fija.';
COMMENT ON COLUMN rrhh_prestamo.tasa_mensual IS
'Tasa mensual fija (decimal, ej 0.05 = 5% mensual). 0 = préstamo sin interés.';
COMMENT ON COLUMN rrhh_prestamo.cuota_monto IS
'Monto fijo de la cuota mensual calculado con fórmula francesa al crear el préstamo.';
COMMENT ON COLUMN rrhh_prestamo.mes_primer_descuento IS
'Primer período del descuento (YYYY-MM-01). Las cuotas siguen siendo mensuales consecutivas.';

-- ─── Detalle: plan de cuotas ───
CREATE TABLE IF NOT EXISTS rrhh_prestamo_cuota (
    id                bigserial PRIMARY KEY,
    prestamo_id       bigint  NOT NULL REFERENCES rrhh_prestamo(id) ON DELETE CASCADE,
    numero            int     NOT NULL,             -- 1, 2, ..., cuotas_totales
    mes_descuento     date    NOT NULL,             -- YYYY-MM-01

    monto_total       numeric(12,2) NOT NULL,       -- = monto_capital + monto_interes
    monto_capital     numeric(12,2) NOT NULL,
    monto_interes     numeric(12,2) NOT NULL DEFAULT 0,
    saldo_post_cuota  numeric(12,2) NOT NULL,       -- capital pendiente DESPUÉS de aplicar esta cuota

    estado            text    NOT NULL DEFAULT 'pendiente'
                            CHECK (estado IN ('pendiente','aplicada','cancelada')),
    liquidacion_id    bigint  REFERENCES rrhh_liquidacion(id) ON DELETE SET NULL,
                            -- A qué liquidación quedó atada cuando se aplicó
    aplicada_at       timestamptz,

    UNIQUE(prestamo_id, numero)
);
CREATE INDEX IF NOT EXISTS idx_prestamo_cuota_mes      ON rrhh_prestamo_cuota(mes_descuento, estado);
CREATE INDEX IF NOT EXISTS idx_prestamo_cuota_prestamo ON rrhh_prestamo_cuota(prestamo_id, numero);
CREATE INDEX IF NOT EXISTS idx_prestamo_cuota_liq      ON rrhh_prestamo_cuota(liquidacion_id);

COMMENT ON COLUMN rrhh_prestamo_cuota.estado IS
'pendiente = todavía no se aplicó. aplicada = ya fue al recibo (con liquidacion_id). cancelada = no se va a aplicar (cancelacion anticipada).';

-- ─── Función helper: ¿cuál es el saldo restante de un préstamo? ───
CREATE OR REPLACE FUNCTION rrhh_prestamo_saldo(p_prestamo_id bigint)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(monto_capital), 0)::numeric
    FROM rrhh_prestamo_cuota
    WHERE prestamo_id = p_prestamo_id
      AND estado = 'pendiente';
$$;
COMMENT ON FUNCTION rrhh_prestamo_saldo IS
'Devuelve el capital pendiente del préstamo (suma de capital de cuotas pendientes).';

-- ─── Snapshot del descuento en cada liquidación (para auditoría rápida) ───
ALTER TABLE rrhh_liquidacion
    ADD COLUMN IF NOT EXISTS prestamo_capital  numeric(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS prestamo_interes  numeric(12,2) NOT NULL DEFAULT 0;
COMMENT ON COLUMN rrhh_liquidacion.prestamo_capital IS
'Suma del capital descontado este mes por cuotas de préstamos (descuento del banco).';
COMMENT ON COLUMN rrhh_liquidacion.prestamo_interes IS
'Suma de intereses descontados este mes por cuotas de préstamos (descuento del efectivo).';

-- ═══════════════════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE rrhh_prestamo       ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_prestamo_cuota ENABLE ROW LEVEL SECURITY;

-- Admin: control total sobre préstamos.
DROP POLICY IF EXISTS prestamo_admin ON rrhh_prestamo;
CREATE POLICY prestamo_admin ON rrhh_prestamo FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- Empleada: ve sus propios préstamos (transparencia financiera).
DROP POLICY IF EXISTS prestamo_self ON rrhh_prestamo;
CREATE POLICY prestamo_self ON rrhh_prestamo FOR SELECT TO authenticated
    USING (empleado_id = rrhh_mi_empleado_id());

-- Admin: control total sobre cuotas.
DROP POLICY IF EXISTS prestamo_cuota_admin ON rrhh_prestamo_cuota;
CREATE POLICY prestamo_cuota_admin ON rrhh_prestamo_cuota FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- Empleada: ve sus propias cuotas (via FK al préstamo).
DROP POLICY IF EXISTS prestamo_cuota_self ON rrhh_prestamo_cuota;
CREATE POLICY prestamo_cuota_self ON rrhh_prestamo_cuota FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM rrhh_prestamo p
        WHERE p.id = prestamo_id
          AND p.empleado_id = rrhh_mi_empleado_id()
    ));
