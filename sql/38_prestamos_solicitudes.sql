-- ═══════════════════════════════════════════════════════════════════════
--  38_prestamos_solicitudes.sql
--  Solicitudes que la vendedora dispara desde su self-service:
--    - REFINANCIACIÓN: pedir capital adicional sobre un préstamo activo.
--                      Al aprobar, el admin crea una nueva PROPUESTA con
--                      capital = saldo_viejo + capital_adicional. Cuando
--                      la empleada acepta la propuesta nueva, el préstamo
--                      viejo pasa a 'refinanciado'.
--    - ADELANTAR CUOTAS: pagar más en un mes para terminar antes. Al aprobar,
--                      las últimas N cuotas pendientes se mueven al mes
--                      elegido (se acumulan), el préstamo termina antes.
--
--  Después de correr: NOTIFY pgrst, 'reload schema';
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Nuevo estado en rrhh_prestamo ────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rrhh_prestamo_estado_check') THEN
    ALTER TABLE public.rrhh_prestamo DROP CONSTRAINT rrhh_prestamo_estado_check;
  END IF;
END $$;

ALTER TABLE public.rrhh_prestamo
    ADD CONSTRAINT rrhh_prestamo_estado_check
    CHECK (estado IN ('propuesto', 'activo', 'pagado', 'cancelado_anticipado', 'rechazado', 'refinanciado'));

ALTER TABLE public.rrhh_prestamo
    ADD COLUMN IF NOT EXISTS refinanciado_at      timestamptz,
    ADD COLUMN IF NOT EXISTS refinanciado_por_id  bigint REFERENCES public.rrhh_prestamo(id);

COMMENT ON COLUMN public.rrhh_prestamo.refinanciado_por_id IS
    'Si este préstamo fue refinanciado, apunta al préstamo NUEVO que lo reemplazó.';

