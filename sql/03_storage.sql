-- ═══════════════════════════════════════════════════════════════════════
--  MÓDULO RRHH — Storage buckets + políticas
--  Ejecutar DESPUÉS de 02_rls.sql
--
--  Buckets:
--   rrhh-recibos          → recibos de sueldo PDF
--   rrhh-certificados     → certificados médicos PDF/imagen
--   rrhh-apercibimientos  → apercibimientos PDF firmados
--   rrhh-documentos       → contratos, DNI, CBU, CV, etc.
--   rrhh-fotos            → fotos de empleados (jpg/png)
--   rrhh-asistencias-raw  → Excel originales de CrossChex
--
--  Convención de paths:
--   {empleado_id}/{tipo}/{nombre_archivo}
--   ej: 42/recibo/2026-04.pdf
-- ═══════════════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('rrhh-recibos',          'rrhh-recibos',          false, 10485760,  ARRAY['application/pdf']::text[]),
    ('rrhh-certificados',     'rrhh-certificados',     false, 10485760,  ARRAY['application/pdf','image/jpeg','image/png']::text[]),
    ('rrhh-apercibimientos',  'rrhh-apercibimientos',  false, 10485760,  ARRAY['application/pdf','image/jpeg','image/png']::text[]),
    ('rrhh-documentos',       'rrhh-documentos',       false, 20971520,  ARRAY['application/pdf','image/jpeg','image/png','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document']::text[]),
    ('rrhh-fotos',            'rrhh-fotos',            false,  5242880,  ARRAY['image/jpeg','image/png','image/webp']::text[]),
    ('rrhh-asistencias-raw',  'rrhh-asistencias-raw',  false, 52428800,  ARRAY['application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']::text[])
ON CONFLICT (id) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- Políticas Storage — patrón: admin todo, empleado solo su carpeta
-- (storage.objects usa storage.foldername(name) para extraer el primer segmento del path)
-- ───────────────────────────────────────────────────────────────────────

-- Helper común: el primer segmento del path es el empleado_id
-- (storage.foldername devuelve array, tomamos índice 1)

-- ===== RECIBOS =====
DROP POLICY IF EXISTS rrhh_recibos_admin  ON storage.objects;
DROP POLICY IF EXISTS rrhh_recibos_self   ON storage.objects;
CREATE POLICY rrhh_recibos_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-recibos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-recibos' AND rrhh_is_admin());
CREATE POLICY rrhh_recibos_self ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-recibos'
           AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);

-- ===== CERTIFICADOS =====
DROP POLICY IF EXISTS rrhh_cert_admin   ON storage.objects;
DROP POLICY IF EXISTS rrhh_cert_self    ON storage.objects;
DROP POLICY IF EXISTS rrhh_cert_gerente ON storage.objects;
CREATE POLICY rrhh_cert_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-certificados' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-certificados' AND rrhh_is_admin());
CREATE POLICY rrhh_cert_self ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-certificados' AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text)
    WITH CHECK (bucket_id = 'rrhh-certificados' AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);
CREATE POLICY rrhh_cert_gerente ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-certificados'
           AND rrhh_is_gerente()
           AND (storage.foldername(name))[1]::bigint IN
               (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));

-- ===== APERCIBIMIENTOS =====
DROP POLICY IF EXISTS rrhh_aper_admin   ON storage.objects;
DROP POLICY IF EXISTS rrhh_aper_gerente ON storage.objects;
DROP POLICY IF EXISTS rrhh_aper_self    ON storage.objects;
CREATE POLICY rrhh_aper_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-apercibimientos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-apercibimientos' AND rrhh_is_admin());
CREATE POLICY rrhh_aper_gerente ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-apercibimientos' AND rrhh_is_gerente()
           AND (storage.foldername(name))[1]::bigint IN
               (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (bucket_id = 'rrhh-apercibimientos' AND rrhh_is_gerente()
           AND (storage.foldername(name))[1]::bigint IN
               (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY rrhh_aper_self ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-apercibimientos'
           AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);

-- ===== DOCUMENTOS =====
DROP POLICY IF EXISTS rrhh_doc_admin ON storage.objects;
DROP POLICY IF EXISTS rrhh_doc_self  ON storage.objects;
CREATE POLICY rrhh_doc_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-documentos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-documentos' AND rrhh_is_admin());
CREATE POLICY rrhh_doc_self ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-documentos'
           AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);

-- ===== FOTOS =====
DROP POLICY IF EXISTS rrhh_foto_admin ON storage.objects;
DROP POLICY IF EXISTS rrhh_foto_self  ON storage.objects;
DROP POLICY IF EXISTS rrhh_foto_read  ON storage.objects;
CREATE POLICY rrhh_foto_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-fotos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-fotos' AND rrhh_is_admin());
CREATE POLICY rrhh_foto_self ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-fotos' AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text)
    WITH CHECK (bucket_id = 'rrhh-fotos' AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);
-- todos los logueados pueden ver las fotos (para listados, ABM, etc.)
CREATE POLICY rrhh_foto_read ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-fotos');

-- ===== ASISTENCIAS RAW =====
DROP POLICY IF EXISTS rrhh_asi_admin   ON storage.objects;
DROP POLICY IF EXISTS rrhh_asi_gerente ON storage.objects;
CREATE POLICY rrhh_asi_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-asistencias-raw' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-asistencias-raw' AND rrhh_is_admin());
CREATE POLICY rrhh_asi_gerente ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-asistencias-raw' AND rrhh_is_gerente());

-- ═══════════════════════════════════════════════════════════════════════
-- FIN Storage. Siguiente: 04_seed.sql
-- ═══════════════════════════════════════════════════════════════════════
