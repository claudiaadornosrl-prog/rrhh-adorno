-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Foto self-service + fix de datos self-service
--
--  Decisión JP: cada empleada sube su propia foto desde "Mi legajo".
--
--  Problema detectado: la política emp_self de rrhh_empleados es solo SELECT,
--  así que el "Guardar cambios" del legajo (contacto/emergencia) no persistía.
--  Lo resolvemos con funciones SECURITY DEFINER que actualizan SOLO los campos
--  self-service de la propia empleada (sin abrir un UPDATE amplio sobre la fila).
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Bucket de fotos (público para poder mostrarlas como avatar) ───
INSERT INTO storage.buckets (id, name, public)
VALUES ('rrhh-fotos', 'rrhh-fotos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Lectura pública (los <img> del avatar funcionan sin firmar URL)
DROP POLICY IF EXISTS fotos_public_read ON storage.objects;
CREATE POLICY fotos_public_read ON storage.objects FOR SELECT
    USING (bucket_id = 'rrhh-fotos');

-- Cada empleada escribe SOLO en su carpeta {empleado_id}/...
DROP POLICY IF EXISTS fotos_self_insert ON storage.objects;
CREATE POLICY fotos_self_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'rrhh-fotos'
        AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text
    );

DROP POLICY IF EXISTS fotos_self_update ON storage.objects;
CREATE POLICY fotos_self_update ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'rrhh-fotos'
        AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text
    );

-- El admin puede gestionar todas (por si necesita corregir)
DROP POLICY IF EXISTS fotos_admin_all ON storage.objects;
CREATE POLICY fotos_admin_all ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-fotos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-fotos' AND rrhh_is_admin());

-- ─── 2. Actualizar mi foto (solo la propia empleada) ───
CREATE OR REPLACE FUNCTION rrhh_actualizar_mi_foto(p_url text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $func$
BEGIN
    UPDATE rrhh_empleados
       SET foto_url = p_url
     WHERE id = rrhh_mi_empleado_id();
END;
$func$;

-- ─── 3. Actualizar mis datos de contacto/emergencia (fix del Guardar) ───
CREATE OR REPLACE FUNCTION rrhh_actualizar_mis_datos(
    p_email               text,
    p_telefono            text,
    p_direccion           text,
    p_emergencia_nombre   text,
    p_emergencia_telefono text,
    p_emergencia_vinculo  text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $func$
BEGIN
    UPDATE rrhh_empleados
       SET email               = p_email,
           telefono            = p_telefono,
           direccion           = p_direccion,
           emergencia_nombre   = p_emergencia_nombre,
           emergencia_telefono = p_emergencia_telefono,
           emergencia_vinculo  = p_emergencia_vinculo
     WHERE id = rrhh_mi_empleado_id();
END;
$func$;

GRANT EXECUTE ON FUNCTION rrhh_actualizar_mi_foto(text)            TO authenticated;
GRANT EXECUTE ON FUNCTION rrhh_actualizar_mis_datos(text,text,text,text,text,text) TO authenticated;
