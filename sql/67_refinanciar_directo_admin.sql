-- ═══════════════════════════════════════════════════════════════════════
--  67_refinanciar_directo_admin.sql
--
--  Bug detectado: cuando el admin crea el préstamo nuevo de refinanciación
--  como "activo directo" (sin esperar confirmación de la empleada), la
--  lógica de refinanciar el viejo NUNCA se ejecuta (solo se disparaba en
--  rrhh_aceptar_prestamo, que no corre para activos directos).
--  Resultado: quedan 2 préstamos activos.
--
--  Este SQL:
--   1) Crea rrhh_refinanciar_directo(solicitud_id, prestamo_nuevo_id) que
--      vincula y, si el nuevo está activo, refinancia el viejo de una.
--   2) Arregla manualmente el caso de BIANCHI (préstamos #X y #Y).
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Nueva RPC para refinanciar directo ───────────────────────────
CREATE OR REPLACE FUNCTION public.rrhh_refinanciar_directo(
  p_solicitud_id      bigint,
  p_prestamo_nuevo_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sol record;
  v_estado_nuevo text;
  v_email text;
BEGIN
  IF NOT rrhh_is_admin() THEN RAISE EXCEPTION 'Solo admin'; END IF;

  -- Vincular la solicitud al préstamo nuevo (igual que rrhh_vincular_refinanciacion)
  SELECT email INTO v_email FROM rrhh_usuarios WHERE auth_user_id = auth.uid() LIMIT 1;
  UPDATE public.rrhh_prestamo_solicitud
     SET prestamo_resultante_id = p_prestamo_nuevo_id,
         estado = 'aprobada',
         resuelto_at = COALESCE(resuelto_at, now()),
         resuelto_por = COALESCE(resuelto_por, v_email)
   WHERE id = p_solicitud_id
   RETURNING * INTO v_sol;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud % no encontrada', p_solicitud_id; END IF;

  -- Si el préstamo nuevo ya está activo → refinanciar el viejo AHORA
  -- (si está propuesto, esperamos a que la empleada acepte — lógica existente)
  SELECT estado INTO v_estado_nuevo FROM public.rrhh_prestamo WHERE id = p_prestamo_nuevo_id;
  IF v_estado_nuevo = 'activo' AND v_sol.prestamo_id IS NOT NULL THEN
    UPDATE public.rrhh_prestamo
       SET estado = 'refinanciado',
           refinanciado_at = now(),
           refinanciado_por_id = p_prestamo_nuevo_id
     WHERE id = v_sol.prestamo_id AND estado = 'activo';
    UPDATE public.rrhh_prestamo_cuota
       SET estado = 'cancelada'
     WHERE prestamo_id = v_sol.prestamo_id AND estado = 'pendiente';
    RETURN jsonb_build_object('ok', true, 'refinanciado_inmediato', true,
      'prestamo_viejo_id', v_sol.prestamo_id, 'prestamo_nuevo_id', p_prestamo_nuevo_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'refinanciado_inmediato', false,
    'mensaje', 'Esperando a que la empleada acepte la nueva propuesta');
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_refinanciar_directo(bigint, bigint) TO authenticated;

-- ─── 2. FIX manual del caso BIANCHI ─────────────────────────────────
-- Préstamo viejo activo desde 11/01/2026 con $2.200.000, saldo $1.100.000 (5/10 cuotas)
-- Préstamo nuevo activo desde 31/05/2026 con $1.750.000 (saldo viejo + $650k adicional)
-- Marcar el viejo como refinanciado por el nuevo + cancelar cuotas pendientes.

-- Detectar IDs (admite que JP los pase explícitos si los conoce)
DO $$
DECLARE
  v_bianchi_id bigint;
  v_viejo_id   bigint;
  v_nuevo_id   bigint;
BEGIN
  SELECT id INTO v_bianchi_id FROM public.rrhh_empleados
   WHERE apellido ILIKE '%BIANCHI%' AND estado = 'activo' LIMIT 1;
  IF v_bianchi_id IS NULL THEN
    RAISE NOTICE 'No se encontró BIANCHI activa — skip fix';
    RETURN;
  END IF;

  -- El viejo: capital 2.200.000, otorgado 11/01/2026 — activo
  SELECT id INTO v_viejo_id FROM public.rrhh_prestamo
   WHERE empleado_id = v_bianchi_id AND estado = 'activo'
     AND capital = 2200000 AND fecha_otorgamiento = '2026-01-11'
   LIMIT 1;

  -- El nuevo: capital 1.750.000, otorgado 31/05/2026 — activo
  SELECT id INTO v_nuevo_id FROM public.rrhh_prestamo
   WHERE empleado_id = v_bianchi_id AND estado = 'activo'
     AND capital = 1750000 AND fecha_otorgamiento = '2026-05-31'
   LIMIT 1;

  IF v_viejo_id IS NULL OR v_nuevo_id IS NULL THEN
    RAISE NOTICE 'No se encontró el par BIANCHI viejo/nuevo (viejo=% nuevo=%)', v_viejo_id, v_nuevo_id;
    RETURN;
  END IF;

  UPDATE public.rrhh_prestamo
     SET estado = 'refinanciado',
         refinanciado_at = now(),
         refinanciado_por_id = v_nuevo_id
   WHERE id = v_viejo_id;

  UPDATE public.rrhh_prestamo_cuota
     SET estado = 'cancelada'
   WHERE prestamo_id = v_viejo_id AND estado = 'pendiente';

  RAISE NOTICE 'BIANCHI fix OK: viejo % refinanciado por nuevo %', v_viejo_id, v_nuevo_id;
END $$;

NOTIFY pgrst, 'reload schema';

-- Verificación
SELECT id, empleado_id, fecha_otorgamiento, capital, estado, refinanciado_por_id
  FROM public.rrhh_prestamo
 WHERE empleado_id = (SELECT id FROM rrhh_empleados WHERE apellido ILIKE '%BIANCHI%' LIMIT 1)
 ORDER BY fecha_otorgamiento;
