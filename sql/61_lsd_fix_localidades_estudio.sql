-- ═══════════════════════════════════════════════════════════════════════
--  61_lsd_fix_localidades_estudio.sql
--
--  Localidades AFIP per CUIL extraídas del TXT LSD del estudio abril 2026.
--  En AFIP la localidad va por DOMICILIO del empleado, no por lugar de
--  trabajo. Mi SQL 58 los puso por local (alcorta=01, unicenter/oficina=02),
--  pero el estudio tiene 3 casos donde difiere:
--   - DONZELLI: Unicenter pero vive en CABA → 01
--   - SANCHEZ: Unicenter pero vive en CABA → 01
--   - MOREIRA: Unicenter (era Alcorta) → 01 (estudio histórico)
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- Empleadas con localidad distinta al local de trabajo (según estudio):
UPDATE rrhh_empleados SET localidad_codigo = '01' WHERE cuil = '27-31741055-2'; -- DONZELLI vive CABA
UPDATE rrhh_empleados SET localidad_codigo = '01' WHERE cuil = '27-22275528-5'; -- SANCHEZ vive CABA
UPDATE rrhh_empleados SET localidad_codigo = '01' WHERE cuil = '20-29168551-0'; -- MOREIRA legacy

-- (todas las demás respetan la regla: alcorta=01, unicenter/oficina=02
--  por lo que ya están bien del SQL 58)

COMMIT;

-- Verificación
SELECT
  apellido, cuil, local, localidad_codigo
FROM rrhh_empleados
WHERE estado = 'activo'
ORDER BY apellido;
