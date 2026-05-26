-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Tracking del documento firmado de vacaciones
--
--  Cuando la encargada aprueba una vacación:
--    1. El sistema genera un PDF con código identificador (VAC-<id>)
--    2. Imprimen, firman, escanean y mandan a claudiaadornosrl@gmail.com
--    3. Un proceso automático identifica el mail por el código y guarda
--       el PDF firmado en OneDrive en la carpeta del empleado.
--    4. Estas columnas guardan el estado del documento firmado.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE rrhh_vacaciones_movimientos
    ADD COLUMN IF NOT EXISTS documento_firmado_path  text,         -- Ruta en OneDrive
    ADD COLUMN IF NOT EXISTS documento_firmado_at    timestamptz,  -- Cuándo se recibió
    ADD COLUMN IF NOT EXISTS documento_firmado_origen text,        -- 'mail' | 'manual' | 'sistema'
    ADD COLUMN IF NOT EXISTS calendar_event_id       text,         -- ID del evento en Google Calendar
    ADD COLUMN IF NOT EXISTS calendar_sync_pending   boolean DEFAULT false;  -- True cuando hay que crear/actualizar evento

CREATE INDEX IF NOT EXISTS idx_vacmov_doc_firmado
    ON rrhh_vacaciones_movimientos(documento_firmado_at)
    WHERE documento_firmado_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_vacmov_cal_pending
    ON rrhh_vacaciones_movimientos(calendar_sync_pending)
    WHERE calendar_sync_pending = true;
