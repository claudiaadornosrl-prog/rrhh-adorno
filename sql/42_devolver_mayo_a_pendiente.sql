-- ═══════════════════════════════════════════════════════════════════════
--  42_devolver_mayo_a_pendiente.sql
--  Las cuotas con mes_descuento = '2026-05-01' fueron marcadas como
--  'aplicada' por error (al marcar históricas se contó 1 de más).
--  Las devolvemos a 'pendiente' para que el panel "Pagos del mes" las
--  vea y se descuenten en la liquidación de mayo.
-- ═══════════════════════════════════════════════════════════════════════

-- Paso 1: preview de lo que se va a corregir
SELECT
  e.nombre_completo AS empleada,
  p.id              AS prestamo_id,
  c.numero          AS num_cuota,
  c.mes_descuento,
  c.monto_total,
  c.estado          AS estado_actual
FROM public.rrhh_prestamo_cuota c
JOIN public.rrhh_prestamo p   ON p.id = c.prestamo_id
JOIN public.rrhh_empleados e  ON e.id = p.empleado_id
WHERE c.estado = 'aplicada'
  AND c.mes_descuento = '2026-05-01'
ORDER BY e.apellido;

-- Paso 2: revertir mayo a pendiente
UPDATE public.rrhh_prestamo_cuota
   SET estado      = 'pendiente',
       aplicada_at = NULL
 WHERE estado = 'aplicada'
   AND mes_descuento = '2026-05-01'
RETURNING prestamo_id, numero, mes_descuento, monto_total;

-- Paso 3: re-activar préstamos que habían pasado a 'pagado' por error
UPDATE public.rrhh_prestamo
   SET estado = 'activo'
 WHERE estado = 'pagado'
   AND EXISTS (
     SELECT 1 FROM public.rrhh_prestamo_cuota
      WHERE prestamo_id = rrhh_prestamo.id
        AND estado = 'pendiente'
   )
RETURNING id;

NOTIFY pgrst, 'reload schema';
