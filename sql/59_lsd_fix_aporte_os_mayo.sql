-- ═══════════════════════════════════════════════════════════════════════
--  59_lsd_fix_aporte_os_mayo.sql
--
--  CONTEXTO:
--   El salaryEngine tenía un bug histórico:
--     - Para OSECAC: aporte OS = 3% × bruto (rem + NR completo)
--     - Para no-OSECAC: aporte OS = 3% × rem
--   AFIP requiere: aporte OS = 3% × baseLRT (= rem + 0492 ant_nr + 0493 pres_nr)
--   para TODAS las empleadas, independiente de la OS.
--
--  Esto da error de aporte OS mismatch en validación LSD ARCA.
--
--  Este script:
--   1) Para cada liquidación de mayo 2026, calcula el aporte OS correcto.
--   2) Actualiza el concepto 1031 (OS) con el importe corregido.
--   3) Compensa la diferencia ajustando `ajuste_blanco` en rrhh_liquidacion
--      para mantener intactos el neto pagado y el total_negro.
--
--  El TXT LSD pasa a coincidir con lo que ARCA calcula. Los netos pagados
--  a las empleadas NO cambian (ya están en línea con el cálculo del estudio).
-- ═══════════════════════════════════════════════════════════════════════

-- Paso 1: PREVIEW — mostrar qué va a cambiar (no ejecuta nada todavía)
WITH
liq_bases AS (
  SELECT
    l.id          AS liq_id,
    e.cuil,
    e.apellido,
    e.obra_social_codigo,
    l.recibo_basico,
    l.recibo_antiguedad,
    l.recibo_presentismo,
    l.recibo_antig_nr,
    l.recibo_pres_nr,
    l.ajuste_blanco,
    -- Cálculos
    COALESCE(l.recibo_basico,0) + COALESCE(l.recibo_antiguedad,0) + COALESCE(l.recibo_presentismo,0) AS base_rem,
    COALESCE(l.recibo_antig_nr,0) + COALESCE(l.recibo_pres_nr,0) AS lrt_extra
  FROM rrhh_liquidacion l
  JOIN rrhh_empleados e ON e.id = l.empleado_id
  WHERE l.periodo = '2026-05-01'
),
preview AS (
  SELECT
    b.liq_id,
    b.cuil,
    b.apellido,
    b.obra_social_codigo,
    b.base_rem,
    b.lrt_extra,
    (b.base_rem + b.lrt_extra)         AS base_os_correcta,
    (b.base_rem + b.lrt_extra) * 0.03  AS os_correcto,
    c.importe                          AS os_actual,
    ((b.base_rem + b.lrt_extra) * 0.03 - c.importe) AS diferencia
  FROM liq_bases b
  JOIN rrhh_liquidacion_concepto c
    ON c.liquidacion_id = b.liq_id
   AND c.codigo = '1031'
   AND c.es_descuento = true
)
SELECT
  apellido,
  obra_social_codigo,
  ROUND(base_rem, 2)         AS base_rem,
  ROUND(lrt_extra, 2)        AS extra_nr,
  ROUND(os_actual, 2)        AS os_actual,
  ROUND(os_correcto, 2)      AS os_correcto,
  ROUND(diferencia, 2)       AS diferencia,
  CASE
    WHEN diferencia > 0 THEN 'COBRARLE MÁS OS (le faltó descontar)'
    WHEN diferencia < 0 THEN 'COBRARLE MENOS OS (se le descontó de más)'
    ELSE 'OK sin cambio'
  END AS interpretacion
FROM preview
ORDER BY apellido;

-- ─────────────────────────────────────────────────────────────
-- Paso 2: APLICAR — descomentar para ejecutar después de revisar preview
-- ─────────────────────────────────────────────────────────────

/*
BEGIN;

WITH liq_bases AS (
  SELECT
    l.id AS liq_id,
    COALESCE(l.recibo_basico,0) + COALESCE(l.recibo_antiguedad,0) + COALESCE(l.recibo_presentismo,0) +
    COALESCE(l.recibo_antig_nr,0) + COALESCE(l.recibo_pres_nr,0) AS base_os_correcta
  FROM rrhh_liquidacion l
  WHERE l.periodo = '2026-05-01'
),
deltas AS (
  SELECT
    b.liq_id,
    ROUND((b.base_os_correcta * 0.03)::numeric, 2) AS os_correcto,
    c.importe AS os_actual,
    ROUND(((b.base_os_correcta * 0.03) - c.importe)::numeric, 2) AS delta_os
  FROM liq_bases b
  JOIN rrhh_liquidacion_concepto c
    ON c.liquidacion_id = b.liq_id
   AND c.codigo = '1031'
   AND c.es_descuento = true
)
-- a) Actualizar el concepto 1031 al valor correcto
UPDATE rrhh_liquidacion_concepto c
   SET importe = d.os_correcto,
       base    = (SELECT base_os_correcta FROM liq_bases WHERE liq_id = c.liquidacion_id)
  FROM deltas d
 WHERE c.liquidacion_id = d.liq_id
   AND c.codigo = '1031'
   AND c.es_descuento = true;

-- b) Compensar el `ajuste_blanco` para mantener el neto estable
-- Si OS aumenta delta, el neto baja delta → para compensar y mantener neto,
-- el ajuste_blanco sube delta. Es decir: ajuste_blanco += delta_os
UPDATE rrhh_liquidacion l
   SET ajuste_blanco = COALESCE(ajuste_blanco, 0) + d.delta_os
  FROM (
    SELECT
      b.liq_id,
      ROUND(((b.base_os_correcta * 0.03) - c.importe)::numeric, 2) AS delta_os
    FROM (
      SELECT id AS liq_id,
        COALESCE(recibo_basico,0)+COALESCE(recibo_antiguedad,0)+COALESCE(recibo_presentismo,0)+
        COALESCE(recibo_antig_nr,0)+COALESCE(recibo_pres_nr,0) AS base_os_correcta
      FROM rrhh_liquidacion WHERE periodo='2026-05-01'
    ) b
    JOIN rrhh_liquidacion_concepto c
      ON c.liquidacion_id = b.liq_id
     AND c.codigo = '1031'
     AND c.es_descuento = true
  ) d
 WHERE l.id = d.liq_id;

COMMIT;

-- Verificación post-aplicación
SELECT
  e.apellido,
  l.ajuste_blanco,
  c.importe AS os_actualizado,
  ROUND((
    COALESCE(l.recibo_basico,0)+COALESCE(l.recibo_antiguedad,0)+COALESCE(l.recibo_presentismo,0)+
    COALESCE(l.recibo_antig_nr,0)+COALESCE(l.recibo_pres_nr,0)
  )*0.03, 2) AS os_esperado,
  ROUND(c.importe - (
    COALESCE(l.recibo_basico,0)+COALESCE(l.recibo_antiguedad,0)+COALESCE(l.recibo_presentismo,0)+
    COALESCE(l.recibo_antig_nr,0)+COALESCE(l.recibo_pres_nr,0)
  )*0.03, 2) AS delta_residual
FROM rrhh_liquidacion l
JOIN rrhh_empleados e ON e.id = l.empleado_id
JOIN rrhh_liquidacion_concepto c
  ON c.liquidacion_id = l.id AND c.codigo='1031' AND c.es_descuento=true
WHERE l.periodo = '2026-05-01'
ORDER BY e.apellido;
*/
