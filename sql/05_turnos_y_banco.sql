-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Sistema de turnos + banco de minutos
--  Reemplaza el flujo mensual agregado por uno basado en planificación.
--
--  Ejecutar UNA VEZ en Supabase SQL Editor (después de 01-04).
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
-- 1. FICHADAS RAW — registros crudos de Anviz CrossChex Cloud
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_fichadas_raw (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint REFERENCES rrhh_empleados(id) ON DELETE SET NULL,
    -- Datos crudos de Anviz (por si no se pudo matchear)
    anviz_workno        text,             -- el "Workno" de Anviz, para debug si no matchea
    anviz_first_name    text,
    anviz_last_name     text,
    -- Timestamp de la fichada (en hora Argentina, UTC-3)
    fecha               date NOT NULL,
    hora                time NOT NULL,
    fecha_hora          timestamptz NOT NULL,
    -- Origen
    local               text NOT NULL,    -- unicenter | alcorta | oficina
    dispositivo_serial  text,
    dispositivo_nombre  text,
    checktype           int,              -- 0=in, 1=out (Anviz a veces lo manda)
    cuenta_anviz        text,             -- 'oficina' | 'unicenter' | 'alcorta' | 'alcorta_backup'
    raw_data            jsonb,            -- payload completo para debug
    created_at          timestamptz DEFAULT now(),
    -- Idempotencia: evita duplicados al re-correr el sync
    UNIQUE (fecha_hora, dispositivo_serial, anviz_workno)
);
CREATE INDEX IF NOT EXISTS idx_fich_emp_fecha  ON rrhh_fichadas_raw(empleado_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_fich_local      ON rrhh_fichadas_raw(local, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_fich_fecha_hora ON rrhh_fichadas_raw(fecha_hora DESC);

-- ───────────────────────────────────────────────────────────────────────
-- 2. TEMPLATES DE TURNO — botones rápidos por local
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_templates_turno (
    id              bigserial PRIMARY KEY,
    local           text NOT NULL,             -- unicenter | alcorta | oficina | global
    codigo          text NOT NULL,             -- 'manana', 'tarde', 'intermedio', 'completo', 'franco'
    nombre          text NOT NULL,             -- 'Mañana 9:45-16'
    hora_inicio     time,                      -- NULL para 'franco'
    hora_fin        time,
    es_franco       boolean DEFAULT false,
    color           text,                      -- color hex para la UI ej. '#3b82f6'
    icono           text,                      -- emoji ej. '🌅'
    orden           int DEFAULT 0,
    activo          boolean DEFAULT true,
    created_at      timestamptz DEFAULT now(),
    UNIQUE(local, codigo)
);
CREATE INDEX IF NOT EXISTS idx_tpl_local ON rrhh_templates_turno(local, activo);

-- Seeds: Oficina + Alcorta (Unicenter cuando JP confirme)
INSERT INTO rrhh_templates_turno (local, codigo, nombre, hora_inicio, hora_fin, es_franco, color, icono, orden) VALUES
    -- ===== OFICINA =====
    ('oficina',   'completo',   'Completo 7:45-17:30',  '07:45', '17:30', false, '#0d9488', '🏢', 1),
    ('oficina',   'franco',     'Franco',                NULL,    NULL,   true,  '#9ca3af', '❌', 99),

    -- ===== ALCORTA =====
    ('alcorta',   'manana',     'Mañana 9:45-16',        '09:45', '16:00', false, '#f59e0b', '🌅', 1),
    ('alcorta',   'tarde',      'Tarde 15:45-21',        '15:45', '21:00', false, '#6366f1', '🌆', 2),
    ('alcorta',   'intermedio', 'Intermedio 13-19',      '13:00', '19:00', false, '#10b981', '🕐', 3),
    ('alcorta',   'completo',   'Completo 9:45-21',      '09:45', '21:00', false, '#dc2626', '🌞', 4),
    ('alcorta',   'franco',     'Franco',                NULL,    NULL,   true,  '#9ca3af', '❌', 99),

    -- ===== UNICENTER (shopping abre 10-22; turnos 15min antes) =====
    ('unicenter', 'manana',         'Mañana 9:45-15:45',     '09:45', '15:45', false, '#f59e0b', '🌅', 1),
    ('unicenter', 'tarde',          'Tarde 15:45-22',        '15:45', '22:00', false, '#6366f1', '🌆', 2),
    ('unicenter', 'intermedio',     'Intermedio 12:45-18:45','12:45', '18:45', false, '#10b981', '🕐', 3),
    ('unicenter', 'finde_completo', 'Fin de semana 8hs',     '13:45', '22:00', false, '#a855f7', '📅', 4),
    ('unicenter', 'franco',         'Franco',                 NULL,    NULL,  true,  '#9ca3af', '❌', 99)
ON CONFLICT (local, codigo) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- 3. TURNOS DEFAULT — horario habitual del empleado por día de semana
--    (90% de los casos se repiten, este es el "horario base")
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_turnos_default (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    dia_semana      int NOT NULL,            -- 0=domingo, 1=lunes, ..., 6=sábado
    template_id     bigint REFERENCES rrhh_templates_turno(id),  -- opcional
    hora_inicio     time,                    -- si NULL → tomar del template
    hora_fin        time,
    es_franco       boolean DEFAULT false,
    activo_desde    date DEFAULT CURRENT_DATE,
    updated_at      timestamptz DEFAULT now(),
    updated_by      text,
    UNIQUE(empleado_id, dia_semana, activo_desde),
    CHECK (dia_semana >= 0 AND dia_semana <= 6)
);
CREATE INDEX IF NOT EXISTS idx_tdef_emp ON rrhh_turnos_default(empleado_id, dia_semana);

-- ───────────────────────────────────────────────────────────────────────
-- 4. TURNOS — planificación real día a día
--    (instanciados desde default o creados puntualmente por la encargada)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_turnos (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha           date NOT NULL,
    template_id     bigint REFERENCES rrhh_templates_turno(id),
    hora_inicio     time,                     -- NULL si es franco/vacaciones
    hora_fin        time,
    tipo            text DEFAULT 'planificado', -- 'planificado'|'vacaciones'|'licencia'|'feriado'|'franco'
    es_franco       boolean DEFAULT false,
    observaciones   text,
    planificado_por text,
    created_at      timestamptz DEFAULT now(),
    updated_at      timestamptz DEFAULT now(),
    UNIQUE(empleado_id, fecha)
);
CREATE INDEX IF NOT EXISTS idx_turnos_fecha    ON rrhh_turnos(fecha DESC);
CREATE INDEX IF NOT EXISTS idx_turnos_emp_mes  ON rrhh_turnos(empleado_id, fecha);

-- ───────────────────────────────────────────────────────────────────────
-- 5. PERMISOS — pedidos puntuales (retirarse antes, entrar después)
--    Distinto a licencias (que son días enteros).
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_permisos (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha               date NOT NULL,
    hora_desde          time NOT NULL,           -- desde cuándo se retira / entra después
    hora_hasta          time NOT NULL,
    minutos             int NOT NULL,            -- minutos que afecta
    motivo              text,
    estado              text DEFAULT 'solicitado', -- solicitado|aprobado|rechazado|cumplido
    solicitado_por      text,
    fecha_solicitud     timestamptz DEFAULT now(),
    aprobado_por        text,
    fecha_aprobacion    timestamptz,
    motivo_rechazo      text,
    -- Cómo se compensa
    compensa_con        text,                    -- 'banco' (resta del banco) | 'no_compensa' (resta del banco) | 'descuento_sueldo'
    created_at          timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_per_emp_fecha ON rrhh_permisos(empleado_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_per_estado    ON rrhh_permisos(estado);

-- ───────────────────────────────────────────────────────────────────────
-- 6. HORAS EXTRAS — registro de extras autorizadas
--    (la encargada las solicita y autoriza — es la misma persona)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_horas_extras (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha           date NOT NULL,
    minutos         int NOT NULL,                -- minutos extras realizadas
    motivo          text,
    autorizado_por  text,                        -- email de la encargada
    -- Cómo se trata
    compensacion    text DEFAULT 'banco',        -- 'banco' (suma al banco) | 'pago_negro' | 'pago_recibo'
    pagado          boolean DEFAULT false,
    fecha_pago      date,
    monto_pagado    numeric(12,2),
    observaciones   text,
    created_at      timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hext_emp_fecha ON rrhh_horas_extras(empleado_id, fecha DESC);

-- ───────────────────────────────────────────────────────────────────────
-- 7. BANCO DE MINUTOS — movimientos
--    Saldo = SUM(minutos) por empleado.
--    Positivo: empleado tiene minutos a favor.
--    Negativo: empleado debe minutos.
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_banco_minutos (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha           date NOT NULL,
    minutos         int NOT NULL,           -- + a favor, - en contra
    tipo            text NOT NULL,          -- 'hora_extra' | 'permiso_compensado' | 'falta' | 'tarde' | 'salida_temprana' | 'pago' | 'ajuste'
    referencia_tipo text,                   -- 'horas_extras' | 'permisos' | 'asistencia' | etc.
    referencia_id   bigint,                 -- id de la tabla referenciada
    observaciones   text,
    creado_por      text,                   -- email o 'sistema'
    created_at      timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_banco_emp    ON rrhh_banco_minutos(empleado_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_banco_tipo   ON rrhh_banco_minutos(tipo);

-- Vista: saldo actual por empleado
CREATE OR REPLACE VIEW rrhh_banco_saldo AS
SELECT
    e.id AS empleado_id,
    e.nombre_completo,
    e.local,
    COALESCE(SUM(b.minutos), 0) AS saldo_minutos,
    -- Conversión a horas:minutos para mostrar
    CASE
        WHEN COALESCE(SUM(b.minutos), 0) >= 0 THEN
            LPAD((COALESCE(SUM(b.minutos), 0) / 60)::text, 2, '0') || ':' ||
            LPAD((COALESCE(SUM(b.minutos), 0) % 60)::text, 2, '0')
        ELSE
            '-' ||
            LPAD((ABS(COALESCE(SUM(b.minutos), 0)) / 60)::text, 2, '0') || ':' ||
            LPAD((ABS(COALESCE(SUM(b.minutos), 0)) % 60)::text, 2, '0')
    END AS saldo_horas
FROM rrhh_empleados e
LEFT JOIN rrhh_banco_minutos b ON b.empleado_id = e.id
WHERE e.estado = 'activo'
GROUP BY e.id, e.nombre_completo, e.local;

-- ───────────────────────────────────────────────────────────────────────
-- 8. CONFIG DE TOLERANCIAS — configurable por local
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_config_tolerancias (
    local                       text PRIMARY KEY,
    minutos_tarde               int DEFAULT 20,    -- minutos de tolerancia para llegada tarde
    minutos_temprano            int DEFAULT 5,     -- para retirarse antes
    buffer_entrada              int DEFAULT 15,    -- minutos antes del horario real que se carga el turno (ej. 10:00 → 9:45)
    trabaja_feriados_nacionales boolean DEFAULT true, -- shoppings sí trabajan; oficina no
    updated_at                  timestamptz DEFAULT now(),
    updated_by                  text
);
INSERT INTO rrhh_config_tolerancias (local, minutos_tarde, minutos_temprano, buffer_entrada, trabaja_feriados_nacionales) VALUES
    ('oficina',   20, 5, 15, false),
    ('unicenter', 20, 5, 15, true),
    ('alcorta',   20, 5, 15, true)
ON CONFLICT (local) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- 9. ALTERS — agregar flags en rrhh_feriados (qué local cierra ese día)
--    Para shoppings: cierran solo 1-ene, 25-dic, 1-may, Día del Comercio
-- ───────────────────────────────────────────────────────────────────────
ALTER TABLE rrhh_feriados
    ADD COLUMN IF NOT EXISTS cierra_oficina   boolean DEFAULT true,    -- oficina cierra TODOS los feriados nacionales
    ADD COLUMN IF NOT EXISTS cierra_shoppings boolean DEFAULT false;   -- shoppings cierran solo algunos

-- Marcar los feriados en los que SÍ cierran los shoppings
UPDATE rrhh_feriados SET cierra_shoppings = true
WHERE fecha IN (
    '2026-01-01',  -- Año Nuevo
    '2026-05-01',  -- Día del Trabajador
    '2026-12-25'   -- Navidad
);

-- Agregar Día del Comercio (26 de septiembre — cierran los shoppings)
INSERT INTO rrhh_feriados (fecha, nombre, tipo, cierra_oficina, cierra_shoppings) VALUES
    ('2026-09-26', 'Día del Empleado de Comercio', 'no_laborable', false, true)
ON CONFLICT (fecha) DO UPDATE SET cierra_shoppings = EXCLUDED.cierra_shoppings;

-- ───────────────────────────────────────────────────────────────────────
-- 10. ALTERS — rrhh_asistencias_detalle: agregar referencias al turno + banco
-- ───────────────────────────────────────────────────────────────────────
ALTER TABLE rrhh_asistencias_detalle
    ADD COLUMN IF NOT EXISTS turno_id       bigint REFERENCES rrhh_turnos(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS minutos_extra  int DEFAULT 0,
    ADD COLUMN IF NOT EXISTS minutos_banco  int DEFAULT 0,
    ADD COLUMN IF NOT EXISTS procesado_at   timestamptz;

-- ───────────────────────────────────────────────────────────────────────
-- 11. RLS — Row Level Security para tablas nuevas
-- ───────────────────────────────────────────────────────────────────────
ALTER TABLE rrhh_fichadas_raw            ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_templates_turno         ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_turnos_default          ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_turnos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_permisos                ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_horas_extras            ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_banco_minutos           ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_config_tolerancias      ENABLE ROW LEVEL SECURITY;

-- FICHADAS RAW: admin todo, gerente su local, empleado las suyas
DROP POLICY IF EXISTS fr_admin   ON rrhh_fichadas_raw;
DROP POLICY IF EXISTS fr_gerente ON rrhh_fichadas_raw;
DROP POLICY IF EXISTS fr_self    ON rrhh_fichadas_raw;
CREATE POLICY fr_admin   ON rrhh_fichadas_raw FOR ALL USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY fr_gerente ON rrhh_fichadas_raw FOR SELECT USING (rrhh_is_gerente() AND local = rrhh_gerente_local());
CREATE POLICY fr_self    ON rrhh_fichadas_raw FOR SELECT USING (empleado_id = rrhh_mi_empleado_id());

-- TEMPLATES: todos leen, admin/gerente escriben
DROP POLICY IF EXISTS tpl_read   ON rrhh_templates_turno;
DROP POLICY IF EXISTS tpl_write  ON rrhh_templates_turno;
CREATE POLICY tpl_read   ON rrhh_templates_turno FOR SELECT USING (true);
CREATE POLICY tpl_write  ON rrhh_templates_turno FOR ALL USING (rrhh_is_admin() OR rrhh_is_gerente()) WITH CHECK (rrhh_is_admin() OR rrhh_is_gerente());

-- TURNOS DEFAULT: admin/gerente CRUD su local, empleado los suyos read-only
DROP POLICY IF EXISTS tdef_admin   ON rrhh_turnos_default;
DROP POLICY IF EXISTS tdef_gerente ON rrhh_turnos_default;
DROP POLICY IF EXISTS tdef_self    ON rrhh_turnos_default;
CREATE POLICY tdef_admin   ON rrhh_turnos_default FOR ALL USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY tdef_gerente ON rrhh_turnos_default FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY tdef_self    ON rrhh_turnos_default FOR SELECT USING (empleado_id = rrhh_mi_empleado_id());

-- TURNOS REALES: admin/gerente CRUD, empleado read
DROP POLICY IF EXISTS turnos_admin   ON rrhh_turnos;
DROP POLICY IF EXISTS turnos_gerente ON rrhh_turnos;
DROP POLICY IF EXISTS turnos_self    ON rrhh_turnos;
CREATE POLICY turnos_admin   ON rrhh_turnos FOR ALL USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY turnos_gerente ON rrhh_turnos FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY turnos_self    ON rrhh_turnos FOR SELECT USING (empleado_id = rrhh_mi_empleado_id());

-- PERMISOS: empleado puede SOLICITAR (insert), admin/gerente CRUD
DROP POLICY IF EXISTS per_admin     ON rrhh_permisos;
DROP POLICY IF EXISTS per_gerente   ON rrhh_permisos;
DROP POLICY IF EXISTS per_self_read ON rrhh_permisos;
DROP POLICY IF EXISTS per_self_ins  ON rrhh_permisos;
CREATE POLICY per_admin     ON rrhh_permisos FOR ALL USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY per_gerente   ON rrhh_permisos FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY per_self_read ON rrhh_permisos FOR SELECT USING (empleado_id = rrhh_mi_empleado_id());
CREATE POLICY per_self_ins  ON rrhh_permisos FOR INSERT WITH CHECK (empleado_id = rrhh_mi_empleado_id() AND estado = 'solicitado');

-- HORAS EXTRAS: admin/gerente CRUD, empleado solo read sus propias
DROP POLICY IF EXISTS hext_admin   ON rrhh_horas_extras;
DROP POLICY IF EXISTS hext_gerente ON rrhh_horas_extras;
DROP POLICY IF EXISTS hext_self    ON rrhh_horas_extras;
CREATE POLICY hext_admin   ON rrhh_horas_extras FOR ALL USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY hext_gerente ON rrhh_horas_extras FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY hext_self    ON rrhh_horas_extras FOR SELECT USING (empleado_id = rrhh_mi_empleado_id());

-- BANCO DE MINUTOS: admin todo, gerente su local read, empleado solo read los suyos
DROP POLICY IF EXISTS banco_admin   ON rrhh_banco_minutos;
DROP POLICY IF EXISTS banco_gerente ON rrhh_banco_minutos;
DROP POLICY IF EXISTS banco_self    ON rrhh_banco_minutos;
CREATE POLICY banco_admin   ON rrhh_banco_minutos FOR ALL USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY banco_gerente ON rrhh_banco_minutos FOR SELECT
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY banco_self    ON rrhh_banco_minutos FOR SELECT USING (empleado_id = rrhh_mi_empleado_id());

-- CONFIG TOLERANCIAS: todos leen, solo admin escribe
DROP POLICY IF EXISTS conf_read  ON rrhh_config_tolerancias;
DROP POLICY IF EXISTS conf_write ON rrhh_config_tolerancias;
CREATE POLICY conf_read  ON rrhh_config_tolerancias FOR SELECT USING (true);
CREATE POLICY conf_write ON rrhh_config_tolerancias FOR ALL USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- ═══════════════════════════════════════════════════════════════════════
-- Verificación rápida
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT 'templates por local' AS check, local, COUNT(*) FROM rrhh_templates_turno WHERE activo GROUP BY local
-- UNION ALL
-- SELECT 'tolerancias', local, NULL FROM rrhh_config_tolerancias;
