-- ═══════════════════════════════════════════════════════════════════════
--  64_pdf_firmado_path.sql
--
--  Agrega la columna pdf_firmado_path a rrhh_liquidacion para guardar el
--  path en Storage del PDF firmado por la empleada.
--  Usado por el lector bulk de recibos firmados (Liquidador → 📥 Cargar firmados).
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE public.rrhh_liquidacion
    ADD COLUMN IF NOT EXISTS pdf_firmado_path text;

COMMENT ON COLUMN public.rrhh_liquidacion.pdf_firmado_path IS
    'Path en bucket rrhh-recibos del PDF firmado. Convención: {empleado_id}/recibo_{liq.id}_firmado.pdf';

NOTIFY pgrst, 'reload schema';

-- Verificación
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'rrhh_liquidacion'
  AND column_name LIKE 'pdf_%'
ORDER BY column_name;
