-- ═══════════════════════════════════════════════════════════════════════
--  41_marcar_cuotas_historicas_bulk.sql
--  OPERACIÓN ONE-SHOT (mayo 2026):
--  Marca TODAS las cuotas pendientes con mes_descuento ANTERIOR a mayo 2026
--  como 'aplicada' (asumiendo que MEMOSOFT ya las descontó en meses pasados).
--
--  Esto es para préstamos viejos cargados con todas las cuotas pendientes,
--  donde las cuotas anteriores a mayo en realidad ya fueron pagadas.
--
--  USO RECOMENDADO:
--    1. Correr el SELECT primero (línea 23 abajo) para ver QUÉ va a tocar.
--    2. Si te parece bien, correr el UPDATE (línea 45) y listo.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── PREVIEW: ¿qué cuotas se van a marcar como pagadas? ──────────────
-- Corré PRIMERO esto solo (seleccionalo y ejecutalo). Revisá el resultado.
-- Si te parece bien, después corré el UPDATE de más abajo.

SELECT
  e.nombre_completo                     AS empleada,
  p.id                                  AS prestamo_id,
  p.capital,
  p.cuotas_totales,
  p.fecha_otorgamiento,
  c.numero                              AS num_cuota,
  c.mes_descuento,
  c.monto_total,
  c.estado
FROM public.rrhh_prestamo_cuota c
JOIN public.rrhh_prestamo p   ON p.id = c.prestamo_id
JOIN public.rrhh_empleados e  ON e.id = p.empleado_id
WHERE c.estado = 'pendiente'
  AND c.mes_descuento < '2026-05-01'
  AND p.estado = 'activo'
ORDER BY e.apellido, p.id, c.numero;


-- ─── UPDATE: marcar como aplicadas ────────────────────────────────────
-- Una vez que confirmaste el preview, ejecutá ESTO:

/*
UPDATE public.rrhh_prestamo_cuota
   SET estado      = 'aplicada',
       aplicada_at = NOW()
 WHERE estado = 'pendiente'
   AND mes_descuento < '2026-05-01'
   AND prestamo_id IN (
     SELECT id FROM public.rrhh_prestamo WHERE estado = 'activo'
   );

-- Después, marcar como 'pagado' los préstamos que quedaron sin cuotas pendientes
UPDATE public.rrhh_prestamo
   SET estado = 'pagado'
 WHERE estado = 'activo'
   AND NOT EXISTS (
     SELECT 1 FROM public.rrhh_prestamo_cuota
      WHERE prestamo_id = rrhh_prestamo.id
        AND estado = 'pendiente'
   );
*/

-- ─── BORRA los comentarios /* */ de arriba antes de ejecutar el UPDATE ─
