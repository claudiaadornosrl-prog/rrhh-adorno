-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Fix RLS para el trigger de cola de borrados
--
--  Síntoma: al anular una vacación desde el RRHH (logueado como gerente),
--           el INSERT del trigger en rrhh_calendar_delete_queue fallaba con
--           "new row violates row-level security policy".
--
--  Causa:   la policy caldelq_service_all solo permite a service_role.
--           El trigger se ejecuta con los privilegios del usuario que hace
--           el DELETE (gerente / authenticated), que no tiene permiso de
--           INSERT en la cola.
--
--  Fix:     marcar la función del trigger como SECURITY DEFINER. Así
--           corre con los privilegios del owner (postgres) y puede
--           escribir en la cola sin importar quién dispare el DELETE.
--           Esto es seguro porque la función SOLO inserta una entrada
--           en la cola (no expone datos).
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_enqueue_calendar_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    local_emp text;
    cal_id text;
BEGIN
    IF OLD.calendar_event_id IS NULL THEN
        RETURN OLD;
    END IF;

    SELECT local INTO local_emp FROM rrhh_empleados WHERE id = OLD.empleado_id;

    cal_id := CASE local_emp
        WHEN 'unicenter' THEN 'unicenter@claudiaadorno.com'
        WHEN 'alcorta'   THEN 'alcorta@claudiaadorno.com'
        WHEN 'oficina'   THEN 'claudiaadornosrl@gmail.com'
        ELSE 'unknown'
    END;

    INSERT INTO rrhh_calendar_delete_queue
        (calendar_id, event_id, empleado_id, fecha_desde, fecha_hasta)
    VALUES
        (cal_id, OLD.calendar_event_id, OLD.empleado_id, OLD.fecha_desde, OLD.fecha_hasta);

    RETURN OLD;
END;
$func$;
