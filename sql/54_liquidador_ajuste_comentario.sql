-- ═══════════════════════════════════════════════════════════════════════
--  54_liquidador_ajuste_comentario.sql
--  Agrega columna ajuste_comentario en rrhh_liquidacion para guardar
--  el motivo del ajuste cargado por el admin.
--
--  Modelo simple: el comentario VIVE en la fila de la liquidación del mes.
--  Para ver el "histórico" se consulta rrhh_liquidacion con orden por
--  período. No hacemos tabla separada — alcanza con tener el campo
--  en cada mes.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE public.rrhh_liquidacion
    ADD COLUMN IF NOT EXISTS ajuste_comentario text;

COMMENT ON COLUMN public.rrhh_liquidacion.ajuste_comentario IS
    'Motivo / nota libre del ajuste manual cargado por el admin. Visible al pasar el mouse sobre la celda Ajustes en el liquidador.';

NOTIFY pgrst, 'reload schema';

-- Verificación
SELECT column_name, data_type, col_description('public.rrhh_liquidacion'::regclass, ordinal_position) AS notas
  FROM information_schema.columns
 WHERE table_schema='public' AND table_name='rrhh_liquidacion'
   AND column_name IN ('ajuste','ajuste_comentario','prestamo_interes','mercaderia');
