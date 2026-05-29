-- ═══════════════════════════════════════════════════════════════════════
--  45_ganancias_mni_tabla.sql
--  Infraestructura para calcular automáticamente el TOPE de Ganancias
--  4ta categoría (sueldos en relación de dependencia).
--
--  ⚠️  ATENCIÓN: los valores en este archivo son APROXIMADOS basados en
--  estimaciones de evolución 2024-2026. ANTES de activar el cálculo
--  automático para Claudia/JP en producción, JP tiene que verificarlos
--  con el estudio contable y corregir si hace falta.
--
--  Después de correr: NOTIFY pgrst, 'reload schema';
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Tabla con los mínimos no imponibles vigentes por período ─────────
CREATE TABLE IF NOT EXISTS public.rrhh_ganancias_mni (
    id                  bigserial PRIMARY KEY,
    vigente_desde       date NOT NULL,    -- mes de inicio
    mni_mensual         numeric(14,2) NOT NULL, -- Mínimo no imponible mensual
    especial_mensual    numeric(14,2) NOT NULL, -- Deducción especial 4ta categoría mensual
    conyuge_mensual     numeric(14,2) NOT NULL, -- Deducción x cónyuge a cargo mensual
    hijo_mensual        numeric(14,2) NOT NULL, -- Deducción x hijo menor a cargo mensual
    notas               text,
    UNIQUE (vigente_desde)
);

ALTER TABLE public.rrhh_ganancias_mni ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS rrhh_gan_mni_select_all
    ON public.rrhh_ganancias_mni FOR SELECT
    USING (auth.uid() IS NOT NULL);

CREATE POLICY IF NOT EXISTS rrhh_gan_mni_admin_modify
    ON public.rrhh_ganancias_mni FOR ALL
    USING (rrhh_is_admin());

-- ⚠️ VALORES APROXIMADOS — VERIFICAR CON CONTADOR ANTES DE USAR
INSERT INTO public.rrhh_ganancias_mni
    (vigente_desde, mni_mensual, especial_mensual, conyuge_mensual, hijo_mensual, notas)
VALUES
    ('2026-01-01', 500000, 2400000, 465000, 235000,
     '⚠ APROXIMADO basado en proyección 2024-2026. Verificar con estudio.')
ON CONFLICT (vigente_desde) DO NOTHING;

-- ─── Campos en rrhh_empleados para indicar si aplica el cálculo ───────
ALTER TABLE public.rrhh_empleados
    ADD COLUMN IF NOT EXISTS calcular_tope_ganancias boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS conyuge_a_cargo         boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS hijos_a_cargo           int     NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.rrhh_empleados.calcular_tope_ganancias IS
    'Si TRUE, el panel Pagos del mes calcula el neto automáticamente como tope antes de que se aplique Ganancias 4ta categoría.';
COMMENT ON COLUMN public.rrhh_empleados.conyuge_a_cargo IS
    'TRUE si el cónyuge no percibe ganancias y es a cargo del empleado.';
COMMENT ON COLUMN public.rrhh_empleados.hijos_a_cargo IS
    'Cantidad de hijos menores de 18 años a cargo del empleado para deducción de Ganancias.';

-- ─── Función: calcula el tope de bruto y neto para un empleado ────────
CREATE OR REPLACE FUNCTION public.rrhh_calcular_tope_ganancias(
  p_empleado_id bigint,
  p_periodo     date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp record;
  v_mni record;
  v_deducciones_mensuales numeric;
  v_bruto_tope numeric;
  v_neto_tope  numeric;
  v_tasa_aportes constant numeric := 0.17;  -- 11% jub + 3% PAMI + 3% OS
BEGIN
  SELECT * INTO v_emp FROM public.rrhh_empleados WHERE id = p_empleado_id;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Empleado no encontrado'; END IF;

  -- Buscar valores vigentes para el período
  SELECT * INTO v_mni
    FROM public.rrhh_ganancias_mni
   WHERE vigente_desde <= p_periodo
   ORDER BY vigente_desde DESC
   LIMIT 1;
  IF v_mni IS NULL THEN
    RAISE EXCEPTION 'No hay valores de MNI cargados para el período %', p_periodo;
  END IF;

  -- Deducciones mensuales totales
  v_deducciones_mensuales :=
      v_mni.mni_mensual
    + v_mni.especial_mensual
    + (CASE WHEN v_emp.conyuge_a_cargo THEN v_mni.conyuge_mensual ELSE 0 END)
    + (v_mni.hijo_mensual * COALESCE(v_emp.hijos_a_cargo, 0));

  -- Para que (Bruto - Aportes) <= Deducciones:
  --   Bruto × (1 - tasa_aportes) <= Deducciones
  --   Bruto <= Deducciones / (1 - tasa_aportes)
  v_bruto_tope := v_deducciones_mensuales / (1 - v_tasa_aportes);
  v_neto_tope  := v_bruto_tope * (1 - v_tasa_aportes);

  RETURN jsonb_build_object(
    'empleado_id', p_empleado_id,
    'periodo', p_periodo,
    'mni_mensual', v_mni.mni_mensual,
    'especial_mensual', v_mni.especial_mensual,
    'conyuge_mensual', CASE WHEN v_emp.conyuge_a_cargo THEN v_mni.conyuge_mensual ELSE 0 END,
    'hijos_total', v_mni.hijo_mensual * COALESCE(v_emp.hijos_a_cargo, 0),
    'deducciones_mensuales', v_deducciones_mensuales,
    'bruto_tope', round(v_bruto_tope, 2),
    'neto_tope', round(v_neto_tope, 2),
    'notas_mni', v_mni.notas
  );
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_calcular_tope_ganancias(bigint, date) TO authenticated;

-- ─── Marcar Claudia y JP como "calcular tope ganancias" ───────────────
UPDATE public.rrhh_empleados
   SET calcular_tope_ganancias = true,
       conyuge_a_cargo = true,
       hijos_a_cargo = 0
 WHERE apellido ILIKE '%ADORNO%' AND nombre ILIKE '%CLAUDIA%';

UPDATE public.rrhh_empleados
   SET calcular_tope_ganancias = true,
       conyuge_a_cargo = false,
       hijos_a_cargo = 0
 WHERE apellido ILIKE '%SIMONELLI%' AND nombre ILIKE '%JUAN%';

-- ─── Verificación: ver topes calculados para Claudia y JP en mayo 2026
SELECT
  e.nombre_completo,
  e.calcular_tope_ganancias,
  e.conyuge_a_cargo,
  e.hijos_a_cargo,
  rrhh_calcular_tope_ganancias(e.id, '2026-05-01') AS calculo
FROM public.rrhh_empleados e
WHERE e.calcular_tope_ganancias = true;

NOTIFY pgrst, 'reload schema';
