-- ═══════════════════════════════════════════════════════════════════════
--  63_andrea_monotributista.sql
--
--  Caso Andrea Adorno (prima de Claudia): encargada de Alcorta, monotributista.
--  Factura $1.000.000 mensual por banco. Resto se le paga en efectivo (negro).
--  NO tiene recibo CCT, NO va al LSD AFIP, NO va al F.931.
--
--  Cambios:
--   1) Agrega campos a rrhh_empleados:
--       - monotributista (bool default false)
--       - monto_factura_mensual (numeric)
--   2) Documenta la regla
--   3) Verificación
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.rrhh_empleados
    ADD COLUMN IF NOT EXISTS monotributista          boolean        NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS monto_factura_mensual   numeric(12,2);

COMMENT ON COLUMN public.rrhh_empleados.monotributista IS
    'TRUE = no es empleada en relación de dependencia. Factura por monotributo. NO va al LSD AFIP ni al F.931. Se trata aparte en el Liquidador.';

COMMENT ON COLUMN public.rrhh_empleados.monto_factura_mensual IS
    'Monto fijo que factura mensualmente (se transfiere por banco). Si recibe extra en efectivo, se carga aparte en l.efectivo del Liquidador.';

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Verificación
SELECT
  apellido, nombre, cuil, local, estado,
  fuera_convenio, monotributista, monto_factura_mensual
FROM public.rrhh_empleados
WHERE estado = 'activo'
ORDER BY monotributista DESC, apellido;
