-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Tolerancia diaria de llegada tarde: 5 minutos
--
--  Regla acordada con JP:
--    - Turno cargado en sistema: ej. 9:45 (con 15 min de margen)
--    - Horario real acordado: 10:00
--    - Tolerancia diaria: 5 min después del horario real = 10:05
--    - Si ficha 10:06 o más tarde → ES error contra el premio
--
--  Para la suma mensual:
--    - Cuentan TODOS los minutos desde el horario real (10:00)
--    - Si la suma del mes supera 60 min → descontar TOTAL del banco
-- ═══════════════════════════════════════════════════════════════════════

UPDATE rrhh_config_tolerancias SET minutos_tarde = 5;

-- ═══════════════════════════════════════════════════════════════════════
-- Verificación
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT local, buffer_entrada, minutos_tarde, minutos_temprano, max_errores_premio, umbral_mensual_tardanzas
-- FROM rrhh_config_tolerancias;
-- Esperado: minutos_tarde = 5 para los 3 locales (oficina, unicenter, alcorta)
