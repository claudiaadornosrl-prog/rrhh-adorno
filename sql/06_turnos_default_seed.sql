-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Seed turnos default
--  Carga los horarios habituales de cada empleado según el info de JP.
--  Ejecutar UNA VEZ después de 05_turnos_y_banco.sql.
--
--  Convención día_semana: 0=domingo, 1=lunes, 2=martes, 3=miércoles,
--                         4=jueves, 5=viernes, 6=sábado
-- ═══════════════════════════════════════════════════════════════════════

-- Helper: vista temporal para mapear empleados por apellido normalizado
WITH emp AS (
    SELECT id, apellido, local FROM rrhh_empleados WHERE estado = 'activo'
),
tpl AS (
    SELECT id, local, codigo FROM rrhh_templates_turno
)

-- (Plantilla solo para referencia — los INSERTs van abajo)
SELECT 1 WHERE false;

-- ───────────────────────────────────────────────────────────────────────
-- UNICENTER (Martínez) — horario base abre 10-22, turnos cargados 15min antes
-- ───────────────────────────────────────────────────────────────────────
-- Grupo MAÑANA (9:45 - 15:45): Sánchez Sonia, Godoy Pamela
-- Grupo TARDE  (15:45 - 22:00): Damela Silvina, Moreira Gabriela, Freccero Estefanía
-- Encargada INTERMEDIO (12:45 - 18:45): Donzelli Soraya
-- Franquera FINDES (sáb+dom 13:45-22): Escasany Ángeles
--
-- Resto de días (lunes a viernes según corresponda) franco para Ángeles.
-- ───────────────────────────────────────────────────────────────────────

-- SÁNCHEZ SONIA — Mañana lunes a sábado, franco domingo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, '09:45', '15:45', false, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6)) AS days(ds)
JOIN rrhh_templates_turno t ON t.local = 'unicenter' AND t.codigo = 'manana'
WHERE e.apellido = 'SANCHEZ'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'seed'
FROM rrhh_empleados e WHERE e.apellido = 'SANCHEZ'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

-- GODOY PAMELA — Mañana lunes a sábado, franco domingo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, '09:45', '15:45', false, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6)) AS days(ds)
JOIN rrhh_templates_turno t ON t.local = 'unicenter' AND t.codigo = 'manana'
WHERE e.apellido = 'GODOY'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'seed' FROM rrhh_empleados e WHERE e.apellido = 'GODOY'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

-- DAMELA SILVINA — Tarde lunes a sábado, franco domingo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, '15:45', '22:00', false, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6)) AS days(ds)
JOIN rrhh_templates_turno t ON t.local = 'unicenter' AND t.codigo = 'tarde'
WHERE e.apellido = 'DAMELA'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'seed' FROM rrhh_empleados e WHERE e.apellido = 'DAMELA'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

-- MOREIRA GABRIELA — Tarde lunes a sábado, franco domingo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, '15:45', '22:00', false, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6)) AS days(ds)
JOIN rrhh_templates_turno t ON t.local = 'unicenter' AND t.codigo = 'tarde'
WHERE e.apellido = 'MOREIRA'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'seed' FROM rrhh_empleados e WHERE e.apellido = 'MOREIRA'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

-- FRECCERO MEZA ESTEFANIA — Tarde lunes a sábado, franco domingo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, '15:45', '22:00', false, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6)) AS days(ds)
JOIN rrhh_templates_turno t ON t.local = 'unicenter' AND t.codigo = 'tarde'
WHERE e.apellido = 'FRECCERO MEZA'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'seed' FROM rrhh_empleados e WHERE e.apellido = 'FRECCERO MEZA'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

-- DONZELLI SORAYA — Encargada, INTERMEDIO lunes a sábado, franco domingo
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, '12:45', '18:45', false, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6)) AS days(ds)
JOIN rrhh_templates_turno t ON t.local = 'unicenter' AND t.codigo = 'intermedio'
WHERE e.apellido = 'DONZELLI'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, 0, true, 'seed' FROM rrhh_empleados e WHERE e.apellido = 'DONZELLI'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

-- ESCASANY ANGELES — FRANQUERA: solo sábado y domingo (8 hs cada uno)
-- L-V franco, sábado 13:45-22:00, domingo 13:45-22:00 (TODO: confirmar horario exacto con JP)
INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, ds, true, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (1),(2),(3),(4),(5)) AS days(ds)
WHERE e.apellido = 'ESCASANY'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, '13:45', '22:00', false, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (6),(0)) AS days(ds)
JOIN rrhh_templates_turno t ON t.local = 'unicenter' AND t.codigo = 'finde_completo'
WHERE e.apellido = 'ESCASANY'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- OFICINA — Lunes a viernes 7:45 - 17:30, sábado y domingo franco
-- Empleados: CONTRERAS Marisa, ADORNO Claudia, SIMONELLI Juan Pablo,
--            MONZON Carlos, RIVERA Analia
-- ───────────────────────────────────────────────────────────────────────

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, template_id, hora_inicio, hora_fin, es_franco, updated_by)
SELECT e.id, ds, t.id, '07:45', '17:30', false, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (1),(2),(3),(4),(5)) AS days(ds)
JOIN rrhh_templates_turno t ON t.local = 'oficina' AND t.codigo = 'completo'
WHERE e.local = 'oficina'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

INSERT INTO rrhh_turnos_default (empleado_id, dia_semana, es_franco, updated_by)
SELECT e.id, ds, true, 'seed'
FROM rrhh_empleados e
CROSS JOIN (VALUES (6),(0)) AS days(ds)
WHERE e.local = 'oficina'
ON CONFLICT (empleado_id, dia_semana, activo_desde) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- ALCORTA — TODO: JP necesita confirmar grupos (mañana/tarde) por empleado
-- Empleados activos en Alcorta:
--   - BENITEZ ROMINA
--   - QUIROGA ELISABETH
--   - COPA LILIANA
--   - BIANCHI MARIA SOLEDAD
--   - NICOLA VALERIA
--   - NOGUERA PARRA ADRIAN
--   - VERON GEORGINA
--
-- Por ahora dejo sin default; la encargada de Alcorta tendrá que armar el calendario manualmente
-- la primera vez. Cuando JP confirme los grupos lo seedeo igual que Unicenter.
-- ───────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════
-- Verificación
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT e.nombre_completo, e.local, td.dia_semana,
--        CASE td.dia_semana
--          WHEN 0 THEN 'Dom' WHEN 1 THEN 'Lun' WHEN 2 THEN 'Mar' WHEN 3 THEN 'Mié'
--          WHEN 4 THEN 'Jue' WHEN 5 THEN 'Vie' WHEN 6 THEN 'Sáb'
--        END AS dia,
--        td.hora_inicio, td.hora_fin, td.es_franco
-- FROM rrhh_turnos_default td
-- JOIN rrhh_empleados e ON e.id = td.empleado_id
-- ORDER BY e.local, e.nombre_completo, td.dia_semana;
