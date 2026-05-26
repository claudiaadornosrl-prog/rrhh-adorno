-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Turnos default basados en data real de 3 meses
--  Análisis de fichadas marzo-mayo 2026 (2180 fichadas).
--
--  Reemplaza los seeds del 06 con valores deducidos de la mediana
--  por (empleado, día_semana). Sobreescribe los existentes.
-- ═══════════════════════════════════════════════════════════════════════

-- Borrar defaults previos para volver a cargar
DELETE FROM rrhh_turnos_default
WHERE empleado_id IN (SELECT id FROM rrhh_empleados WHERE local IN ('unicenter','alcorta','oficina'));

-- Helper local: insertar 1 fila por (apellido, día_semana, template)
-- dia_semana: 0=Dom, 1=Lun, 2=Mar, 3=Mié, 4=Jue, 5=Vie, 6=Sáb

-- ═══════════════════════════════════════════════════════════════════════
-- UNICENTER (analizado sobre 894 fichadas)
-- ═══════════════════════════════════════════════════════════════════════

-- SÁNCHEZ Sonia Luz — Mañana L-V, Fin de semana S+D (data: 9:50-16:05 L-V, 9:55-22:00 S-D)
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='manana'
WHERE e.apellido='SANCHEZ';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='SANCHEZ';

-- GODOY Pamela — Mañana L-V, Fin de semana S+D (data: 9:50-15:17 L-V, 10:00-22:00 S-D)
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='manana'
WHERE e.apellido='GODOY';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='GODOY';

-- DAMELA Silvina — Tarde L-V, Fin de semana S+D (data: 15:53-22:00 L-V, 9:43-22:00 S-D)
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='DAMELA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='DAMELA';

-- MOREIRA Gabriela — Tarde L-V, Fin de semana S+D
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='MOREIRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='MOREIRA';

-- FRECCERO Estefanía — Tarde L-V, Fin de semana S+D
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='tarde'
WHERE e.apellido='FRECCERO MEZA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='FRECCERO MEZA';

-- DONZELLI Soraya (encargada) — Intermedio L-V, Fin de semana S+D
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='intermedio'
WHERE e.apellido='DONZELLI';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='DONZELLI';

-- ESCASANY Ángeles (franquera) — L-V franco, S+D Fin de semana
-- NOTA: la data muestra que también trabaja muchos días L-V, pero JP especificó solo findes
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, ds, true, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
WHERE e.apellido='ESCASANY';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='unicenter' AND t.codigo='finde_completo'
WHERE e.apellido='ESCASANY';


-- ═══════════════════════════════════════════════════════════════════════
-- ALCORTA (analizado sobre 988 fichadas)
-- ═══════════════════════════════════════════════════════════════════════

-- BENITEZ Romina — Mañana L-V, Completo Sáb, Franco Dom
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='BENITEZ';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 6, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='BENITEZ';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'analisis-real' FROM rrhh_empleados e WHERE e.apellido='BENITEZ';

-- QUIROGA Elizabeth — Mañana L-V, Completo S+D
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='QUIROGA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='QUIROGA';

-- COPA Liliana — Mañana L-V, Completo S+D
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='manana'
WHERE e.apellido='COPA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='COPA';

-- BIANCHI Soledad — Tarde L-V, Completo S+D
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='BIANCHI';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='BIANCHI';

-- NICOLA Valeria — Tarde L-V, Completo S+D
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='NICOLA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='NICOLA';

-- NOGUERA PARRA Adrián — Tarde Lun, Intermedio Mar-Vie, Completo S+D
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, 1, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='NOGUERA PARRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='intermedio'
WHERE e.apellido='NOGUERA PARRA';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='completo'
WHERE e.apellido='NOGUERA PARRA';

-- VERON Georgina — Tarde TODOS los días (única vendedora que trabaja 7/7 turno tarde)
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6)) days(ds)
JOIN rrhh_templates_turno t ON t.local='alcorta' AND t.codigo='tarde'
WHERE e.apellido='VERON';


-- ═══════════════════════════════════════════════════════════════════════
-- OFICINA — Completo L-V, franco S+D (confirmado por data)
-- ═══════════════════════════════════════════════════════════════════════
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, t.hora_inicio, t.hora_fin, false, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (1),(2),(3),(4),(5)) days(ds)
JOIN rrhh_templates_turno t ON t.local='oficina' AND t.codigo='completo'
WHERE e.local='oficina';
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, ds, true, 'analisis-real'
FROM rrhh_empleados e CROSS JOIN (VALUES (6),(0)) days(ds)
WHERE e.local='oficina';


-- ═══════════════════════════════════════════════════════════════════════
-- Verificación — cuántos defaults quedaron cargados por empleado
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT e.local, e.nombre_completo, COUNT(*) AS dias_default
-- FROM rrhh_empleados e
-- JOIN rrhh_turnos_default td ON td.empleado_id = e.id
-- WHERE e.estado='activo'
-- GROUP BY e.local, e.nombre_completo
-- ORDER BY e.local, e.nombre_completo;
-- Esperado: cada empleado activo con 7 filas (una por día de semana)
