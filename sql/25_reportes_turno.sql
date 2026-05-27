-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Reportes de turno mal cargado (vendedora → encargada)
--
--  La vendedora, desde "Mi calendario", puede reportar que un turno (pasado
--  o futuro) está mal cargado. La encargada de su local lo ve en su panel y
--  puede ACEPTAR (cambia el turno) o RECHAZAR (con motivo). La vendedora ve
--  el estado de su reporte.
--
--  NO es anónimo: la encargada necesita saber quién reporta para corregir.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rrhh_reportes_turno (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    local           text NOT NULL,           -- para RLS del gerente
    fecha           date NOT NULL,           -- el día reportado
    turno_actual    text,                    -- cómo está cargado hoy (ej "09:45 → 16:00" o "sin turno")
    turno_propuesto text,                    -- lo que la vendedora dice que debería ser (opcional)
    comentario      text,                    -- texto libre
    estado          text NOT NULL DEFAULT 'pendiente'
                    CHECK (estado IN ('pendiente','aceptado','rechazado')),
    respuesta       text,                    -- nota/motivo de la encargada al resolver
    creado_at       timestamptz DEFAULT now(),
    resuelto_at     timestamptz,
    resuelto_por    text
);

CREATE INDEX IF NOT EXISTS idx_reptur_pendientes
    ON rrhh_reportes_turno(local, creado_at DESC)
    WHERE estado = 'pendiente';
CREATE INDEX IF NOT EXISTS idx_reptur_emp
    ON rrhh_reportes_turno(empleado_id, creado_at DESC);

ALTER TABLE rrhh_reportes_turno ENABLE ROW LEVEL SECURITY;

-- Vendedora: crea reportes propios
DROP POLICY IF EXISTS reptur_self_insert ON rrhh_reportes_turno;
CREATE POLICY reptur_self_insert ON rrhh_reportes_turno FOR INSERT TO authenticated
    WITH CHECK (empleado_id = rrhh_mi_empleado_id());

-- Lectura: la vendedora ve los suyos; el gerente los de su local; el admin todos
DROP POLICY IF EXISTS reptur_select ON rrhh_reportes_turno;
CREATE POLICY reptur_select ON rrhh_reportes_turno FOR SELECT TO authenticated
    USING (
        empleado_id = rrhh_mi_empleado_id()
        OR rrhh_is_admin()
        OR (rrhh_is_gerente() AND local = rrhh_gerente_local())
    );

-- Resolver (aceptar/rechazar): solo gerente de su local o admin
DROP POLICY IF EXISTS reptur_manage_update ON rrhh_reportes_turno;
CREATE POLICY reptur_manage_update ON rrhh_reportes_turno FOR UPDATE TO authenticated
    USING (rrhh_is_admin() OR (rrhh_is_gerente() AND local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_admin() OR (rrhh_is_gerente() AND local = rrhh_gerente_local()));
