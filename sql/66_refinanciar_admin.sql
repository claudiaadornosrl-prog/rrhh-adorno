-- ═══════════════════════════════════════════════════════════════════════
--  66_refinanciar_admin.sql
--
--  Permite que el admin (JP) inicie una refinanciación SIN que la vendedora
--  haya hecho la solicitud previa desde su self-service.
--
--  Crea una solicitud ya en estado 'aprobada', devolviendo el ID para que
--  el front lo use en window._prestamoRefiSolicitudId y dispare el wizard
--  normal de nueva propuesta. Cuando la empleada acepte la nueva propuesta,
--  el préstamo viejo queda 'refinanciado' (lógica existente en
--  rrhh_aceptar_prestamo).
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rrhh_iniciar_refinanciacion_admin(
  p_prestamo_id       bigint,
  p_capital_adicional numeric,
  p_cuotas            int,
  p_motivo            text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_id    bigint;
  v_estado    text;
  v_sol_id    bigint;
  v_email     text;
BEGIN
  IF NOT rrhh_is_admin() THEN
    RAISE EXCEPTION 'Solo admin puede iniciar refinanciación directa';
  END IF;

  SELECT empleado_id, estado INTO v_emp_id, v_estado
    FROM public.rrhh_prestamo WHERE id = p_prestamo_id;

  IF v_emp_id IS NULL THEN
    RAISE EXCEPTION 'Préstamo % no encontrado', p_prestamo_id;
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'Solo se puede refinanciar préstamos activos (actual: %)', v_estado;
  END IF;
  IF NOT (p_capital_adicional > 0) THEN
    RAISE EXCEPTION 'Capital adicional debe ser > 0';
  END IF;
  IF p_cuotas IS NULL OR p_cuotas < 1 OR p_cuotas > 60 THEN
    RAISE EXCEPTION 'Cuotas debe estar entre 1 y 60';
  END IF;

  SELECT email INTO v_email FROM rrhh_usuarios WHERE auth_user_id = auth.uid() LIMIT 1;

  -- Crear solicitud ya APROBADA (la dispara el admin, no la vendedora)
  INSERT INTO public.rrhh_prestamo_solicitud
    (empleado_id, tipo, prestamo_id, capital_adicional, cuotas_solicitadas, motivo,
     estado, solicitado_at, resuelto_at, resuelto_por)
  VALUES
    (v_emp_id, 'refinanciacion', p_prestamo_id, p_capital_adicional, p_cuotas,
     NULLIF(trim(coalesce(p_motivo, '')), '') || ' [iniciada por admin]',
     'aprobada', now(), now(), v_email)
  RETURNING id INTO v_sol_id;

  RETURN jsonb_build_object('ok', true, 'solicitud_id', v_sol_id, 'empleado_id', v_emp_id);
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_iniciar_refinanciacion_admin(bigint, numeric, int, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Verificación
SELECT 'rrhh_iniciar_refinanciacion_admin creada OK' AS estado;
