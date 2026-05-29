-- ═══════════════════════════════════════════════════════════════════════
--  46_ganancias_afip_h1_2026.sql
--  Valores oficiales ARCA/AFIP Resolución H1 2026 (enero a junio).
--  Cuando AFIP publique los de H2 2026 (julio-diciembre), agregar
--  una nueva fila con vigente_desde = '2026-07-01' actualizados.
--
--  Fuente: cuantocobro.ar / iprofesional / Consejo Profesional Córdoba
--  (publicaciones oficiales del primer semestre 2026).
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Limpiar valores aproximados anteriores ──────────────────────────
DELETE FROM public.rrhh_ganancias_mni WHERE vigente_desde = '2026-01-01';

-- Valores OFICIALES enero-junio 2026 (mensualizados = anual / 13 con SAC)
INSERT INTO public.rrhh_ganancias_mni
    (vigente_desde, mni_mensual, especial_mensual, conyuge_mensual, hijo_mensual, notas)
VALUES
    ('2026-01-01',
     ROUND(5151802.50 / 13, 2),     -- MNI: $396.292,50
     ROUND(24728652.02 / 13, 2),    -- Especial: $1.902.204,00
     ROUND(4851964.66 / 13, 2),     -- Cónyuge: $373.227,28
     ROUND(2446863.48 / 13, 2),     -- Hijo: $188.220,27
     'Valores OFICIALES ARCA Resolución H1 2026 (enero-junio). Fuente: ARCA publicaciones primer semestre 2026.')
ON CONFLICT (vigente_desde) DO UPDATE SET
    mni_mensual = EXCLUDED.mni_mensual,
    especial_mensual = EXCLUDED.especial_mensual,
    conyuge_mensual = EXCLUDED.conyuge_mensual,
    hijo_mensual = EXCLUDED.hijo_mensual,
    notas = EXCLUDED.notas;

