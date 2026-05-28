-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Esquema "doble blanco" (Contreras + Escasany)
--
--  Confirmación JP: Contreras y Escasany reciben DOS recibos blancos por mes:
--    1. Recibo CCT puro (escala oficial: básico, antig, presentismo, no rem, descuentos).
--    2. Recibo ajuste: la diferencia para llegar al Total esperado
--       (Fijo + Comisión + Premio + Viáticos + Extras).
--  No cobran nada en negro. El Excel sumaba ambos en la columna 'Banco'.
--
--  Y caso particular Escasany (Franquera): MEMOSOFT prorratea el básico a
--  16/30 pero las sumas no rem a 50% (criterio distinto del estudio).
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Modo de liquidación por empleada
ALTER TABLE rrhh_sueldo_empleada_config
    ADD COLUMN IF NOT EXISTS modo_liquidacion text NOT NULL DEFAULT 'cct_negro'
        CHECK (modo_liquidacion IN ('cct_negro','doble_blanco'));
COMMENT ON COLUMN rrhh_sueldo_empleada_config.modo_liquidacion IS
'cct_negro: la diferencia entre Total y recibo se paga en negro (efectivo). '
'doble_blanco: la diferencia se paga en un segundo recibo blanco (ajuste); no hay negro.';

-- 2) Fracción para prorratear las sumas no rem (override; null = usa dias_trabajados/30)
ALTER TABLE rrhh_sueldo_empleada_config
    ADD COLUMN IF NOT EXISTS fraccion_no_rem numeric(5,4);
COMMENT ON COLUMN rrhh_sueldo_empleada_config.fraccion_no_rem IS
'Override del prorrateo de sumas no rem. Para casos como Escasany donde MEMOSOFT '
'prorratea básico a unidades/30 pero no rem a otra fracción (ej 0.5 = 50%). '
'null = usar dias_trabajados/30 igual que el básico.';

-- 3) Monto del segundo recibo blanco en la liquidación
ALTER TABLE rrhh_liquidacion
    ADD COLUMN IF NOT EXISTS ajuste_blanco numeric(12,2) NOT NULL DEFAULT 0;
COMMENT ON COLUMN rrhh_liquidacion.ajuste_blanco IS
'Para empleadas modo_liquidacion=doble_blanco: monto del segundo recibo en blanco '
'que cubre la diferencia entre Total y el recibo CCT puro. Cero si la empleada es cct_negro.';

-- 4) Aplicar el esquema a Contreras y Escasany (vigente desde 2026-04-01)
UPDATE rrhh_sueldo_empleada_config c
   SET modo_liquidacion = 'doble_blanco'
  FROM rrhh_empleados e
 WHERE c.empleado_id = e.id
   AND upper(e.apellido) IN ('CONTRERAS','ESCASANY')
   AND c.vigente_desde = '2026-04-01';

-- Escasany: fracción no rem a 50% (MEMOSOFT lo liquida así)
UPDATE rrhh_sueldo_empleada_config c
   SET fraccion_no_rem = 0.5000
  FROM rrhh_empleados e
 WHERE c.empleado_id = e.id
   AND upper(e.apellido) = 'ESCASANY'
   AND c.vigente_desde = '2026-04-01';
