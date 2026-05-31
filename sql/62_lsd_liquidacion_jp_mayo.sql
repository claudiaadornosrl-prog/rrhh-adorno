-- ═══════════════════════════════════════════════════════════════════════
--  62_lsd_liquidacion_jp_mayo.sql
--  Genera la liquidación de JP Simonelli (empleado en relación de
--  dependencia, FUERA DE CONVENIO, OSDE adherente) para mayo 2026
--  para que figure en el LSD AFIP.
--
--  Replica el formato del recibo de abril 2026 del estudio:
--   - 0001 Sueldo básico  (rem)
--   - 0022 Antigüedad 10% (rem)
--   - 0491 Suma fija NR
--   - 0492 Ant NR 10%        (se exporta como 0494 en el TXT — no OSECAC)
--   - 0493 Pres NR 8.33%     (se exporta como 0495 en el TXT — no OSECAC)
--   - 0497 Recompos NR
--   - 1001/1002/1031 descuentos
--
--  Neto objetivo: $2.695.114 (de SQL 44 override del estudio).
--  Sin presentismo CCT, sin SEC, sin FAECYS (fuera de convenio).
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Limpiar liquidación previa de JP en mayo si existe ──────────────
DELETE FROM rrhh_liquidacion_concepto
 WHERE liquidacion_id IN (
   SELECT l.id FROM rrhh_liquidacion l
   JOIN rrhh_empleados e ON e.id = l.empleado_id
   WHERE e.cuil = '20-36754687-6' AND l.periodo = '2026-05-01'
 );
DELETE FROM rrhh_liquidacion
 WHERE periodo = '2026-05-01'
   AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE cuil = '20-36754687-6');

-- ─── Insertar liquidación maestro ────────────────────────────────────
WITH emp AS (
  SELECT id FROM rrhh_empleados WHERE cuil = '20-36754687-6'
),
nueva_liq AS (
  INSERT INTO rrhh_liquidacion (
    empleado_id, periodo, local, estado, dias_trabajados,
    recibo_basico, recibo_antiguedad, recibo_presentismo,
    recibo_sumafija_nr, recibo_antig_nr, recibo_pres_nr, recibo_recompos_nr,
    recibo_otros_rem,
    recibo_jubilacion, recibo_ley19032, recibo_obra_social,
    recibo_sec, recibo_faecys,
    recibo_total_rem, recibo_total_nr, recibo_bruto,
    recibo_descuentos, recibo_neto,
    observaciones
  )
  SELECT
    emp.id, '2026-05-01', 'oficina', 'borrador', 30,
    2795310.00, 279531.00, 0,
    100000.00, 12000.00, 10995.60, 20000.00,
    0,
    338232.51, 92245.23, 92245.23,
    0, 0,
    3074841.00, 142995.60, 3217836.60,
    522722.97, 2695113.63,
    'LSD AFIP mayo 2026 — JP fuera de convenio + OSDE adherente. Generada por SQL 62.'
  FROM emp
  RETURNING id
)
-- ─── Insertar los 9 conceptos del recibo ─────────────────────────────
INSERT INTO rrhh_liquidacion_concepto (
  liquidacion_id, codigo, nombre, base, porcentaje, importe, remunerativo, es_descuento, orden
)
SELECT id, codigo, nombre, base, porcentaje, importe, remunerativo, es_descuento, orden
FROM nueva_liq, (VALUES
  ('0001', 'Sueldo Básico',          2795310.00, 100.0000, 2795310.00, true,  false,  10),
  ('0022', 'Adicional Antigüedad',   2795310.00,  10.0000,  279531.00, true,  false,  20),
  ('0491', 'Suma fija no rem',             NULL,     NULL,  100000.00, false, false,  50),
  ('0492', 'Antigüedad no rem',       120000.00,  10.0000,   12000.00, false, false,  60),
  ('0493', 'Presentismo no rem',      132000.00,   8.3300,   10995.60, false, false,  70),
  ('0497', 'Recompos Ac. 2026',            NULL,     NULL,   20000.00, false, false,  80),
  ('1001', 'Jubilación',             3074841.00,  11.0000,  338232.51, true,  true,  100),
  ('1002', 'Ley 19.032 (PAMI)',      3074841.00,   3.0000,   92245.23, true,  true,  110),
  ('1031', 'Obra Social',            3074841.00,   3.0000,   92245.23, true,  true,  120)
) AS conc(codigo, nombre, base, porcentaje, importe, remunerativo, es_descuento, orden);

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── Verificación ────────────────────────────────────────────────────
SELECT
  e.apellido, e.cuil, e.local, e.os_codigo_afip,
  l.id AS liq_id, l.recibo_basico, l.recibo_total_rem, l.recibo_total_nr,
  l.recibo_bruto, l.recibo_descuentos, l.recibo_neto,
  (SELECT COUNT(*) FROM rrhh_liquidacion_concepto WHERE liquidacion_id = l.id) AS n_conceptos
FROM rrhh_empleados e
JOIN rrhh_liquidacion l ON l.empleado_id = e.id
WHERE l.periodo = '2026-05-01' AND e.cuil = '20-36754687-6';

-- Detalle de conceptos
SELECT codigo, nombre, importe, remunerativo, es_descuento, orden
FROM rrhh_liquidacion_concepto
WHERE liquidacion_id IN (
  SELECT l.id FROM rrhh_liquidacion l
  JOIN rrhh_empleados e ON e.id = l.empleado_id
  WHERE e.cuil = '20-36754687-6' AND l.periodo = '2026-05-01'
)
ORDER BY orden;
