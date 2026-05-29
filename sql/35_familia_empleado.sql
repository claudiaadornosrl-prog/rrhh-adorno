-- ═══════════════════════════════════════════════════════════════════════
--  35_familia_empleado.sql
--  Agrega campos de familia al legajo: cónyuge + hijos (lista dinámica).
--
--  - conyuge_nombre: text (un solo cónyuge)
--  - hijos: jsonb (lista de { nombre, fecha_nacimiento? })
--
--  Después de correr, ejecutar:   NOTIFY pgrst, 'reload schema';
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE public.rrhh_empleados
    ADD COLUMN IF NOT EXISTS conyuge_nombre text,
    ADD COLUMN IF NOT EXISTS hijos          jsonb DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.rrhh_empleados.conyuge_nombre IS
    'Nombre del cónyuge / pareja (opcional, dato de legajo)';
COMMENT ON COLUMN public.rrhh_empleados.hijos IS
    'Lista de hijos: jsonb array de objetos { "nombre": "...", "fecha_nacimiento": "YYYY-MM-DD"? }';

-- Refrescar cache de PostgREST
NOTIFY pgrst, 'reload schema';
