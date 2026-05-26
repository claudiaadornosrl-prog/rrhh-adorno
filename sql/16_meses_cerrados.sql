-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Cierre de mes (banco diferido)
--
--  Flujo nuevo:
--    1. procesarMes calcula rrhh_asistencias_detalle (estados, minutos por día)
--       pero NO escribe al banco.
--    2. Cuando la encargada hace "Cerrar mes" para un (local, año, mes),
--       el sistema crea los movimientos correspondientes en rrhh_banco_minutos
--       y registra el cierre en esta tabla.
--    3. No se puede reprocesar un mes cerrado sin reabrir primero.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rrhh_meses_cerrados (
    id              bigserial PRIMARY KEY,
    local           text NOT NULL,
    año             int NOT NULL,
    mes             int NOT NULL,
    cerrado_por     text NOT NULL,
    cerrado_at      timestamptz DEFAULT now(),
    movimientos_creados int DEFAULT 0,
    minutos_totales int DEFAULT 0,
    observaciones   text,
    UNIQUE(local, año, mes)
);

CREATE INDEX IF NOT EXISTS idx_mc_local_periodo
    ON rrhh_meses_cerrados(local, año DESC, mes DESC);

-- ═══════════════════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE rrhh_meses_cerrados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mc_admin   ON rrhh_meses_cerrados;
DROP POLICY IF EXISTS mc_gerente ON rrhh_meses_cerrados;
DROP POLICY IF EXISTS mc_read    ON rrhh_meses_cerrados;

-- Admin: full
CREATE POLICY mc_admin ON rrhh_meses_cerrados FOR ALL
    USING (EXISTS (
        SELECT 1 FROM rrhh_usuarios u
        WHERE u.auth_user_id = auth.uid() AND u.rol = 'admin' AND u.activo = true
    ));

-- Gerente: full sobre su local
CREATE POLICY mc_gerente ON rrhh_meses_cerrados FOR ALL
    USING (EXISTS (
        SELECT 1 FROM rrhh_usuarios u
        WHERE u.auth_user_id = auth.uid()
          AND u.rol = 'gerente'
          AND u.activo = true
          AND rrhh_meses_cerrados.local = u.local_gerencia
    ));

-- Empleado: lectura (para saber si su mes está cerrado)
CREATE POLICY mc_read ON rrhh_meses_cerrados FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM rrhh_usuarios u
        WHERE u.auth_user_id = auth.uid() AND u.activo = true
    ));
