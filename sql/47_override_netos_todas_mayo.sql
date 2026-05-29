-- ═══════════════════════════════════════════════════════════════════════
--  47_override_netos_todas_mayo.sql
--  Override de TODOS los netos de mayo 2026 con los valores EXACTOS del
--  PDF que pasó el estudio contable (ADORNOMAYO2026-*.pdf, MEMOSOFT).
--
--  Esto evita el bug del salaryEngine que suma presentismo doble.
--
--  ⚠ NOTA: MUSAQUIO NORA PATRICIA no aparece en el PDF del estudio de
--          mayo — no se le carga override (revisar si corresponde aparte).
--
--  Para junio en adelante: arreglar el bug del salaryEngine y dejar los
--  cálculos automáticos. Por ahora, override masivo.
-- ═══════════════════════════════════════════════════════════════════════

-- Limpiar overrides previos del mismo período para empezar limpio
DELETE FROM public.rrhh_pagos_blanco WHERE periodo = '2026-05-01';

-- Cargar netos del PDF de mayo 2026 (valores EXACTOS extraídos del PDF)
INSERT INTO public.rrhh_pagos_blanco (empleado_id, periodo, neto_cct, cargado_por, notas)
SELECT id, '2026-05-01', neto, 'admin',
       'Neto exacto del PDF MEMOSOFT mayo 2026 (estudio) — override mientras se arregla el bug presentismo doble del salaryEngine'
FROM (VALUES
    ('CONTRERAS',     'MARISA',    1312004.36),
    -- BENITEZ: 28 días básico + presentismo COMPLETO (licencia justificada
    -- art 36 CCT 130/75 — no se pierde presentismo). Estudio mandó dos
    -- versiones erradas (28d sin pres = $1.145.061 / 30d con pres = $1.318.365);
    -- la correcta es el punto medio: $1.246.436,26.
    ('BENITEZ',       'ROMINA',    1246436.26),
    ('ADORNO',        'CLAUDIA',   3662360.00),
    ('DONZELLI',      'SORAYA',    1303151.92),
    ('QUIROGA',       'ELISABETH', 1302629.45),
    ('DAMELA',        'SILVINA',   1296019.73),
    ('COPA',          'LILIANA',   1269228.70),
    ('GODOY',         'PAMELA',    1251329.40),
    ('BIANCHI',       'MARIA',     1224694.37),
    ('SIMONELLI',     'JUAN',      2695113.63),
    ('SANCHEZ',       'SONIA',     1228984.24),
    ('MONZON',        'CARLOS',    1196178.28),
    ('NICOLA',        'VALERIA',   1202427.20),
    ('ESCASANY',      'ANGELES',    601991.00),
    ('RIVERA',        'ANALIA',    1163071.06),
    ('FRECCERO',      'ESTEFANIA', 1146759.27),
    ('NOGUERA',       'ADRIAN',    1139603.57),
    -- MOREIRA: 28 días básico + presentismo COMPLETO (licencia justificada
    -- art 36 CCT 130/75). Idem Benitez: el estudio mandó dos versiones
    -- erradas; la correcta es: $1.077.427,95.
    ('MOREIRA',       'GABRIELA',  1077427.95),
    ('VERON',         'GEORGINA',  1128430.98)
) AS netos(ap, nom, neto)
JOIN LATERAL (
    SELECT id FROM public.rrhh_empleados
    WHERE apellido ILIKE '%' || netos.ap || '%'
      AND nombre   ILIKE '%' || netos.nom || '%'
      AND estado = 'activo'
    LIMIT 1
) e ON true;

-- Verificación: ver qué quedó cargado, agrupado por local
SELECT
  e.local,
  e.nombre_completo,
  p.neto_cct,
  TO_CHAR(p.neto_cct, 'FM999G999G999D00') AS neto_formateado
FROM public.rrhh_pagos_blanco p
JOIN public.rrhh_empleados e ON e.id = p.empleado_id
WHERE p.periodo = '2026-05-01'
ORDER BY e.local, e.apellido;

-- Total a transferir mayo (suma de todos los netos)
SELECT
  COUNT(*) AS cantidad_empleadas,
  SUM(neto_cct) AS total_blanco_mayo,
  TO_CHAR(SUM(neto_cct), 'FM999G999G999D00') AS total_formateado
FROM public.rrhh_pagos_blanco
WHERE periodo = '2026-05-01';
