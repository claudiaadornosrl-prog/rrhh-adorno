-- ═══════════════════════════════════════════════════════════════════════
--  43_override_netos_benitez_moreira.sql
--  Override manual de los netos de Benitez y Moreira para mayo 2026.
--  Caso: MEMOSOFT les descontó 2 días por licencia "enfermedad familiar"
--        que el CCT 130/75 art. 36 establece como CON goce (hasta 2/año).
--        Esos $60.956 de diferencia por persona quedan a reclamarle al
--        estudio. Mientras tanto, JP transfiere lo que MEMOSOFT calculó
--        (los netos del PDF) para no demorar el pago.
--  Importante: cuando el estudio rehaga los recibos, borrar este override
--              (DELETE de las 2 filas) y el sistema volverá al cálculo
--              automático que es lo correcto legalmente.
-- ═══════════════════════════════════════════════════════════════════════

-- Benítez Romina Solange → $1.145.061 (neto del PDF MEMOSOFT mayo 2026)
INSERT INTO public.rrhh_pagos_blanco (empleado_id, periodo, neto_cct, cargado_por, notas)
SELECT id, '2026-05-01', 1145061, 'admin',
       'Override por 2 días enf familiar (MEMOSOFT descontó pero art 36 era con goce — a revisar contra estudio)'
  FROM public.rrhh_empleados
 WHERE apellido ILIKE '%BENITEZ%' AND nombre ILIKE '%ROMINA%'
 LIMIT 1
ON CONFLICT (empleado_id, periodo)
DO UPDATE SET neto_cct = EXCLUDED.neto_cct,
              notas = EXCLUDED.notas,
              cargado_at = NOW();

-- Moreira Gabriela Liliana → $989.798
INSERT INTO public.rrhh_pagos_blanco (empleado_id, periodo, neto_cct, cargado_por, notas)
SELECT id, '2026-05-01', 989798, 'admin',
       'Override por 2 días enf familiar (MEMOSOFT descontó pero art 36 era con goce — a revisar contra estudio)'
  FROM public.rrhh_empleados
 WHERE apellido ILIKE '%MOREIRA%' AND nombre ILIKE '%GABRIELA%'
 LIMIT 1
ON CONFLICT (empleado_id, periodo)
DO UPDATE SET neto_cct = EXCLUDED.neto_cct,
              notas = EXCLUDED.notas,
              cargado_at = NOW();

-- Verificación: ver qué quedó cargado
SELECT
  e.nombre_completo,
  p.neto_cct,
  p.notas,
  p.cargado_at
FROM public.rrhh_pagos_blanco p
JOIN public.rrhh_empleados e ON e.id = p.empleado_id
WHERE p.periodo = '2026-05-01'
  AND e.apellido IN ('BENITEZ', 'MOREIRA');
