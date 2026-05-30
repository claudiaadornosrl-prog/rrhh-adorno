-- ═══════════════════════════════════════════════════════════════════════
--  49_ganancias_historico_fix.sql
--  Fix de la función rrhh_calcular_retencion_mensual + carga del histórico
--  ene-abr 2026 para Claudia y JP (extraídos de los PDFs reales del OneDrive).
--
--  PROBLEMA: la función solo leía de rrhh_liquidacion, pero Claudia y JP
--  liquidan en modo doble_blanco con override en rrhh_pagos_blanco
--  (no entran al workflow normal). Resultado: acumulado = 0 siempre.
--
--  FIX: la función ahora usa pagos_blanco como fallback cuando no hay
--  liquidación. Convierte neto→bruto con la tasa de aportes del empleado.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Agregar tasa de aportes por empleado ───────────────────────
ALTER TABLE public.rrhh_empleados
    ADD COLUMN IF NOT EXISTS tasa_aportes_ganancias numeric(6,4) NOT NULL DEFAULT 0.17;

COMMENT ON COLUMN public.rrhh_empleados.tasa_aportes_ganancias IS
    'Tasa efectiva de aportes obligatorios (jub+ley19032+OS+SEC+FAECYS) sobre bruto. Default 17.5% empleado convenio normal. Casos: 0 para LRT/Director SA, 0.1635 para fuera de convenio sin sindicato.';

-- Claudia: LRT, sin aportes
UPDATE public.rrhh_empleados
   SET tasa_aportes_ganancias = 0
 WHERE apellido ILIKE '%ADORNO%' AND nombre ILIKE '%CLAUDIA%';

-- JP: fuera de convenio (jub 11% + ley 3% + OS 3% efectivos sobre rem)
-- En los recibos reales: 504900 / 3089163 = 16.35%
UPDATE public.rrhh_empleados
   SET tasa_aportes_ganancias = 0.1635
 WHERE apellido ILIKE '%SIMONELLI%' AND nombre ILIKE '%JUAN%';

