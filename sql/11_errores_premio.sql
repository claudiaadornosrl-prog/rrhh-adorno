-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Configuración premio por cumplimiento de fichadas
--
--  Regla:
--   - Oficina: hasta 3 errores permitidos; al 4to pierde el premio
--   - Locales (Unicenter, Alcorta): hasta 4 errores; al 5to pierde
--
--  Un "error" = día con anomalía de fichada:
--   - Olvidó fichar entrada (entrada vacía + turno planificado)
--   - Olvidó fichar salida (salida vacía + turno planificado)
--   - Entrada fuera de horario (más de 60 min después del turno)
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE rrhh_config_tolerancias
    ADD COLUMN IF NOT EXISTS max_errores_premio int DEFAULT 4;

UPDATE rrhh_config_tolerancias SET max_errores_premio = 3 WHERE local = 'oficina';
UPDATE rrhh_config_tolerancias SET max_errores_premio = 4 WHERE local IN ('unicenter','alcorta');

-- Verificación
-- SELECT local, max_errores_premio FROM rrhh_config_tolerancias;
