-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Permitir a admin y gerente (encargada) anular
--  vacaciones aprobadas / tomadas / pagadas / rechazadas / canceladas.
--
--  La policy vacmov_self_delete (sql/15_…) solo permite a la vendedora
--  borrar sus propias solicitudes en estado='solicitada'.
--
--  Para que el botón "Anular" del panel de la encargada funcione cuando
--  la vacación ya está aprobada/tomada (con calendar_event_id), hay que
--  habilitar el DELETE explícitamente.
--
--  El gerente solo puede borrar vacaciones de empleados de su mismo local.
--  El admin puede borrar cualquiera.
-- ═══════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS vacmov_admin_delete ON rrhh_vacaciones_movimientos;
DROP POLICY IF EXISTS vacmov_gerente_delete ON rrhh_vacaciones_movimientos;

-- Admin: borra cualquier vacación
CREATE POLICY vacmov_admin_delete ON rrhh_vacaciones_movimientos FOR DELETE
    USING (rrhh_is_admin());

-- Gerente: borra vacaciones de empleados de su local
CREATE POLICY vacmov_gerente_delete ON rrhh_vacaciones_movimientos FOR DELETE
    USING (
        rrhh_is_gerente()
        AND EXISTS (
            SELECT 1 FROM rrhh_empleados e
            WHERE e.id = rrhh_vacaciones_movimientos.empleado_id
              AND e.local = rrhh_gerente_local()
        )
    );
