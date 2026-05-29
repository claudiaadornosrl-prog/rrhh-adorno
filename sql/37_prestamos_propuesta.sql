-- ═══════════════════════════════════════════════════════════════════════
--  37_prestamos_propuesta.sql
--  Workflow de PROPUESTA / ACEPTACIÓN para préstamos
--
--  Hasta ahora: admin crea préstamo y queda directamente 'activo'.
--  Ahora: admin puede crear el préstamo como 'propuesto' (toggle en UI).
--         La empleada lo ve en self-service, lo acepta o lo rechaza.
--         Solo cuando acepta pasa a 'activo' y empiezan los descuentos.
--
--  Estados de rrhh_prestamo:
--    propuesto              ← admin lo cargó, esperando aceptación
--    activo                 ← descontando cuotas
--    pagado                 ← terminó normal
--    cancelado_anticipado   ← admin lo canceló (perdón de saldo, renuncia, etc.)
--    rechazado              ← empleada lo rechazó
--
--  Estados de rrhh_prestamo_cuota:
--    propuesta              ← cuota proyectada, NO se descuenta hasta que acepte
--    pendiente              ← lista para descontar el próximo cierre
--    aplicada               ← ya descontada en una liquidación
--    cancelada              ← admin canceló préstamo
--    rechazada              ← empleada rechazó la propuesta
--
--  Después de correr: NOTIFY pgrst, 'reload schema';
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Columnas nuevas en rrhh_prestamo ─────────────────────────────────
ALTER TABLE public.rrhh_prestamo
    ADD COLUMN IF NOT EXISTS aceptado_at     timestamptz,
    ADD COLUMN IF NOT EXISTS rechazado_at    timestamptz,
    ADD COLUMN IF NOT EXISTS rechazo_motivo  text,
    ADD COLUMN IF NOT EXISTS propuesto_por   text;

COMMENT ON COLUMN public.rrhh_prestamo.aceptado_at IS
    'Fecha en que la empleada aceptó la propuesta. Null si nunca pasó por estado propuesto.';
COMMENT ON COLUMN public.rrhh_prestamo.rechazado_at IS
    'Fecha en que la empleada rechazó la propuesta.';
COMMENT ON COLUMN public.rrhh_prestamo.rechazo_motivo IS
    'Motivo del rechazo (opcional, lo carga la empleada).';
COMMENT ON COLUMN public.rrhh_prestamo.propuesto_por IS
    'Email del admin que creó la propuesta (si vino vía workflow propuesta→aceptación).';

-- ─── Constraint del enum de estados (drop and recreate si ya existía) ─
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rrhh_prestamo_estado_check') THEN
    ALTER TABLE public.rrhh_prestamo DROP CONSTRAINT rrhh_prestamo_estado_check;
  END IF;
END $$;

ALTER TABLE public.rrhh_prestamo
    ADD CONSTRAINT rrhh_prestamo_estado_check
    CHECK (estado IN ('propuesto', 'activo', 'pagado', 'cancelado_anticipado', 'rechazado'));

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rrhh_prestamo_cuota_estado_check') THEN
    ALTER TABLE public.rrhh_prestamo_cuota DROP CONSTRAINT rrhh_prestamo_cuota_estado_check;
  END IF;
END $$;

ALTER TABLE public.rrhh_prestamo_cuota
    ADD CONSTRAINT rrhh_prestamo_cuota_estado_check
    CHECK (estado IN ('propuesta', 'pendiente', 'aplicada', 'cancelada', 'rechazada'));

-- ─── RLS: empleada puede ver sus propios préstamos ─────────────────────
-- (asume que rrhh_prestamo y rrhh_prestamo_cuota ya tienen RLS habilitado
--  desde la migración 33_prestamos.sql; acá solo agregamos política de SELECT
--  para empleada si no existía)

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'rrhh_prestamo'
    AND policyname = 'rrhh_prestamo_self_select'
  ) THEN
    EXECUTE $POL$
      CREATE POLICY rrhh_prestamo_self_select
        ON public.rrhh_prestamo
        FOR SELECT
        USING (empleado_id = rrhh_mi_empleado_id());
    $POL$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'rrhh_prestamo_cuota'
    AND policyname = 'rrhh_prestamo_cuota_self_select'
  ) THEN
    EXECUTE $POL$
      CREATE POLICY rrhh_prestamo_cuota_self_select
        ON public.rrhh_prestamo_cuota
        FOR SELECT
        USING (
          prestamo_id IN (
            SELECT id FROM public.rrhh_prestamo
            WHERE empleado_id = rrhh_mi_empleado_id()
          )
        );
    $POL$;
  END IF;
END $$;

-- ─── RPC: aceptar préstamo (SECURITY DEFINER) ─────────────────────────
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
BEGIN
  -- Verificar que el préstamo pertenece a la empleada autenticada
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

  -- Si el mes_primer_descuento ya pasó, lo movemos al mes próximo
  v_ahora_mes := date_trunc('month', CURRENT_DATE)::date;
  IF v_mes_primer < v_ahora_mes THEN
    v_mes_primer := (v_ahora_mes + interval '1 month')::date;
  END IF;

  -- Activar préstamo y cuotas
  UPDATE public.rrhh_prestamo
     SET estado = 'activo',
         aceptado_at = now(),
         mes_primer_descuento = v_mes_primer
   WHERE id = p_prestamo_id;

  -- Re-mapear las cuotas: la cuota 1 va a v_mes_primer, las siguientes mensuales
  UPDATE public.rrhh_prestamo_cuota c
     SET estado = 'pendiente',
         mes_descuento = (v_mes_primer + (c.numero - 1) * interval '1 month')::date
   WHERE c.prestamo_id = p_prestamo_id
     AND c.estado = 'propuesta';

  GET DIAGNOSTICS v_mov_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'prestamo_id', p_prestamo_id,
    'cuotas_activadas', v_mov_count,
    'mes_primer_descuento', v_mes_primer
  );
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_aceptar_prestamo(bigint) TO authenticated;

-- ─── RPC: rechazar préstamo (SECURITY DEFINER) ─────────────────────────
CREATE OR REPLACE FUNCTION public.rrhh_rechazar_prestamo(
  p_prestamo_id bigint,
  p_motivo      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_id bigint;
  v_estado text;
BEGIN
  SELECT empleado_id, estado
    INTO v_emp_id, v_estado
  FROM public.rrhh_prestamo
  WHERE id = p_prestamo_id;

  IF v_emp_id IS NULL THEN
    RAISE EXCEPTION 'Préstamo no encontrado';
  END IF;
  IF v_emp_id <> rrhh_mi_empleado_id() THEN
    RAISE EXCEPTION 'No tenés permiso para rechazar este préstamo';
  END IF;
  IF v_estado <> 'propuesto' THEN
    RAISE EXCEPTION 'Solo se puede rechazar un préstamo en estado propuesto (actual: %)', v_estado;
  END IF;

  UPDATE public.rrhh_prestamo
     SET estado = 'rechazado',
         rechazado_at = now(),
         rechazo_motivo = NULLIF(trim(coalesce(p_motivo, '')), '')
   WHERE id = p_prestamo_id;

  UPDATE public.rrhh_prestamo_cuota
     SET estado = 'rechazada'
   WHERE prestamo_id = p_prestamo_id
     AND estado = 'propuesta';

  RETURN jsonb_build_object('ok', true, 'prestamo_id', p_prestamo_id);
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_rechazar_prestamo(bigint, text) TO authenticated;

-- ─── Refrescar cache de PostgREST ─────────────────────────────────────
NOTIFY pgrst, 'reload schema';
