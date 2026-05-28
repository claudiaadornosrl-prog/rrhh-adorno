-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Plus por feriado trabajado (shoppings)
--
--  Los locales en shoppings (Alcorta, Unicenter) abren los feriados nacionales.
--  Por cada feriado trabajado se paga un plus fijo a cada vendedora del local.
--  Oficina NO trabaja feriados, así que no le aplica.
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Configurar el monto por feriado en cada local
ALTER TABLE rrhh_sueldo_local_config
    ADD COLUMN IF NOT EXISTS feriado_por_dia numeric(12,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN rrhh_sueldo_local_config.feriado_por_dia IS
'Monto fijo que se paga a cada empleada del local por cada día feriado trabajado. '
'En shoppings (Alcorta/Unicenter) aplica $22.000. En Oficina queda en 0 (no trabaja feriados).';

UPDATE rrhh_sueldo_local_config SET feriado_por_dia = 22000.00 WHERE local IN ('alcorta','unicenter');
UPDATE rrhh_sueldo_local_config SET feriado_por_dia = 0       WHERE local = 'oficina';

-- 2) Snapshot del monto en cada liquidación (para auditoría)
ALTER TABLE rrhh_liquidacion
    ADD COLUMN IF NOT EXISTS feriado_dias  int           NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS feriado_monto numeric(12,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN rrhh_liquidacion.feriado_dias IS
'Cantidad de feriados nacionales del mes que el local trabajó (snapshot).';
COMMENT ON COLUMN rrhh_liquidacion.feriado_monto IS
'Plus total por feriado trabajado: feriado_dias × feriado_por_dia (del local).';
