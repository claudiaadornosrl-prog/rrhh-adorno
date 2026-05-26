-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Marcar empleados que NO fichan
--
--  Algunos empleados (directores, fuera de convenio) no fichan en Anviz.
--  Los excluimos del cruce y de la generación de turnos.
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Columna ficha (true por default)
ALTER TABLE rrhh_empleados
    ADD COLUMN IF NOT EXISTS ficha boolean DEFAULT true;

-- 2) Marcar a los que NO fichan
UPDATE rrhh_empleados
SET ficha = false
WHERE dni IN (
    '13531903',  -- ADORNO CLAUDIA VIVIANA (directora)
    '36754687'   -- SIMONELLI JUAN PABLO (fuera de convenio)
);

-- 3) Borrar sus turnos_default y turnos (si existieran)
DELETE FROM rrhh_turnos_default
WHERE empleado_id IN (
    SELECT id FROM rrhh_empleados WHERE ficha = false
);

DELETE FROM rrhh_turnos
WHERE empleado_id IN (
    SELECT id FROM rrhh_empleados WHERE ficha = false
);

-- ═══════════════════════════════════════════════════════════════════════
-- Verificación
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT nombre_completo, dni, ficha FROM rrhh_empleados WHERE estado='activo' ORDER BY ficha, nombre_completo;
-- Esperado: 17 con ficha=true, 2 con ficha=false (Adorno + Simonelli)
