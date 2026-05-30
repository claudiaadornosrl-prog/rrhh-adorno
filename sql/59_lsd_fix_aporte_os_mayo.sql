-- ═══════════════════════════════════════════════════════════════════════
--  59_lsd_fix_aporte_os_mayo.sql · DEPRECATED · NO EJECUTAR
--
--  Este script asumía erróneamente que el salaryEngine tenía un bug en
--  el cálculo de OS. La realidad: el salaryEngine estaba bien.
--  El problema era que mi generador LSD usa códigos NR mixtos para todas
--  las empleadas. La fix correcta vive en el generador (v47 swap por OSECAC).
--
--  No ejecutar.
-- ═══════════════════════════════════════════════════════════════════════

SELECT 'SQL 59 deprecated — no ejecutar' AS estado;
