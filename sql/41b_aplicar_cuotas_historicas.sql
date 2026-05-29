-- ═══════════════════════════════════════════════════════════════════════
--  41b_aplicar_cuotas_historicas.sql
--  EJECUTAR todo de una. Marca cuotas anteriores a mayo 2026 como pagadas
--  y cierra los préstamos sin pendientes.
-- ═══════════════════════════════════════════════════════════════════════

-- Paso 1: marcar cuotas atrasadas como aplicadas
UPDATE public.rrhh_prestamo_cuota
   SET estado      = 'aplicada',
       aplicada_at = NOW()
 WHERE estado = 'pendiente'
   AND mes_descuento < '2026-05-01'
   AND prestamo_id IN (
     SELECT id FROM public.rrhh_prestamo WHERE estado = 'activo'
   )
RETURNING prestamo_id, numero, mes_descuento, monto_total;

-- Paso 2: cerrar préstamos que quedaron sin cuotas pendientes
UPDATE public.rrhh_prestamo
   SET estado = 'pagado'
 WHERE estado = 'activo'
   AND NOT EXISTS (
     SELECT 1 FROM public.rrhh_prestamo_cuota
      WHERE prestamo_id = rrhh_prestamo.id
        AND estado = 'pendiente'
   )
RETURNING id, capital, cuotas_totales;

-- Refrescar cache de PostgREST por las dudas
NOTIFY pgrst, 'reload schema';
