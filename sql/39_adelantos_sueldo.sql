-- ═══════════════════════════════════════════════════════════════════════
--  39_adelantos_sueldo.sql
--  Workflow de "Pedir adelanto de sueldo" desde el self-service de la
--  empleada. Reglas de negocio:
--    - Solo entre el día 5 y el 14 (inclusive) de cada mes
--    - Monto máximo: 50% del neto del mes anterior
--    - Una sola solicitud por mes y por empleada (pendiente o aprobada)
--    - Al aprobar, se crea un préstamo 1 cuota 0% CFT
--    - Se descuenta en la liquidación del mes en curso
--    - Día de pago: el siguiente día hábil después del 14
--
--  Después de correr: NOTIFY pgrst, 'reload schema';
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Extender el CHECK de tipos en rrhh_prestamo_solicitud ────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conname = 'rrhh_prestamo_solicitud_tipo_check') THEN
    ALTER TABLE public.rrhh_prestamo_solicitud
      DROP CONSTRAINT rrhh_prestamo_solicitud_tipo_check;
  END IF;
END $$;

ALTER TABLE public.rrhh_prestamo_solicitud
  ADD CONSTRAINT rrhh_prestamo_solicitud_tipo_check
  CHECK (tipo IN ('refinanciacion', 'adelantar_cuotas', 'adelanto_sueldo'));

-- Columna nueva para el monto solicitado en un adelanto de sueldo
ALTER TABLE public.rrhh_prestamo_solicitud
    ADD COLUMN IF NOT EXISTS monto_solicitado numeric(14,2);

-- ─── Helper: calcular siguiente día hábil después de una fecha ─────────
CREATE OR REPLACE FUNCTION public.rrhh_siguiente_dia_habil(p_fecha date)
RETURNS date
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_fecha date := p_fecha + 1;
  v_es_habil boolean;
BEGIN
  -- Avanzar hasta encontrar lun-vie que no sea feriado
  FOR i IN 1..20 LOOP -- safety cap
    v_es_habil := extract(isodow from v_fecha) BETWEEN 1 AND 5
                  AND NOT EXISTS (
                    SELECT 1 FROM public.rrhh_feriados WHERE fecha = v_fecha
                  );
    EXIT WHEN v_es_habil;
    v_fecha := v_fecha + 1;
  END LOOP;
  RETURN v_fecha;
END $$;

-- ─── RPC: la empleada solicita un adelanto de sueldo ──────────────────
CREATE OR REPLACE FUNCTION public.rrhh_solicitar_adelanto_sueldo(
  p_monto  numeric,
  p_motivo text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_id      bigint;
  v_dia         int;
  v_mes_actual  date;
  v_neto_mes_ant numeric;
  v_tope        numeric;
  v_count       int;
  v_solic_id    bigint;
BEGIN
  v_emp_id := rrhh_mi_empleado_id();
  IF v_emp_id IS NULL THEN
    RAISE EXCEPTION 'Tu usuario no está vinculado a un empleado';
  END IF;

  -- 1) Ventana 5-14
  v_dia := extract(day from CURRENT_DATE)::int;
  IF v_dia < 5 OR v_dia > 14 THEN
    RAISE EXCEPTION 'Los adelantos solo se pueden pedir entre el día 5 y el 14 de cada mes';
  END IF;

  -- 2) Validar monto
  IF NOT (p_monto > 0) THEN
    RAISE EXCEPTION 'El monto debe ser mayor a 0';
  END IF;

  v_mes_actual := date_trunc('month', CURRENT_DATE)::date;

  -- 3) No puede haber otra solicitud (pendiente o aprobada) en el mes corriente
  SELECT COUNT(*) INTO v_count
    FROM public.rrhh_prestamo_solicitud
   WHERE empleado_id = v_emp_id
     AND tipo = 'adelanto_sueldo'
     AND estado IN ('pendiente', 'aprobada')
     AND solicitado_at >= v_mes_actual;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Ya tenés una solicitud de adelanto este mes. Esperá al mes que viene.';
  END IF;

  -- 4) Tope: 50% del recibo neto del mes anterior
  SELECT recibo_neto INTO v_neto_mes_ant
    FROM public.rrhh_liquidacion
   WHERE empleado_id = v_emp_id
     AND periodo = (v_mes_actual - interval '1 month')::date
   ORDER BY id DESC LIMIT 1;

  IF v_neto_mes_ant IS NULL THEN
    -- No hay liquidación del mes anterior cargada en el sistema; usar fallback
    -- conservador: no aceptar tope = NULL para no bloquear, pero advertir.
    -- Decisión: dejamos pasar sin tope, admin valida a ojo.
    v_tope := NULL;
  ELSE
    v_tope := round(v_neto_mes_ant * 0.5, 2);
    IF p_monto > v_tope THEN
      RAISE EXCEPTION 'El monto máximo que podés solicitar este mes es $%', v_tope;
    END IF;
  END IF;

  INSERT INTO public.rrhh_prestamo_solicitud
    (empleado_id, tipo, monto_solicitado, motivo)
    VALUES (v_emp_id, 'adelanto_sueldo', p_monto, NULLIF(trim(coalesce(p_motivo, '')), ''))
  RETURNING id INTO v_solic_id;

  RETURN jsonb_build_object(
    'ok', true,
    'solicitud_id', v_solic_id,
    'tope_aplicado', v_tope
  );
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_solicitar_adelanto_sueldo(numeric, text) TO authenticated;

