-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Permitir a la vendedora MODIFICAR/ANULAR sus propias
--  solicitudes de vacaciones mientras estén en estado='solicitada'.
-- ═══════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS vacmov_self_update ON rrhh_vacaciones_movimientos;
DROP POLICY IF EXISTS vacmov_self_delete ON rrhh_vacaciones_movimientos;

CREATE POLICY vacmov_self_update ON rrhh_vacaciones_movimientos FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_vacaciones_movimientos.empleado_id
              AND u.activo = true
        )
        AND estado = 'solicitada'
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_vacaciones_movimientos.empleado_id
              AND u.activo = true
        )
        AND estado = 'solicitada'
    );

CREATE POLICY vacmov_self_delete ON rrhh_vacaciones_movimientos FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_vacaciones_movimientos.empleado_id
              AND u.activo = true
        )
        AND estado = 'solicitada'
    );
