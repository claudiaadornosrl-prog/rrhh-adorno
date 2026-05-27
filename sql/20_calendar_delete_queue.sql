-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Sync de borrado con Google Calendar
--
--  Flujo:
--    1. Una vacación se sincroniza a Google Calendar (script 11_sync_…)
--       → la fila queda con calendar_event_id no NULL.
--    2. Si después se anula la vacación (DELETE de la fila), un trigger
--       BEFORE DELETE captura calendar_event_id + local del empleado y
--       lo encola en rrhh_calendar_delete_queue.
--    3. El mismo script 11_sync_google_calendar.py procesa la cola al
--       inicio: para cada item, llama Google Calendar API events.delete
--       y elimina la fila de la cola.
--
--  Funciona aunque el DELETE venga de la UI o de SQL directo.
--
--  Nota: usamos dollar-quote etiquetado ($func$) en lugar de $$ porque
--  el SQL Editor de Supabase parsea mal $$ y se confunde con las
--  variables PL/pgSQL (las trata como nombres de tabla).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rrhh_calendar_delete_queue (
    id            bigserial PRIMARY KEY,
    calendar_id   text NOT NULL,         -- email del calendar (unicenter@…, alcorta@…, claudiaadornosrl@gmail.com)
    event_id      text NOT NULL,         -- ID del evento en Google Calendar
    empleado_id   bigint,                -- referencia informativa (no FK porque el empleado puede seguir existiendo)
    fecha_desde   date,                  -- referencia informativa para el log
    fecha_hasta   date,
    queued_at     timestamptz DEFAULT now(),
    processed_at  timestamptz,           -- NULL hasta que se borre OK
    error_msg     text                   -- si falló, queda registrado
);

CREATE INDEX IF NOT EXISTS idx_caldelq_pending
    ON rrhh_calendar_delete_queue(queued_at)
    WHERE processed_at IS NULL;

-- RLS — solo service_role puede leer/escribir la cola (es housekeeping)
ALTER TABLE rrhh_calendar_delete_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS caldelq_service_all ON rrhh_calendar_delete_queue;
CREATE POLICY caldelq_service_all ON rrhh_calendar_delete_queue
    FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- ───────────────────────────────────────────────────────────────────────
--  Trigger: encolar event_id antes de borrar la vacación
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_enqueue_calendar_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $func$
DECLARE
    local_emp text;
    cal_id text;
BEGIN
    -- Solo encolar si había evento sincronizado
    IF OLD.calendar_event_id IS NULL THEN
        RETURN OLD;
    END IF;

    -- Lookup del local del empleado para mapear a calendar_id
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

DROP TRIGGER IF EXISTS trg_vacmov_calendar_delete ON rrhh_vacaciones_movimientos;
CREATE TRIGGER trg_vacmov_calendar_delete
    BEFORE DELETE ON rrhh_vacaciones_movimientos
    FOR EACH ROW
    EXECUTE FUNCTION trg_enqueue_calendar_delete();
