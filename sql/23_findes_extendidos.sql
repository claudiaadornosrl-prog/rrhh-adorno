-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Findes con horario extendido (corrección)
--
--  Regla operativa (JP):
--    Las vendedoras NO franqueras que trabajan un solo día del finde
--    cubren TODO el horario de apertura del local:
--      - Unicenter: 10:00 → 22:00 (12 hs)  → cargado 09:45 → 22:00 (buffer 15')
--      - Alcorta:   10:00 → 21:00 (11 hs)  → cargado 09:45 → 21:00 (buffer 15')
--
--  Problema: el template unicenter/finde_completo estaba en 13:45 → 22:00
--  ("Fin de semana 8hs"), que era un turno tarde, no el extendido completo.
--
--  Convención de buffer: entrada cargada = apertura real − 15 min
--  (igual que el resto de los templates, ej. "Mañana 9:45-16").
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Unicenter: corregir el template de finde a 12 hs ───
UPDATE rrhh_templates_turno
SET hora_inicio = '09:45',
    hora_fin    = '22:00',
    nombre      = 'Fin de semana 12hs'
WHERE local = 'unicenter' AND codigo = 'finde_completo';

-- ─── 2. Alcorta: crear template de finde 11 hs (nombre claro) ───
--     Su 'completo' (09:45-21) ya tenía el horario correcto, pero creamos
--     un finde_completo dedicado para que el dropdown muestre "Fin de semana 11hs"
--     consistente con Unicenter.
INSERT INTO rrhh_templates_turno (local, codigo, nombre, hora_inicio, hora_fin, es_franco, color, icono, orden)
VALUES ('alcorta', 'finde_completo', 'Fin de semana 11hs', '09:45', '21:00', false, '#a855f7', '📅', 5)
ON CONFLICT (local, codigo) DO UPDATE
    SET hora_inicio = EXCLUDED.hora_inicio,
        hora_fin    = EXCLUDED.hora_fin,
        nombre      = EXCLUDED.nombre;

-- ─── 3. Corregir turnos default que apuntaban al finde viejo ───
--     (las horas se copian del template al crearse, así que hay que
--      actualizarlas explícitamente en los defaults ya existentes)
UPDATE rrhh_turnos_default d
SET hora_inicio = '09:45', hora_fin = '22:00'
FROM rrhh_templates_turno t
WHERE d.template_id = t.id
  AND t.local = 'unicenter'
  AND t.codigo = 'finde_completo'
  AND d.es_franco = false;

-- Verificación
-- SELECT local, codigo, nombre, hora_inicio, hora_fin
-- FROM rrhh_templates_turno WHERE codigo = 'finde_completo' ORDER BY local;
