-- ═══════════════════════════════════════════════════════════════════════
--  MÓDULO RRHH — Row Level Security
--  Ejecutar DESPUÉS de 01_schema.sql
--
--  Lógica:
--   - admin: ve y modifica todo
--   - gerente: ve empleados de su local + asistencias / aprueba vacaciones de su local
--   - empleado: ve solo SU propio registro (mi_legajo, mis_sueldos, mis_asistencias…)
--   - service_role / anon (CRM): NO acceso a tablas rrhh_* (separación de módulos)
--
--  Auth: Supabase Auth — auth.uid() devuelve el UUID del usuario logueado
--  Tabla puente: rrhh_usuarios (auth_user_id → empleado_id + rol)
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
-- Helpers (funciones SECURITY DEFINER que leen rrhh_usuarios)
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rrhh_current_user()
RETURNS rrhh_usuarios
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT * FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND activo = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION rrhh_is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (SELECT 1 FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND rol = 'admin' AND activo = true);
$$;

CREATE OR REPLACE FUNCTION rrhh_is_gerente()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (SELECT 1 FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND rol = 'gerente' AND activo = true);
$$;

CREATE OR REPLACE FUNCTION rrhh_gerente_local()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT local_gerencia FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND rol = 'gerente' AND activo = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION rrhh_mi_empleado_id()
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT empleado_id FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND activo = true LIMIT 1;
$$;

-- ───────────────────────────────────────────────────────────────────────
-- Aplicar RLS a todas las tablas
-- ───────────────────────────────────────────────────────────────────────
ALTER TABLE rrhh_categorias_cct           ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_empleados                ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_usuarios                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_sueldos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_asistencias              ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_asistencias_detalle      ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_vacaciones               ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_vacaciones_movimientos   ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_licencias                ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_certificados_medicos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_apercibimientos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_documentos               ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_premios                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_log                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_feriados                 ENABLE ROW LEVEL SECURITY;

-- ───────────────────────────────────────────────────────────────────────
-- 1. CATEGORIAS CCT — todos pueden leer, solo admin escribe
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS cct_read  ON rrhh_categorias_cct;
DROP POLICY IF EXISTS cct_write ON rrhh_categorias_cct;
CREATE POLICY cct_read  ON rrhh_categorias_cct FOR SELECT USING (true);
CREATE POLICY cct_write ON rrhh_categorias_cct FOR ALL    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- ───────────────────────────────────────────────────────────────────────
-- 2. EMPLEADOS
--    admin: todo | gerente: su local | empleado: solo el suyo
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS emp_admin    ON rrhh_empleados;
DROP POLICY IF EXISTS emp_gerente  ON rrhh_empleados;
DROP POLICY IF EXISTS emp_self     ON rrhh_empleados;
CREATE POLICY emp_admin   ON rrhh_empleados FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY emp_gerente ON rrhh_empleados FOR SELECT
    USING (rrhh_is_gerente() AND local = rrhh_gerente_local());
CREATE POLICY emp_self    ON rrhh_empleados FOR SELECT
    USING (id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 3. USUARIOS — solo admin gestiona, cada uno ve el suyo
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS usr_admin ON rrhh_usuarios;
DROP POLICY IF EXISTS usr_self  ON rrhh_usuarios;
CREATE POLICY usr_admin ON rrhh_usuarios FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY usr_self  ON rrhh_usuarios FOR SELECT
    USING (auth_user_id = auth.uid());

-- ───────────────────────────────────────────────────────────────────────
-- 4. SUELDOS — admin todo | empleado solo los suyos
--    (gerentes NO ven sueldos del equipo por privacidad)
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS sue_admin ON rrhh_sueldos;
DROP POLICY IF EXISTS sue_self  ON rrhh_sueldos;
CREATE POLICY sue_admin ON rrhh_sueldos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY sue_self  ON rrhh_sueldos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 5-6. ASISTENCIAS (resumen + detalle)
--    admin: todo | gerente: su local | empleado: las suyas
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS asi_admin    ON rrhh_asistencias;
DROP POLICY IF EXISTS asi_gerente  ON rrhh_asistencias;
DROP POLICY IF EXISTS asi_self     ON rrhh_asistencias;
CREATE POLICY asi_admin   ON rrhh_asistencias FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY asi_gerente ON rrhh_asistencias FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY asi_self    ON rrhh_asistencias FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

DROP POLICY IF EXISTS asid_admin    ON rrhh_asistencias_detalle;
DROP POLICY IF EXISTS asid_gerente  ON rrhh_asistencias_detalle;
DROP POLICY IF EXISTS asid_self     ON rrhh_asistencias_detalle;
CREATE POLICY asid_admin   ON rrhh_asistencias_detalle FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY asid_gerente ON rrhh_asistencias_detalle FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY asid_self    ON rrhh_asistencias_detalle FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 7-8. VACACIONES (saldo + movimientos)
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS vac_admin    ON rrhh_vacaciones;
DROP POLICY IF EXISTS vac_gerente  ON rrhh_vacaciones;
DROP POLICY IF EXISTS vac_self     ON rrhh_vacaciones;
CREATE POLICY vac_admin   ON rrhh_vacaciones FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY vac_gerente ON rrhh_vacaciones FOR SELECT
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY vac_self    ON rrhh_vacaciones FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

DROP POLICY IF EXISTS vacmov_admin   ON rrhh_vacaciones_movimientos;
DROP POLICY IF EXISTS vacmov_gerente ON rrhh_vacaciones_movimientos;
DROP POLICY IF EXISTS vacmov_self    ON rrhh_vacaciones_movimientos;
CREATE POLICY vacmov_admin   ON rrhh_vacaciones_movimientos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
-- gerente: ve y aprueba/rechaza pedidos de su local
CREATE POLICY vacmov_gerente ON rrhh_vacaciones_movimientos FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
-- empleado: ve los suyos + puede solicitar (INSERT en estado 'solicitada')
CREATE POLICY vacmov_self ON rrhh_vacaciones_movimientos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());
DROP POLICY IF EXISTS vacmov_self_insert ON rrhh_vacaciones_movimientos;
CREATE POLICY vacmov_self_insert ON rrhh_vacaciones_movimientos FOR INSERT
    WITH CHECK (empleado_id = rrhh_mi_empleado_id() AND estado = 'solicitada');

