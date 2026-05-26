-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Fase E: Permisos puntuales
--
--  4 tipos:
--    - retirarse_antes:  vendedora se va antes del fin de turno
--    - llegar_tarde:     vendedora avisa que va a llegar tarde
--    - dia_completo:     pide día libre
--    - salir_volver:     sale a la mitad del turno y vuelve
--
--  Flujo:
--    1. Vendedora (o encargada) solicita → estado='pendiente'
--    2. Encargada o admin aprueba/rechaza
--    3. Al aprobar, define si descuenta del banco y cuántos minutos
--    4. procesarMes respeta los permisos aprobados:
--       - no marca tarde/falta_fichada si hay permiso aprobado
--       - descuenta banco si descontar_banco=true
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rrhh_permisos_puntuales (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha           date   NOT NULL,
    tipo            text   NOT NULL CHECK (tipo IN ('retirarse_antes','llegar_tarde','dia_completo','salir_volver')),
    hora_desde      time,
    hora_hasta      time,
    motivo          text,

    estado          text   NOT NULL DEFAULT 'pendiente'
                            CHECK (estado IN ('pendiente','aprobado','rechazado')),

    solicitado_por  text,
    solicitado_at   timestamptz DEFAULT now(),

    revisado_por    text,
    revisado_at     timestamptz,
    revision_motivo text,

    descontar_banco boolean DEFAULT true,
    minutos_descontar int  DEFAULT 0,

    created_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_perm_emp_fecha
    ON rrhh_permisos_puntuales(empleado_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_perm_estado
    ON rrhh_permisos_puntuales(estado, solicitado_at DESC);

-- ═══════════════════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE rrhh_permisos_puntuales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS perm_admin   ON rrhh_permisos_puntuales;
DROP POLICY IF EXISTS perm_gerente ON rrhh_permisos_puntuales;
DROP POLICY IF EXISTS perm_self    ON rrhh_permisos_puntuales;
DROP POLICY IF EXISTS perm_self_insert ON rrhh_permisos_puntuales;

-- Admin: full
CREATE POLICY perm_admin ON rrhh_permisos_puntuales FOR ALL
    USING (EXISTS (
        SELECT 1 FROM rrhh_usuarios u
        WHERE u.auth_user_id = auth.uid() AND u.rol = 'admin' AND u.activo = true
    ));

-- Gerente: full sobre su local
CREATE POLICY perm_gerente ON rrhh_permisos_puntuales FOR ALL
    USING (EXISTS (
        SELECT 1 FROM rrhh_usuarios u
        JOIN rrhh_empleados e ON e.id = rrhh_permisos_puntuales.empleado_id
        WHERE u.auth_user_id = auth.uid()
          AND u.rol = 'gerente'
          AND u.activo = true
          AND e.local = u.local_gerencia
    ));

-- Empleado: ve los suyos
CREATE POLICY perm_self ON rrhh_permisos_puntuales FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM rrhh_usuarios u
        WHERE u.auth_user_id = auth.uid()
          AND u.empleado_id = rrhh_permisos_puntuales.empleado_id
          AND u.activo = true
    ));

-- Empleado: puede crear los suyos (solo estado='pendiente')
CREATE POLICY perm_self_insert ON rrhh_permisos_puntuales FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_permisos_puntuales.empleado_id
              AND u.activo = true
        )
        AND estado = 'pendiente'
    );

-- ═══════════════════════════════════════════════════════════════════════
-- Verificación
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT COUNT(*) FROM rrhh_permisos_puntuales;
-- SELECT tablename FROM pg_tables WHERE tablename = 'rrhh_permisos_puntuales';