-- ─── RPC: admin aprueba una solicitud de adelanto de sueldo ────────────
-- Crea un préstamo de 1 cuota CFT 0% (= adelanto) con mes_descuento = mes actual
CREATE OR REPLACE FUNCTION public.rrhh_aprobar_adelanto_sueldo(p_solicitud_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sol         record;
  v_admin_email text;
  v_mes_actual  date;
  v_nuevo_id    bigint;
BEGIN
  IF NOT rrhh_is_admin() THEN
    RAISE EXCEPTION 'Solo admin puede aprobar adelantos';
  END IF;

  SELECT * INTO v_sol
    FROM public.rrhh_prestamo_solicitud
   WHERE id = p_solicitud_id AND tipo = 'adelanto_sueldo' AND estado = 'pendiente';
  IF v_sol IS NULL THEN
    RAISE EXCEPTION 'Solicitud no encontrada o ya resuelta';
  END IF;

  SELECT email INTO v_admin_email
    FROM public.rrhh_usuarios WHERE auth_user_id = auth.uid() LIMIT 1;

  v_mes_actual := date_trunc('month', CURRENT_DATE)::date;

  -- 1) Crear préstamo 1 cuota 0%
  INSERT INTO public.rrhh_prestamo
    (empleado_id, fecha_otorgamiento, capital, tasa_mensual, cuotas_totales,
     cuota_monto, mes_primer_descuento, estado, otorgado_por, notas, aceptado_at)
    VALUES
    (v_sol.empleado_id, CURRENT_DATE, v_sol.monto_solicitado, 0, 1,
     v_sol.monto_solicitado, v_mes_actual, 'activo', v_admin_email,
     'Adelanto de sueldo — solicitud #' || p_solicitud_id ||
       CASE WHEN v_sol.motivo IS NOT NULL THEN ' (' || v_sol.motivo || ')' ELSE '' END,
     now())
  RETURNING id INTO v_nuevo_id;

  -- 2) Crear la cuota única
  INSERT INTO public.rrhh_prestamo_cuota
    (prestamo_id, numero, mes_descuento, monto_total, monto_capital,
     monto_interes, saldo_post_cuota, estado)
    VALUES
    (v_nuevo_id, 1, v_mes_actual, v_sol.monto_solicitado, v_sol.monto_solicitado,
     0, 0, 'pendiente');

  -- 3) Marcar la solicitud como aprobada y vincular
  UPDATE public.rrhh_prestamo_solicitud
     SET estado = 'aprobada',
         resuelto_at = now(),
         resuelto_por = v_admin_email,
         prestamo_resultante_id = v_nuevo_id
   WHERE id = p_solicitud_id;

  RETURN jsonb_build_object(
    'ok', true,
    'prestamo_id', v_nuevo_id,
    'fecha_pago_estimada', rrhh_siguiente_dia_habil((date_trunc('month', CURRENT_DATE) + interval '13 days')::date)
  );
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_aprobar_adelanto_sueldo(bigint) TO authenticated;

-- ─── Vista helper para el Excel Galicia ────────────────────────────────
-- Trae todos los adelantos del mes corriente con CBU del empleado y monto
CREATE OR REPLACE VIEW public.rrhh_adelantos_mes_actual AS
SELECT
  p.id                AS prestamo_id,
  e.id                AS empleado_id,
  e.apellido,
  e.nombre,
  e.nombre_completo,
  e.cuil,
  e.cbu,
  p.capital           AS monto,
  p.fecha_otorgamiento,
  p.notas,
  p.otorgado_por
FROM public.rrhh_prestamo p
JOIN public.rrhh_empleados e ON e.id = p.empleado_id
WHERE p.tasa_mensual = 0
  AND p.cuotas_totales = 1
  AND p.estado = 'activo'
  AND p.fecha_otorgamiento >= date_trunc('month', CURRENT_DATE)
  AND p.fecha_otorgamiento <  date_trunc('month', CURRENT_DATE) + interval '1 month';

GRANT SELECT ON public.rrhh_adelantos_mes_actual TO authenticated;

NOTIFY pgrst, 'reload schema';
