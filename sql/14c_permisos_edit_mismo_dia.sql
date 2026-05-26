-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Fase E (c): ventana de edición el mismo día del permiso
--
--  Caso de uso:
--    - Vendedora cargó permiso "llegar 1h tarde" el día anterior
--    - La encargada lo aprobó
--    - El día del permiso, se retrasa más de lo previsto (90 min en vez de 60)
--    - Quiere modificar el permiso para reflejar la realidad
--
--  Regla:
--    - Si el permiso está pendiente → puede modificarlo siempre (ya estaba)
--    - Si está aprobado Y fecha = hoy → puede modificarlo, pero vuelve a pendiente
--    - El RLS valida que el nuevo estado sea siempre 'pendiente' (no puede
--      dejarlo aprobado sin revisión de la encargada)
-- ═══════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS perm_self_update ON rrhh_permisos_puntuales;

CREATE POLICY perm_self_update ON rrhh_permisos_puntuales FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_permisos_puntuales.empleado_id
              AND u.activo = true
        )
        AND (
            estado = 'pendiente'
            OR (estado = 'aprobado' AND fecha = CURRENT_DATE)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM rrhh_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empleado_id = rrhh_permisos_puntuales.empleado_id
              AND u.activo = true
        )
        AND estado = 'pendiente'  -- al modificar, vuelve a pendiente
    );
