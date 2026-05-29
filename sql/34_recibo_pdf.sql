-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Workflow de firma del recibo PDF
--
--  Estados del recibo:
--    borrador → calculado (al generarse) → enviado (PDF mandado por mail)
--                                       → firmado (la empleada devolvió el PDF firmado)
--
--  Para no atar TODO el flujo al cambio de `estado`, agregamos columnas
--  específicas que registran solo lo del PDF / firma. El `estado` general
--  de la liquidación sigue siendo borrador/aprobado/pagado como hasta ahora.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE rrhh_liquidacion
    ADD COLUMN IF NOT EXISTS pdf_generado_at   timestamptz,
    ADD COLUMN IF NOT EXISTS pdf_enviado_at    timestamptz,
    ADD COLUMN IF NOT EXISTS pdf_enviado_por   text,
    ADD COLUMN IF NOT EXISTS pdf_firmado_at    timestamptz,
    ADD COLUMN IF NOT EXISTS pdf_url_firmado   text;

COMMENT ON COLUMN rrhh_liquidacion.pdf_generado_at IS
'Última vez que se descargó/generó el PDF del recibo.';
COMMENT ON COLUMN rrhh_liquidacion.pdf_enviado_at IS
'Cuándo se envió el PDF por email a la empleada para firmar.';
COMMENT ON COLUMN rrhh_liquidacion.pdf_enviado_por IS
'Email del usuario admin que disparó el envío.';
COMMENT ON COLUMN rrhh_liquidacion.pdf_firmado_at IS
'Cuándo la empleada devolvió el PDF firmado (auto-procesado vía Gmail).';
COMMENT ON COLUMN rrhh_liquidacion.pdf_url_firmado IS
'URL en Supabase Storage del PDF firmado (después de procesar la respuesta).';

CREATE INDEX IF NOT EXISTS idx_liquidacion_pdf_workflow
    ON rrhh_liquidacion(pdf_enviado_at, pdf_firmado_at);