-- ─── Campos adicionales en rrhh_empleados ─────────────────────────────
ALTER TABLE public.rrhh_empleados
    ADD COLUMN IF NOT EXISTS prepaga_mensual    numeric(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS domestica_mensual  numeric(14,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.rrhh_empleados.prepaga_mensual IS
    'Cuota mensual de prepaga (a deducir de Ganancias, cap 5% gan neta). Solo si calcular_tope_ganancias=true.';
COMMENT ON COLUMN public.rrhh_empleados.domestica_mensual IS
    'Sueldo mensual de empleada doméstica en blanco (a deducir, cap MNI anual). Solo si calcular_tope_ganancias=true.';

-- Datos personales de Claudia: prepaga $300k + doméstica $550k mensual
UPDATE public.rrhh_empleados
   SET prepaga_mensual = 300000,
       domestica_mensual = 550000
 WHERE apellido ILIKE '%ADORNO%' AND nombre ILIKE '%CLAUDIA%';

-- JP: sin deducciones adicionales
UPDATE public.rrhh_empleados
   SET prepaga_mensual = 0,
       domestica_mensual = 0
 WHERE apellido ILIKE '%SIMONELLI%' AND nombre ILIKE '%JUAN%';

-- ─── Función actualizada con caps correctos ──────────────────────────
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
  v_deducciones_anuales numeric;
  v_mni_anual numeric;
  v_prepaga_anual numeric;
  v_domestica_anual numeric;
  v_domestica_deducible numeric;
  v_prepaga_deducible numeric;
  v_bruto_tope_anual numeric;
  v_bruto_tope_mensual numeric;
  v_neto_tope_mensual  numeric;
  v_tasa_aportes constant numeric := 0.17;
BEGIN
  SELECT * INTO v_emp FROM public.rrhh_empleados WHERE id = p_empleado_id;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Empleado no encontrado'; END IF;

  SELECT * INTO v_mni
    FROM public.rrhh_ganancias_mni
   WHERE vigente_desde <= p_periodo
   ORDER BY vigente_desde DESC
   LIMIT 1;
  IF v_mni IS NULL THEN
    RAISE EXCEPTION 'No hay valores de MNI cargados para el período %', p_periodo;
  END IF;

  -- Anualizar (× 13 contando SAC)
  v_mni_anual := v_mni.mni_mensual * 13;
  v_prepaga_anual := COALESCE(v_emp.prepaga_mensual, 0) * 12;     -- prepaga es solo 12 (no SAC)
  v_domestica_anual := COALESCE(v_emp.domestica_mensual, 0) * 13; -- sí incluye SAC para doméstica

  -- Cap doméstica: hasta el MNI anual
  v_domestica_deducible := LEAST(v_domestica_anual, v_mni_anual);

  -- Deducciones base (sin prepaga porque requiere iteración)
  v_deducciones_anuales :=
      v_mni_anual
    + v_mni.especial_mensual * 13
    + (CASE WHEN v_emp.conyuge_a_cargo THEN v_mni.conyuge_mensual * 13 ELSE 0 END)
    + (v_mni.hijo_mensual * 13 * COALESCE(v_emp.hijos_a_cargo, 0))
    + v_domestica_deducible;

  -- Para prepaga: cap es 5% de la ganancia neta ANTES de prepaga.
  -- Iteración simple: bruto anual sin prepaga × 0.83 × 0.05 = cap prepaga.
  -- Mejor: cap directo al monto pagado si es menor a ~5% del bruto neto esperado.
  IF v_prepaga_anual > 0 THEN
    -- Estimación: 5% de (Bruto Anual sin prepaga × 0.83)
    -- Bruto Anual sin prepaga = deducciones_anuales / 0.83
    DECLARE
      v_bruto_aprox numeric := v_deducciones_anuales / (1 - v_tasa_aportes);
      v_gan_neta_aprox numeric := v_bruto_aprox * (1 - v_tasa_aportes);
      v_cap_prepaga numeric := v_gan_neta_aprox * 0.05;
    BEGIN
      v_prepaga_deducible := LEAST(v_prepaga_anual, v_cap_prepaga);
    END;
    v_deducciones_anuales := v_deducciones_anuales + v_prepaga_deducible;
  ELSE
    v_prepaga_deducible := 0;
  END IF;

  -- Cálculo final
  v_bruto_tope_anual    := v_deducciones_anuales / (1 - v_tasa_aportes);
  v_bruto_tope_mensual  := v_bruto_tope_anual / 13;
  v_neto_tope_mensual   := v_bruto_tope_mensual * (1 - v_tasa_aportes);

  RETURN jsonb_build_object(
    'empleado_id', p_empleado_id,
    'periodo', p_periodo,
    'deducciones_anuales', round(v_deducciones_anuales, 2),
    'detalle', jsonb_build_object(
      'mni',       v_mni_anual,
      'especial',  v_mni.especial_mensual * 13,
      'conyuge',   CASE WHEN v_emp.conyuge_a_cargo THEN v_mni.conyuge_mensual * 13 ELSE 0 END,
      'hijos',     v_mni.hijo_mensual * 13 * COALESCE(v_emp.hijos_a_cargo, 0),
      'domestica_deducible', v_domestica_deducible,
      'prepaga_deducible',   v_prepaga_deducible
    ),
    'bruto_tope_mensual', round(v_bruto_tope_mensual, 2),
    'neto_tope_mensual', round(v_neto_tope_mensual, 2),
    'notas_mni', v_mni.notas
  );
END $$;

-- ─── Verificación final ──────────────────────────────────────────────
SELECT
  e.nombre_completo,
  e.conyuge_a_cargo,
  e.hijos_a_cargo,
  e.prepaga_mensual,
  e.domestica_mensual,
  rrhh_calcular_tope_ganancias(e.id, '2026-06-01') AS calculo
FROM public.rrhh_empleados e
WHERE e.calcular_tope_ganancias = true
ORDER BY e.apellido;

NOTIFY pgrst, 'reload schema';
