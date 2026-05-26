-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Defaults FINALES basados en data real + decisiones JP
--
--  Cambios desde el 08:
--    - Unicenter: SIN default en findes (rotación quincenal — manual)
--    - Liliana Copa (Alcorta): SIN default en findes (manual)
--    - Georgina Verón (Alcorta): Lun franco, Mar-Vie Tarde,
--                                 Sáb-Dom custom 13:45-21
--    - Ángeles Escasany (Unicenter franquera): L-V franco, S+D findes 8hs
--
--  Templates corregidos (ya hechos en 08):
--    - Unicenter Mañana: 9:45-16
--    - Unicenter Intermedio: 12:45-19
--    - Alcorta Intermedio: 12:45-19
--
--  Ejecutar UNA VEZ en Supabase. Reemplaza al 08 completo.
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Templates (idempotente, por si no se corrió el 08)
UPDATE rrhh_templates_turno
SET hora_fin = '16:00', nombre = 'Mañana 9:45-16'
WHERE local='unicenter' AND codigo='manana';

UPDATE rrhh_templates_turno
SET hora_fin = '19:00', nombre = 'Intermedio 12:45-19'
WHERE local='unicenter' AND codigo='intermedio';

UPDATE rrhh_templates_turno
SET hora_inicio = '12:45', nombre = 'Intermedio 12:45-19'
WHERE local='alcorta' AND codigo='intermedio';

-- 2) Limpiar TODO antes de recargar
DELETE FROM rrhh_turnos_default
WHERE empleado_id IN (SELECT id FROM rrhh_empleados WHERE local IN ('unicenter','alcorta','oficina'));


-- ═══════════════════════════════════════════════════════════════════════
-- UNICENTER — Solo L-V con default (findes manuales por la encargada)
-- Excepción: Ángeles (franquera) — L-V franco, S+D findes
-- ═══════════════════════════════════════════════════════════════════════

-- SÁNCHEZ Sonia — Mañana L-V
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='manana'
WHERE e.apellido='SANCHEZ';

-- GODOY Pamela — Mañana L-V
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='manana'
WHERE e.apellido='GODOY';

-- DAMELA Silvina — Tarde L-V
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='DAMELA';

-- MOREIRA Gabriela — Tarde L-V
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='MOREIRA';

-- FRECCERO Estefanía — Tarde L-V
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='FRECCERO MEZA';

-- DONZELLI Soraya (encargada) — Intermedio L-V
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='intermedio'
WHERE e.apellido='DONZELLI';

-- ESCASANY Ángeles (franquera) — L-V franco, S+D fin de semana
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, ds, true, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
WHERE e.apellido='ESCASANY';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='ESCASANY';


-- ═══════════════════════════════════════════════════════════════════════
-- ALCORTA — Default completo L-D (estable)
-- Excepciones:
--   - Liliana Copa: solo L-V (findes manuales)
--   - Georgina Verón: Lun franco, Mar-Vie Tarde, S+D custom 13:45-21
-- ═══════════════════════════════════════════════════════════════════════

-- BENITEZ Romina — Mañana L-V, Sáb Completo, Dom franco
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='BENITEZ';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 6, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='BENITEZ';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'final-real' FROM rrhh_empleados e WHERE e.apellido='BENITEZ';

-- QUIROGA Elizabeth — Mañana L-V, Sáb Completo, Dom franco
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='QUIROGA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 6, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='QUIROGA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'final-real' FROM rrhh_empleados e WHERE e.apellido='QUIROGA';

-- COPA Liliana — Mañana L-V, FINDES VACÍOS (sin default → la encargada los carga)
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='COPA';

-- BIANCHI Soledad — Tarde L-V, Sáb franco, Dom Completo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='BIANCHI';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 6, true, 'final-real' FROM rrhh_empleados e WHERE e.apellido='BIANCHI';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 0, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='BIANCHI';

-- NICOLA Valeria — Tarde L-V, Sáb franco, Dom Completo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='NICOLA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 6, true, 'final-real' FROM rrhh_empleados e WHERE e.apellido='NICOLA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 0, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='NICOLA';

-- NOGUERA PARRA Adrián — Tarde Lun, Intermedio Mar-Vie, Sáb franco, Dom Completo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 1, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='NOGUERA PARRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='intermedio'
WHERE e.apellido='NOGUERA PARRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 6, true, 'final-real' FROM rrhh_empleados e WHERE e.apellido='NOGUERA PARRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 0, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='NOGUERA PARRA';

-- VERON Georgina — Lun franco, Mar-Vie Tarde, Sáb+Dom custom 13:45-21
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 1, true, 'final-real' FROM rrhh_empleados e WHERE e.apellido='VERON';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='VERON';
-- Findes: custom (sin template, hora ad-hoc 13:45 a 21:00)
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, '13:45', '21:00', false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
WHERE e.apellido='VERON';


-- ═══════════════════════════════════════════════════════════════════════
-- OFICINA — Completo L-V, franco S+D
-- ═══════════════════════════════════════════════════════════════════════
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='oficina' AND t.codigo='completo'
WHERE e.local='oficina';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, ds, true, 'final-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
WHERE e.local='oficina';


-- ═══════════════════════════════════════════════════════════════════════
-- Verificación: cuántos defaults por empleado
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT e.local, e.nombre_completo, COUNT(td.id) AS dias_default
-- FROM rrhh_empleados e
-- LEFT JOIN rrhh_turnos_default td ON td.empleado_id = e.id
-- WHERE e.estado='activo'
-- GROUP BY e.local, e.nombre_completo
-- ORDER BY e.local, e.nombre_completo;
--
-- Esperado:
--   Unicenter Sonia, Pamela, Silvina, Gabriela, Estefi, Soraya: 5 días (L-V)
--   Unicenter Ángeles: 7 días (L-V franco + S/D finde)
--   Alcorta Romina, Elizabeth, Bianchi, Nicola, Adrián, Georgina: 7 días
--   Alcorta Liliana: 5 días (L-V, sin findes)
--   Oficina (5 empleados): 7 días cada uno
