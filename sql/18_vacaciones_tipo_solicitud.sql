-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Tipo de solicitud de vacaciones
--
--  Una solicitud puede ser:
--    - 'toma':   la vendedora pide tomar vacaciones (estado→aprobada→tomada)
--    - 'pago':   la vendedora pide cobrar vacaciones no tomadas
--                (al aprobar pasa a 'pagada')
--
--  Al solicitar tipo='pago', el sistema valida las reglas (≥3 semanas de
--  saldo, máx 1 semana paga por año). Si no cumple, no la deja crear la solicitud.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE rrhh_vacaciones_movimientos
    ADD COLUMN IF NOT EXISTS tipo_solicitud text DEFAULT 'toma'
        CHECK (tipo_solicitud IN ('toma','pago'));

CREATE INDEX IF NOT EXISTS idx_vacmov_tipo_pendiente
    ON rrhh_vacaciones_movimientos(tipo_solicitud, estado)
    WHERE estado = 'solicitada';