-- ─── Tabla rrhh_prestamo_solicitud ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rrhh_prestamo_solicitud (
    id                bigserial PRIMARY KEY,
    empleado_id       bigint NOT NULL REFERENCES public.rrhh_empleados(id) ON DELETE CASCADE,
    tipo              text   NOT NULL CHECK (tipo IN ('refinanciacion', 'adelantar_cuotas')),
    prestamo_id       bigint REFERENCES public.rrhh_prestamo(id) ON DELETE SET NULL,

    -- Refinanciación:
    capital_adicional       numeric(14,2),
    cuotas_solicitadas      int,

    -- Adelantar cuotas:
    cuotas_a_adelantar      int,
    mes_descuento           date,

    motivo                  text,
    estado                  text NOT NULL DEFAULT 'pendiente'
                              CHECK (estado IN ('pendiente', 'aprobada', 'rechazada', 'cancelada')),
    solicitado_at           timestamptz NOT NULL DEFAULT now(),
    resuelto_at             timestamptz,
    resuelto_por            text,
    motivo_rechazo          text,
    prestamo_resultante_id  bigint REFERENCES public.rrhh_prestamo(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_pres_solic_emp ON public.rrhh_prestamo_solicitud(empleado_id);
CREATE INDEX IF NOT EXISTS idx_pres_solic_estado ON public.rrhh_prestamo_solicitud(estado);

-- ─── RLS ───────────────────────────────────────────────────────────────
ALTER TABLE public.rrhh_prestamo_solicitud ENABLE ROW LEVEL SECURITY;

CREATE POLICY rrhh_pres_solic_self_select
    ON public.rrhh_prestamo_solicitud FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

CREATE POLICY rrhh_pres_solic_admin_all
    ON public.rrhh_prestamo_solicitud FOR ALL
    USING (rrhh_is_admin());

-- ─── RPC: crear solicitud de refinanciación ───────────────────────────
CREATE OR REPLACE FUNCTION public.rrhh_solicitar_refinanciacion(
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
  v_emp_id bigint;
  v_estado text;
  v_solic_id bigint;
BEGIN
  SELECT empleado_id, estado INTO v_emp_id, v_estado
    FROM public.rrhh_prestamo WHERE id = p_prestamo_id;
  IF v_emp_id IS NULL THEN RAISE EXCEPTION 'Préstamo no encontrado'; END IF;
  IF v_emp_id <> rrhh_mi_empleado_id() THEN
    RAISE EXCEPTION 'No tenés permiso para refinanciar este préstamo';
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'Solo se puede refinanciar un préstamo activo (actual: %)', v_estado;
  END IF;
  IF NOT (p_capital_adicional > 0) THEN RAISE EXCEPTION 'Capital adicional debe ser > 0'; END IF;
  IF NOT (p_cuotas > 0) THEN RAISE EXCEPTION 'Cuotas debe ser > 0'; END IF;

  INSERT INTO public.rrhh_prestamo_solicitud
    (empleado_id, tipo, prestamo_id, capital_adicional, cuotas_solicitadas, motivo)
    VALUES
    (v_emp_id, 'refinanciacion', p_prestamo_id, p_capital_adicional, p_cuotas, NULLIF(trim(coalesce(p_motivo, '')), ''))
  RETURNING id INTO v_solic_id;

  RETURN jsonb_build_object('ok', true, 'solicitud_id', v_solic_id);
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_solicitar_refinanciacion(bigint, numeric, int, text) TO authenticated;

-- ─── RPC: crear solicitud de adelantar cuotas ─────────────────────────
CREATE OR REPLACE FUNCTION public.rrhh_solicitar_adelantar_cuotas(
  p_prestamo_id  bigint,
  p_cuotas       int,
  p_mes_descuento date,
  p_motivo       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_id bigint;
  v_estado text;
  v_pendientes int;
  v_solic_id bigint;
BEGIN
  SELECT empleado_id, estado INTO v_emp_id, v_estado
    FROM public.rrhh_prestamo WHERE id = p_prestamo_id;
  IF v_emp_id IS NULL THEN RAISE EXCEPTION 'Préstamo no encontrado'; END IF;
  IF v_emp_id <> rrhh_mi_empleado_id() THEN
    RAISE EXCEPTION 'No tenés permiso para adelantar cuotas en este préstamo';
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'Solo se puede adelantar cuotas en un préstamo activo (actual: %)', v_estado;
  END IF;
  IF NOT (p_cuotas > 0) THEN RAISE EXCEPTION 'Debés adelantar al menos 1 cuota'; END IF;

  SELECT COUNT(*) INTO v_pendientes
    FROM public.rrhh_prestamo_cuota
    WHERE prestamo_id = p_prestamo_id AND estado = 'pendiente';
  IF p_cuotas > v_pendientes THEN
    RAISE EXCEPTION 'Tenés % cuotas pendientes; no podés adelantar %', v_pendientes, p_cuotas;
  END IF;

  INSERT INTO public.rrhh_prestamo_solicitud
    (empleado_id, tipo, prestamo_id, cuotas_a_adelantar, mes_descuento, motivo)
    VALUES
    (v_emp_id, 'adelantar_cuotas', p_prestamo_id, p_cuotas, p_mes_descuento, NULLIF(trim(coalesce(p_motivo, '')), ''))
  RETURNING id INTO v_solic_id;

  RETURN jsonb_build_object('ok', true, 'solicitud_id', v_solic_id);
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_solicitar_adelantar_cuotas(bigint, int, date, text) TO authenticated;

-- ─── RPC: rechazar solicitud (admin) ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.rrhh_rechazar_solicitud_prestamo(
  p_solicitud_id bigint,
  p_motivo       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT rrhh_is_admin() THEN RAISE EXCEPTION 'Solo admin'; END IF;
  UPDATE public.rrhh_prestamo_solicitud
     SET estado = 'rechazada',
         resuelto_at = now(),
         resuelto_por = (SELECT email FROM rrhh_usuarios WHERE auth_user_id = auth.uid() LIMIT 1),
         motivo_rechazo = NULLIF(trim(coalesce(p_motivo, '')), '')
   WHERE id = p_solicitud_id AND estado = 'pendiente';
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no encontrada o ya resuelta'; END IF;
  RETURN jsonb_build_object('ok', true);
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_rechazar_solicitud_prestamo(bigint, text) TO authenticated;

-- ─── RPC: aplicar adelanto de cuotas (admin aprueba) ──────────────────
-- Mueve las últimas N cuotas pendientes al mes elegido (se acumulan ahí).
-- El préstamo termina antes.
CREATE OR REPLACE FUNCTION public.rrhh_aplicar_adelanto_cuotas(p_solicitud_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sol record;
BEGIN
  IF NOT rrhh_is_admin() THEN RAISE EXCEPTION 'Solo admin'; END IF;
  SELECT * INTO v_sol FROM public.rrhh_prestamo_solicitud
    WHERE id = p_solicitud_id AND estado = 'pendiente';
  IF v_sol IS NULL THEN RAISE EXCEPTION 'Solicitud no encontrada o ya resuelta'; END IF;
  IF v_sol.tipo <> 'adelantar_cuotas' THEN
    RAISE EXCEPTION 'Esta solicitud no es de adelantar cuotas';
  END IF;

  -- Mover las últimas N cuotas pendientes al mes elegido
  -- (se actualizan a mes_descuento = v_sol.mes_descuento)
  WITH ultimas AS (
    SELECT id FROM public.rrhh_prestamo_cuota
    WHERE prestamo_id = v_sol.prestamo_id AND estado = 'pendiente'
    ORDER BY numero DESC
    LIMIT v_sol.cuotas_a_adelantar
  )
  UPDATE public.rrhh_prestamo_cuota c
     SET mes_descuento = v_sol.mes_descuento
   WHERE c.id IN (SELECT id FROM ultimas);

  UPDATE public.rrhh_prestamo_solicitud
     SET estado = 'aprobada',
         resuelto_at = now(),
         resuelto_por = (SELECT email FROM rrhh_usuarios WHERE auth_user_id = auth.uid() LIMIT 1)
   WHERE id = p_solicitud_id;

  RETURN jsonb_build_object('ok', true, 'cuotas_movidas', v_sol.cuotas_a_adelantar, 'nuevo_mes', v_sol.mes_descuento);
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_aplicar_adelanto_cuotas(bigint) TO authenticated;

-- ─── RPC: vincular nueva propuesta con solicitud de refinanciación ────
-- El admin después de crear la propuesta nueva vía UI, conecta los dos
-- para que cuando la empleada acepte el nuevo, el viejo se refinancie.
CREATE OR REPLACE FUNCTION public.rrhh_vincular_refinanciacion(
  p_solicitud_id bigint,
  p_prestamo_nuevo_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT rrhh_is_admin() THEN RAISE EXCEPTION 'Solo admin'; END IF;
  UPDATE public.rrhh_prestamo_solicitud
     SET estado = 'aprobada',
         resuelto_at = now(),
         resuelto_por = (SELECT email FROM rrhh_usuarios WHERE auth_user_id = auth.uid() LIMIT 1),
         prestamo_resultante_id = p_prestamo_nuevo_id
   WHERE id = p_solicitud_id AND estado = 'pendiente';
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no encontrada o ya resuelta'; END IF;
  RETURN jsonb_build_object('ok', true);
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_vincular_refinanciacion(bigint, bigint) TO authenticated;

-- ─── Modificar rrhh_aceptar_prestamo para que también refinancie viejo ─
CREATE OR REPLACE FUNCTION public.rrhh_aceptar_prestamo(p_prestamo_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_id bigint;
  v_estado text;
  v_mes_primer date;
  v_ahora_mes date;
  v_mov_count int;
  v_sol record;
BEGIN
  SELECT empleado_id, estado, mes_primer_descuento
    INTO v_emp_id, v_estado, v_mes_primer
  FROM public.rrhh_prestamo
  WHERE id = p_prestamo_id;

  IF v_emp_id IS NULL THEN
    RAISE EXCEPTION 'Préstamo no encontrado';
  END IF;
  IF v_emp_id <> rrhh_mi_empleado_id() THEN
    RAISE EXCEPTION 'No tenés permiso para aceptar este préstamo';
  END IF;
  IF v_estado <> 'propuesto' THEN
    RAISE EXCEPTION 'Solo se puede aceptar un préstamo en estado propuesto (actual: %)', v_estado;
  END IF;

  v_ahora_mes := date_trunc('month', CURRENT_DATE)::date;
  IF v_mes_primer < v_ahora_mes THEN
    v_mes_primer := (v_ahora_mes + interval '1 month')::date;
  END IF;

  UPDATE public.rrhh_prestamo
     SET estado = 'activo', aceptado_at = now(), mes_primer_descuento = v_mes_primer
   WHERE id = p_prestamo_id;

  UPDATE public.rrhh_prestamo_cuota c
     SET estado = 'pendiente',
         mes_descuento = (v_mes_primer + (c.numero - 1) * interval '1 month')::date
   WHERE c.prestamo_id = p_prestamo_id AND c.estado = 'propuesta';
  GET DIAGNOSTICS v_mov_count = ROW_COUNT;

  -- ¿Es una propuesta de refinanciación? Si sí, refinanciar el viejo
  SELECT * INTO v_sol FROM public.rrhh_prestamo_solicitud
    WHERE prestamo_resultante_id = p_prestamo_id
      AND tipo = 'refinanciacion'
      AND estado = 'aprobada'
    LIMIT 1;

  IF v_sol IS NOT NULL AND v_sol.prestamo_id IS NOT NULL THEN
    UPDATE public.rrhh_prestamo
       SET estado = 'refinanciado',
           refinanciado_at = now(),
           refinanciado_por_id = p_prestamo_id
     WHERE id = v_sol.prestamo_id;
    UPDATE public.rrhh_prestamo_cuota
       SET estado = 'cancelada'
     WHERE prestamo_id = v_sol.prestamo_id AND estado = 'pendiente';
  END IF;

  RETURN jsonb_build_object('ok', true, 'prestamo_id', p_prestamo_id, 'cuotas_activadas', v_mov_count, 'mes_primer_descuento', v_mes_primer);
END $$;

NOTIFY pgrst, 'reload schema';
