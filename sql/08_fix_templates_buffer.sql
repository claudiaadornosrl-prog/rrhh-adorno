-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Corrección templates: buffer solo en entrada
--
--  Convención (aclarada por JP):
--    - Entrada cargada = horario REAL - 15 min (buffer)
--    - Salida cargada  = horario REAL (sin buffer)
--
--  Templates a corregir:
--    Unicenter Mañana   : 9:45  → 16:00  (era 9:45 → 15:45)
--    Unicenter Intermedio: 12:45 → 19:00  (era 12:45 → 18:45)
--    Alcorta   Intermedio: 12:45 → 19:00  (era 13:00 → 19:00, faltaba buffer entrada)
--
--  Después de actualizar los templates, re-cargo los turnos_default
--  para que tomen los nuevos valores.
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Corregir templates
UPDATE rrhh_templates_turno
SET hora_fin    = '16:00',
    nombre      = 'Mañana 9:45-16'
WHERE local='unicenter' AND codigo='manana';

UPDATE rrhh_templates_turno
SET hora_fin    = '19:00',
    nombre      = 'Intermedio 12:45-19'
WHERE local='unicenter' AND codigo='intermedio';

UPDATE rrhh_templates_turno
SET hora_inicio = '12:45',
    nombre      = 'Intermedio 12:45-19'
WHERE local='alcorta' AND codigo='intermedio';

-- 2) Borrar defaults para volver a cargar con los valores correctos del template
DELETE FROM rrhh_turnos_default
WHERE empleado_id IN (SELECT id FROM rrhh_empleados WHERE local IN ('unicenter','alcorta','oficina'));

-- 3) Re-cargar defaults — mismo contenido que el 07, pero ahora los templates tienen los valores corregidos

-- ===== UNICENTER =====
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='manana'
WHERE e.apellido='SANCHEZ';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='SANCHEZ';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='manana'
WHERE e.apellido='GODOY';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='GODOY';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='DAMELA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='DAMELA';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='MOREIRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='MOREIRA';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='FRECCERO MEZA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='FRECCERO MEZA';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='intermedio'
WHERE e.apellido='DONZELLI';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='DONZELLI';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, ds, true, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
WHERE e.apellido='ESCASANY';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='ESCASANY';


-- ===== ALCORTA =====
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='BENITEZ';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 6, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='BENITEZ';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'fix-buffer' FROM rrhh_empleados e WHERE e.apellido='BENITEZ';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='QUIROGA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='QUIROGA';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='COPA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='COPA';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='BIANCHI';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='BIANCHI';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='NICOLA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='NICOLA';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 1, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='NOGUERA PARRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='intermedio'
WHERE e.apellido='NOGUERA PARRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='NOGUERA PARRA';

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='VERON';


-- ===== OFICINA =====
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='oficina' AND t.codigo='completo'
WHERE e.local='oficina';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, ds, true, 'fix-buffer'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
WHERE e.local='oficina';

-- ═══════════════════════════════════════════════════════════════════════
-- Verificación de los templates corregidos
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT local, codigo, nombre, hora_inicio, hora_fin FROM rrhh_templates_turno
-- WHERE codigo IN ('manana','intermedio') AND local IN ('unicenter','alcorta')
-- ORDER BY local, codigo;
-- Esperado:
--   alcorta   intermedio  Intermedio 12:45-19  12:45  19:00
--   alcorta   manana      Mañana 9:45-16        09:45  16:00
--   unicenter intermedio  Intermedio 12:45-19   12:45  19:00
--   unicenter manana      Mañana 9:45-16        09:45  16:00