-- ─── 2. Función mejorada con fallback a rrhh_pagos_blanco ──────────
CREATE OR REPLACE FUNCTION public.rrhh_calcular_retencion_mensual(
    p_empleado_id bigint,
    p_periodo     date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_emp                rrhh_empleados%ROWTYPE;
    v_mni                rrhh_ganancias_mni%ROWTYPE;
    v_mes                int;
    v_anio               int;
    v_bruto_acum         numeric := 0;
    v_aportes_acum       numeric := 0;
    v_bruto_liq          numeric := 0;
    v_aportes_liq        numeric := 0;
    v_neto_override      numeric := 0;
    v_ganancia_neta_acum numeric;
    v_ded_anuales        numeric;
    v_prepaga_anual      numeric;
    v_prepaga_deducible  numeric;
    v_domestica_anual    numeric;
    v_domestica_deducible numeric;
    v_ded_acum           numeric;
    v_excedente          numeric;
    v_disp               numeric;
    v_bruto_sug_mes      numeric;
    v_tasa_aportes       numeric;
    v_estado             text;
    v_fuente             text;
BEGIN
    SELECT * INTO v_emp FROM rrhh_empleados WHERE id = p_empleado_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Empleado % no encontrado', p_empleado_id;
    END IF;

    v_mes  := EXTRACT(MONTH FROM p_periodo)::int;
    v_anio := EXTRACT(YEAR  FROM p_periodo)::int;
    v_tasa_aportes := COALESCE(v_emp.tasa_aportes_ganancias, 0.17);

    -- ─── 2a. Intentar leer de rrhh_liquidacion (fuente preferida) ───
    SELECT
      COALESCE(SUM(
          COALESCE(recibo_basico,0) + COALESCE(recibo_antiguedad,0) + COALESCE(recibo_presentismo,0)
        + COALESCE(recibo_sumafija_nr,0) + COALESCE(recibo_antig_nr,0) + COALESCE(recibo_pres_nr,0)
        + COALESCE(recibo_recompos_nr,0) + COALESCE(recibo_otros_rem,0)
      ), 0),
      COALESCE(SUM(
          COALESCE(recibo_jubilacion,0) + COALESCE(recibo_ley19032,0) + COALESCE(recibo_obra_social,0)
        + COALESCE(recibo_sec,0) + COALESCE(recibo_faecys,0)
      ), 0)
    INTO v_bruto_liq, v_aportes_liq
    FROM rrhh_liquidacion
    WHERE empleado_id = p_empleado_id
      AND periodo >= make_date(v_anio, 1, 1)
      AND periodo <= p_periodo;

    -- ─── 2b. Fallback a rrhh_pagos_blanco (caso Claudia/JP) ─────────
    -- Trae los meses NO cubiertos por rrhh_liquidacion
    DECLARE
        v_neto_pagos numeric;
    BEGIN
        SELECT COALESCE(SUM(neto_cct), 0)
        INTO v_neto_pagos
        FROM rrhh_pagos_blanco p
        WHERE p.empleado_id = p_empleado_id
          AND p.periodo >= make_date(v_anio, 1, 1)
          AND p.periodo <= p_periodo
          AND NOT EXISTS (
              SELECT 1 FROM rrhh_liquidacion l
              WHERE l.empleado_id = p.empleado_id AND l.periodo = p.periodo
          );

        IF v_neto_pagos > 0 THEN
            -- Convertir neto→bruto con la tasa del empleado
            -- bruto = neto / (1 - tasa)
            IF (1 - v_tasa_aportes) > 0 THEN
                v_bruto_acum   := v_bruto_liq + (v_neto_pagos / (1 - v_tasa_aportes));
                v_aportes_acum := v_aportes_liq + (v_neto_pagos / (1 - v_tasa_aportes)) * v_tasa_aportes;
            ELSE
                v_bruto_acum   := v_bruto_liq + v_neto_pagos;
                v_aportes_acum := v_aportes_liq;
            END IF;
            v_fuente := CASE WHEN v_bruto_liq > 0 THEN 'mixto' ELSE 'pagos_blanco' END;
        ELSE
            v_bruto_acum := v_bruto_liq;
            v_aportes_acum := v_aportes_liq;
            v_fuente := 'liquidacion';
        END IF;
    END;

    v_ganancia_neta_acum := v_bruto_acum - v_aportes_acum;

    -- ─── Valores AFIP/ARCA vigentes ───
    SELECT * INTO v_mni
      FROM rrhh_ganancias_mni
     WHERE vigente_desde <= p_periodo
     ORDER BY vigente_desde DESC
     LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay valores MNI cargados para %', p_periodo;
    END IF;

    -- ─── Deducciones anuales (con SAC = factor 13) ───
    v_domestica_anual     := COALESCE(v_emp.domestica_mensual, 0) * 13;
    v_domestica_deducible := LEAST(v_domestica_anual, v_mni.mni_mensual * 13);

    v_prepaga_anual := COALESCE(v_emp.prepaga_mensual, 0) * 12;
    IF v_mes > 0 AND v_ganancia_neta_acum > 0 THEN
        v_prepaga_deducible := LEAST(
            v_prepaga_anual,
            (v_ganancia_neta_acum / v_mes * 12) * 0.05
        );
    ELSE
        v_prepaga_deducible := v_prepaga_anual;
    END IF;
    IF v_prepaga_deducible < 0 THEN v_prepaga_deducible := 0; END IF;

    v_ded_anuales :=
          v_mni.mni_mensual      * 13
        + v_mni.especial_mensual * 13
        + (CASE WHEN v_emp.conyuge_a_cargo THEN v_mni.conyuge_mensual * 13 ELSE 0 END)
        + (v_mni.hijo_mensual * 13 * COALESCE(v_emp.hijos_a_cargo, 0))
        + v_domestica_deducible
        + v_prepaga_deducible;

    v_ded_acum := v_ded_anuales * (v_mes::numeric / 12);

    v_excedente := v_ganancia_neta_acum - v_ded_acum;

    -- ─── Bruto extra disponible este mes sin gatillar retención ───
    IF v_excedente <= 0 THEN
        v_estado := 'ok';
        IF (1 - v_tasa_aportes) > 0 THEN
            v_disp := (v_ded_acum / (1 - v_tasa_aportes)) - v_bruto_acum;
        ELSE
            v_disp := v_ded_acum - v_ganancia_neta_acum;
        END IF;
    ELSIF v_excedente <= v_ded_acum * 0.05 THEN
        v_estado := 'al_borde';
        v_disp := 0;
    ELSE
        v_estado := 'excedido';
        v_disp := 0;
    END IF;

    IF v_disp < 0 THEN v_disp := 0; END IF;
    v_bruto_sug_mes := v_disp;

    RETURN jsonb_build_object(
        'empleado_id',                p_empleado_id,
        'periodo',                    p_periodo,
        'mes',                        v_mes,
        'anio',                       v_anio,
        'fuente_datos',               v_fuente,
        'bruto_acumulado_anual',      round(v_bruto_acum, 2),
        'aportes_acumulados_anual',   round(v_aportes_acum, 2),
        'tasa_aportes_efectiva',      round(v_tasa_aportes * 100, 2),
        'ganancia_neta_acumulada',    round(v_ganancia_neta_acum, 2),
        'deducciones_anuales',        round(v_ded_anuales, 2),
        'deducciones_acumuladas',     round(v_ded_acum, 2),
        'detalle_deducciones', jsonb_build_object(
            'mni_anual',              v_mni.mni_mensual * 13,
            'especial_anual',         v_mni.especial_mensual * 13,
            'conyuge_anual',          CASE WHEN v_emp.conyuge_a_cargo THEN v_mni.conyuge_mensual * 13 ELSE 0 END,
            'hijos_anual',            v_mni.hijo_mensual * 13 * COALESCE(v_emp.hijos_a_cargo, 0),
            'domestica_deducible',    round(v_domestica_deducible, 2),
            'prepaga_deducible',      round(v_prepaga_deducible, 2)
        ),
        'excedente',                  round(v_excedente, 2),
        'bruto_extra_disponible',     round(v_disp, 2),
        'bruto_sugerido_mes',         round(v_bruto_sug_mes, 2),
        'estado',                     v_estado,
        'notas_mni',                  v_mni.notas
    );
END $$;

-- ─── 3. Cargar histórico ene-abr 2026 en rrhh_pagos_blanco ─────────
-- Valores REALES extraídos de los PDFs del OneDrive (carpeta EMPLEADOS).

DELETE FROM public.rrhh_pagos_blanco
 WHERE periodo IN ('2026-01-01','2026-02-01','2026-03-01','2026-04-01')
   AND empleado_id IN (
        SELECT id FROM rrhh_empleados
         WHERE (apellido ILIKE '%ADORNO%' AND nombre ILIKE '%CLAUDIA%')
            OR (apellido ILIKE '%SIMONELLI%' AND nombre ILIKE '%JUAN%')
   );

INSERT INTO public.rrhh_pagos_blanco (empleado_id, periodo, neto_cct, cargado_por, notas)
SELECT id, periodo::date, neto, 'admin',
       'Histórico ene-abr 2026 cargado desde PDF original del estudio (carpeta OneDrive EMPLEADOS) — necesario para que la función rrhh_calcular_retencion_mensual acumule correctamente.'
FROM (VALUES
    -- Claudia (LRT, bruto = neto)
    ('ADORNO',    'CLAUDIA', '2026-01-01', 3572740.00),
    ('ADORNO',    'CLAUDIA', '2026-02-01', 3572740.00),
    ('ADORNO',    'CLAUDIA', '2026-03-01', 3572740.00),
    ('ADORNO',    'CLAUDIA', '2026-04-01', 3662360.00),
    -- JP (fuera convenio, tasa 16.35%)
    ('SIMONELLI', 'JUAN',    '2026-01-01', 2584263.00),
    ('SIMONELLI', 'JUAN',    '2026-02-01', 2584263.00),
    ('SIMONELLI', 'JUAN',    '2026-03-01', 2584263.00),
    ('SIMONELLI', 'JUAN',    '2026-04-01', 2657397.60)
) AS h(ap, nom, periodo, neto)
JOIN LATERAL (
    SELECT id FROM rrhh_empleados
     WHERE apellido ILIKE '%' || h.ap || '%'
       AND nombre   ILIKE '%' || h.nom || '%'
       AND estado = 'activo'
     LIMIT 1
) e ON true;

NOTIFY pgrst, 'reload schema';

-- ─── Verificación ─────────────────────────────────────────────────────

-- (a) Histórico cargado
SELECT e.nombre_completo, p.periodo, p.neto_cct
  FROM rrhh_pagos_blanco p
  JOIN rrhh_empleados e ON e.id = p.empleado_id
 WHERE e.calcular_tope_ganancias = true
 ORDER BY e.apellido, p.periodo;

-- (b) Cálculo retención mensual al cierre de mayo 2026
SELECT e.nombre_completo,
       public.rrhh_calcular_retencion_mensual(e.id, '2026-05-01'::date) AS calc
  FROM rrhh_empleados e
 WHERE e.calcular_tope_ganancias = true
 ORDER BY e.apellido;
