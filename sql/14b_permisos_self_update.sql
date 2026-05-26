-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Fase E (b): Permitir a la vendedora MODIFICAR/ANULAR
--  sus propios permisos mientras estén en estado='pendiente'.
-- ═══════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS perm_self_update ON rrhh_permisos_puntuales;
DROP POLICY IF EXISTS perm_self_delete ON rrhh_permisos_puntuales;

-- Empleado: UPDATE de sus propios permisos PENDIENTES
CREATE POLICY perm_self_update ON rrhh_permisos_puntuales FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_permisos_puntuales.empleado_id
              AND u.activo = true
        )
        AND estado = 'pendiente'
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_permisos_puntuales.empleado_id
              AND u.activo = true
        )
        AND estado = 'pendiente'
    );

-- Empleado: DELETE de sus propios permisos PENDIENTES
CREATE POLICY perm_self_delete ON rrhh_permisos_puntuales FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_permisos_puntuales.empleado_id
              AND u.activo = true
        )
        AND estado = 'pendiente'
    );
