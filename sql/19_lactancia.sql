-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Período de lactancia
--
--  Cuando una empleada está en lactancia, la ley le permite:
--    - Reducir su jornada (típicamente 1 hora dividida en 2 pausas)
--    - El sistema confía en los turnos cargados en CrossChex con horario
--      reducido (no aplica reducción automática). Solo marca un badge
--      visual y avisa cuando se acerca el fin del período.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE rrhh_empleados
    ADD COLUMN IF NOT EXISTS lactancia_desde date,
    ADD COLUMN IF NOT EXISTS lactancia_hasta date,
    -- Minutos que se reducen del turno por lactancia (al fin en jornada normal,
    -- al inicio en jornada larga ≥ 8hs)
    ADD COLUMN IF NOT EXISTS lactancia_reduccion_diaria_min  int DEFAULT 0,
    ADD COLUMN IF NOT EXISTS lactancia_reduccion_finde_min   int DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_emp_lactancia
    ON rrhh_empleados(lactancia_hasta)
    WHERE lactancia_hasta IS NOT NULL;
