-- ═══════════════════════════════════════════════════════════════════════
--  57_lsd_fix_codigos_reales.sql
--  Fix de códigos AFIP validados contra TXT real del estudio (abril 2026).
--
--  Diferencias detectadas:
--   • Código OS OSECAC: 126203 (mi seed) → 126205 (real)
--   • Actividad default: 478 (CIIU truncado) → 049 (código AFIP "Actividades")
--   • Localidad default: 01 → 02
--   • Conceptos: NO usar mapeo AFIP — el estudio manda códigos internos
--     directamente. Marcar el mapeo como "deprecated" pero conservar.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Corregir código OSECAC ──────────────────────────────────────
UPDATE public.rrhh_lsd_obra_social_catalogo
   SET codigo = '126205'
 WHERE codigo = '126203' AND sigla = 'OSECAC';

UPDATE public.rrhh_empleados
   SET os_codigo_afip = '126205'
 WHERE os_codigo_afip = '126203';

-- ─── 2. Cambiar defaults de actividad y localidad ───────────────────
ALTER TABLE public.rrhh_empleados
    ALTER COLUMN actividad_codigo SET DEFAULT '049';

UPDATE public.rrhh_empleados
   SET actividad_codigo = '049'
 WHERE actividad_codigo = '478996' OR actividad_codigo IS NULL;

-- Localidad: agregar campo si no existe, default '02' (¿provincia BsAs?)
ALTER TABLE public.rrhh_empleados
    ADD COLUMN IF NOT EXISTS localidad_codigo text DEFAULT '02';

UPDATE public.rrhh_empleados SET localidad_codigo = '02' WHERE localidad_codigo IS NULL;

COMMENT ON COLUMN public.rrhh_empleados.localidad_codigo IS
    'Código de localidad AFIP (2 dígitos). 02 = uso histórico del estudio. Verificar con tabla "Localidades Geográficas".';

-- ─── 3. Marcar el mapeo de conceptos como NO usado ──────────────────
-- El estudio manda los códigos internos (0001, 0022, ...) directamente.
-- El mapeo a códigos AFIP (110000, 160001, ...) NO se usa.
-- Lo conservamos por si queremos reusarlo en futuro o para reportes.

COMMENT ON TABLE public.rrhh_lsd_concepto_mapeo IS
    'Mapeo opcional a códigos oficiales AFIP. El generador LSD actualmente NO lo usa — manda códigos internos directamente como el estudio.';

NOTIFY pgrst, 'reload schema';

-- Verificación
SELECT
  (SELECT codigo FROM rrhh_lsd_obra_social_catalogo WHERE sigla='OSECAC') AS osecac_codigo,
  (SELECT count(*) FROM rrhh_empleados WHERE os_codigo_afip = '126205') AS empleados_osecac,
  (SELECT count(*) FROM rrhh_empleados WHERE actividad_codigo = '049') AS empleados_act_049,
  (SELECT count(*) FROM rrhh_empleados WHERE localidad_codigo = '02') AS empleados_loc_02;