-- ───────────────────────────────────────────────────────────────────────
-- 9. LICENCIAS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS lic_admin    ON rrhh_licencias;
DROP POLICY IF EXISTS lic_gerente  ON rrhh_licencias;
DROP POLICY IF EXISTS lic_self     ON rrhh_licencias;
CREATE POLICY lic_admin   ON rrhh_licencias FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY lic_gerente ON rrhh_licencias FOR SELECT
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY lic_self    ON rrhh_licencias FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 10. CERTIFICADOS MÉDICOS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS cert_admin    ON rrhh_certificados_medicos;
DROP POLICY IF EXISTS cert_gerente  ON rrhh_certificados_medicos;
DROP POLICY IF EXISTS cert_self     ON rrhh_certificados_medicos;
DROP POLICY IF EXISTS cert_self_ins ON rrhh_certificados_medicos;
CREATE POLICY cert_admin   ON rrhh_certificados_medicos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY cert_gerente ON rrhh_certificados_medicos FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY cert_self    ON rrhh_certificados_medicos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());
-- el empleado puede subir su certificado (validado=false hasta que admin lo valide)
CREATE POLICY cert_self_ins ON rrhh_certificados_medicos FOR INSERT
    WITH CHECK (empleado_id = rrhh_mi_empleado_id() AND validado = false);

-- ───────────────────────────────────────────────────────────────────────
-- 11. APERCIBIMIENTOS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS aper_admin   ON rrhh_apercibimientos;
DROP POLICY IF EXISTS aper_gerente ON rrhh_apercibimientos;
DROP POLICY IF EXISTS aper_self    ON rrhh_apercibimientos;
CREATE POLICY aper_admin   ON rrhh_apercibimientos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY aper_gerente ON rrhh_apercibimientos FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY aper_self    ON rrhh_apercibimientos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 12. DOCUMENTOS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS doc_admin ON rrhh_documentos;
DROP POLICY IF EXISTS doc_self  ON rrhh_documentos;
CREATE POLICY doc_admin ON rrhh_documentos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY doc_self  ON rrhh_documentos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 13. PREMIOS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS prem_admin   ON rrhh_premios;
DROP POLICY IF EXISTS prem_gerente ON rrhh_premios;
DROP POLICY IF EXISTS prem_self    ON rrhh_premios;
CREATE POLICY prem_admin   ON rrhh_premios FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY prem_gerente ON rrhh_premios FOR SELECT
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY prem_self    ON rrhh_premios FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 14. AUDIT LOG — solo admin lee, todos pueden insertar (vía función)
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS log_admin  ON rrhh_log;
DROP POLICY IF EXISTS log_insert ON rrhh_log;
CREATE POLICY log_admin  ON rrhh_log FOR SELECT USING (rrhh_is_admin());
CREATE POLICY log_insert ON rrhh_log FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ───────────────────────────────────────────────────────────────────────
-- 15. FERIADOS — todos leen, solo admin escribe
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS fer_read  ON rrhh_feriados;
DROP POLICY IF EXISTS fer_write ON rrhh_feriados;
CREATE POLICY fer_read  ON rrhh_feriados FOR SELECT USING (true);
CREATE POLICY fer_write ON rrhh_feriados FOR ALL    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- ═══════════════════════════════════════════════════════════════════════
-- FIN RLS. Siguiente: 03_storage.sql
-- ═══════════════════════════════════════════════════════════════════════
