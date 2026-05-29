-- ═══════════════════════════════════════════════════════════════════════
--  44_override_netos_adorno_simonelli.sql
--  Override de netos para Claudia Adorno y JP Simonelli en mayo 2026.
--  Caso: ambos cobran como gerentes en relación de dependencia. Para que
--        no tributen Ganancias, se ajusta el sueldo bruto al límite del
--        mínimo no imponible AFIP (deducciones por cónyuge/hijos incluidas).
--  Los valores acá usados los pasó el estudio contable y están sujetos a
--  revisión (¿son realmente el tope correcto para mayo 2026?).
-- ═══════════════════════════════════════════════════════════════════════

-- Adorno, Claudia Viviana → $3.662.360 (estudio)
INSERT INTO public.rrhh_pagos_blanco (empleado_id, periodo, neto_cct, cargado_por, notas)
SELECT id, '2026-05-01', 3662360, 'admin',
       'Tope ganancias mayo 2026 — pasado por estudio contable, a chequear vs tabla AFIP cuando esté armada'
  FROM public.rrhh_empleados
 WHERE apellido ILIKE '%ADORNO%' AND nombre ILIKE '%CLAUDIA%'
 LIMIT 1
ON CONFLICT (empleado_id, periodo)
DO UPDATE SET neto_cct = EXCLUDED.neto_cct,
              notas = EXCLUDED.notas,
              cargado_at = NOW();

-- Simonelli, Juan Pablo → $2.695.114 (estudio)
INSERT INTO public.rrhh_pagos_blanco (empleado_id, periodo, neto_cct, cargado_por, notas)
SELECT id, '2026-05-01', 2695114, 'admin',
       'Tope ganancias mayo 2026 — pasado por estudio contable, a chequear vs tabla AFIP cuando esté armada'
  FROM public.rrhh_empleados
 WHERE apellido ILIKE '%SIMONELLI%' AND nombre ILIKE '%JUAN%'
 LIMIT 1
ON CONFLICT (empleado_id, periodo)
DO UPDATE SET neto_cct = EXCLUDED.neto_cct,
              notas = EXCLUDED.notas,
              cargado_at = NOW();

-- Verificación
SELECT
  e.nombre_completo,
  p.neto_cct,
  p.notas,
  p.cargado_at
FROM public.rrhh_pagos_blanco p
JOIN public.rrhh_empleados e ON e.id = p.empleado_id
WHERE p.periodo = '2026-05-01'
  AND (e.apellido ILIKE '%ADORNO%' OR e.apellido ILIKE '%SIMONELLI%');
