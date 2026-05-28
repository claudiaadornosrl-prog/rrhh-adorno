-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — RLS para rrhh_paritaria_sumas_nr
--
--  La tabla guarda las sumas no remunerativas vigentes por período. Es
--  información pública (las sumas son iguales para todas las empleadas y
--  surgen de paritarias publicadas), así que cualquier usuario autenticado
--  puede leerla. Solo el admin puede escribir.
-- ═══════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS paritaria_read   ON rrhh_paritaria_sumas_nr;
CREATE POLICY paritaria_read   ON rrhh_paritaria_sumas_nr FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS paritaria_admin  ON rrhh_paritaria_sumas_nr;
CREATE POLICY paritaria_admin  ON rrhh_paritaria_sumas_nr FOR ALL TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
