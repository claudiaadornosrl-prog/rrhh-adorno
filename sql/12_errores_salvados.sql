-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Errores salvados + umbral mensual de tardanzas
--
--  Feature 1: "Salvar" errores de fichada
--    La encargada puede marcar un día como salvado (ej. dispositivo
--    Anviz roto). Deja de contar contra el premio. Queda registrado quién
--    lo salvó, cuándo y por qué motivo (auditable por admin).
--
--  Feature 2: Tolerancia mensual de tardanzas
--    Si el total de minutos tarde del mes < 60, NO descontar del banco.
--    Si supera 60 min, descontar (total - 60) del banco como un único
--    movimiento mensual.
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Columnas para salvar errores
ALTER TABLE rrhh_asistencias_detalle
    ADD COLUMN IF NOT EXISTS error_salvado    boolean    DEFAULT false,
    ADD COLUMN IF NOT EXISTS salvado_por      text,
    ADD COLUMN IF NOT EXISTS salvado_motivo   text,
    ADD COLUMN IF NOT EXISTS salvado_at       timestamptz;

CREATE INDEX IF NOT EXISTS idx_asid_salvados
    ON rrhh_asistencias_detalle(error_salvado, fecha DESC)
    WHERE error_salvado = true;

-- 2) Umbral mensual de tardanzas en config
ALTER TABLE rrhh_config_tolerancias
    ADD COLUMN IF NOT EXISTS umbral_mensual_tardanzas int DEFAULT 60;

UPDATE rrhh_config_tolerancias SET umbral_mensual_tardanzas = 60;

-- ═══════════════════════════════════════════════════════════════════════
-- Verificación
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT local, max_errores_premio, umbral_mensual_tardanzas FROM rrhh_config_tolerancias;
