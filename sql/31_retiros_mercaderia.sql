-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Retiros de mercadería del personal
--
--  La encargada carga durante el mes cada retiro de mercadería que se
--  lleva una empleada (a precio interno / costo / lo que sea).
--  Al generar la liquidación del mes, el sistema suma todos los retiros
--  del mes de esa empleada en el campo `mercaderia` de la liquidación.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rrhh_retiro_mercaderia (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    local           text   NOT NULL,                 -- snapshot del local al momento del retiro
    fecha           date   NOT NULL,
    monto           numeric(12,2) NOT NULL,
    descripcion     text,                            -- "SET MANTELES", "VELA + SALERO", etc.
    cargado_por     text,                            -- email/usuario que lo registró
    creado_at       timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_retiros_emp_fecha ON rrhh_retiro_mercaderia(empleado_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_retiros_local_periodo
    ON rrhh_retiro_mercaderia(local, fecha DESC);

ALTER TABLE rrhh_retiro_mercaderia ENABLE ROW LEVEL SECURITY;

-- Admin: todo.
DROP POLICY IF EXISTS retmerc_admin ON rrhh_retiro_mercaderia;
CREATE POLICY retmerc_admin ON rrhh_retiro_mercaderia FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- Encargada: ve y carga los de su local.
DROP POLICY IF EXISTS retmerc_gerente ON rrhh_retiro_mercaderia;
CREATE POLICY retmerc_gerente ON rrhh_retiro_mercaderia FOR ALL TO authenticated
    USING (rrhh_is_gerente() AND local = rrhh_gerente_local())
    WITH CHECK (rrhh_is_gerente() AND local = rrhh_gerente_local());

-- Empleada: ve los suyos (transparencia: cada vendedora puede ver qué se le cargó).
DROP POLICY IF EXISTS retmerc_self ON rrhh_retiro_mercaderia;
CREATE POLICY retmerc_self ON rrhh_retiro_mercaderia FOR SELECT TO authenticated
    USING (empleado_id = rrhh_mi_empleado_id());
