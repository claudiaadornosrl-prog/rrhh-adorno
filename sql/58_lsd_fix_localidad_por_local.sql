-- ═══════════════════════════════════════════════════════════════════════
--  58_lsd_fix_localidad_por_local.sql
--  Corrección: localidad AFIP según LOCAL donde trabaja la empleada.
--
--  Verificado contra TXT real del estudio (abril 2026):
--   • Alcorta (CABA)              → código localidad '01' (Capital Federal)
--   • Unicenter + Oficina (BsAs)  → código localidad '02' (Buenos Aires)
-- ═══════════════════════════════════════════════════════════════════════

-- Alcorta (Palermo, CABA) → 01
UPDATE public.rrhh_empleados
   SET localidad_codigo = '01'
 WHERE local = 'alcorta';

-- Unicenter + Oficina (Provincia BsAs) → 02
UPDATE public.rrhh_empleados
   SET localidad_codigo = '02'
 WHERE local IN ('unicenter', 'oficina');

-- Verificación
SELECT
  local,
  localidad_codigo,
  count(*) AS empleados
FROM rrhh_empleados
WHERE estado = 'activo'
GROUP BY local, localidad_codigo
ORDER BY local;
