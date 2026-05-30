-- ═══════════════════════════════════════════════════════════════════════
--  48_ganancias_retencion_mensual.sql
--  Cálculo mensual del tope de retención de Ganancias 4ta categoría
--  (RG 4003/AFIP — agente de retención).
--
--  OBJETIVO: que la SRL como agente de retención NO retenga Ganancias
--  en el recibo. Lo que paguen Claudia/JP al final del año en su DDJJ es
--  problema del contador externamente.
--
--  Lógica del agente de retención mes a mes:
--    Ganancia neta acumulada (enero → mes M)
--      = Σ Brutos − Σ Aportes (jub + ley 19032 + OS + SEC + FAECYS)
--    Deducciones acumuladas hasta mes M
--      = (MNI + Especial + Cónyuge + Hijos + Doméstica + Prepaga) × (M / 12)
--    Si Ganancia neta acumulada > Deducciones acumuladas → se gatilla retención.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Tabla para historiar cada corrida del cron ──────────────────────
CREATE TABLE IF NOT EXISTS public.rrhh_ganancias_revision (
    id                          bigserial PRIMARY KEY,
    fecha_corrida               timestamptz NOT NULL DEFAULT now(),
    empleado_id                 bigint NOT NULL REFERENCES public.rrhh_empleados(id),
    periodo                     date NOT NULL,           -- mes revisado (yyyy-mm-01)
    bruto_acumulado_anual       numeric(14,2),
    aportes_acumulados_anual    numeric(14,2),
    ganancia_neta_acumulada     numeric(14,2),
    deducciones_anuales         numeric(14,2),
    deducciones_acumuladas      numeric(14,2),           -- proporcional al mes
    excedente                   numeric(14,2),           -- ganancia_neta − deducciones_acumuladas
    bruto_extra_disponible      numeric(14,2),           -- cuánto más se puede liquidar antes de gatillar retención
    bruto_sugerido_mes          numeric(14,2),           -- valor sugerido para el bruto del mes corriente
    estado                      text NOT NULL,           -- 'ok' | 'al_borde' | 'excedido'
    detalle                     jsonb,
    aplicado_at                 timestamptz,             -- cuándo JP aplicó la sugerencia (NULL si no)
    aplicado_por                text
);

CREATE INDEX IF NOT EXISTS rrhh_gan_rev_emp_periodo
    ON public.rrhh_ganancias_revision(empleado_id, periodo DESC, fecha_corrida DESC);

ALTER TABLE public.rrhh_ganancias_revision ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rrhh_gan_rev_admin ON public.rrhh_ganancias_revision;
CREATE POLICY rrhh_gan_rev_admin
    ON public.rrhh_ganancias_revision FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

DROP POLICY IF EXISTS rrhh_gan_rev_self ON public.rrhh_ganancias_revision;
CREATE POLICY rrhh_gan_rev_self
    ON public.rrhh_ganancias_revision FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

COMMENT ON TABLE public.rrhh_ganancias_revision IS
    'Historial de revisiones del tope Ganancias 4ta — corrida cron días 25 y último de cada mes.';

-- ─── Función principal: calcular retención mensual ────────────────────
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
BEGIN
    SELECT * INTO v_emp FROM rrhh_empleados WHERE id = p_empleado_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Empleado % no encontrado', p_empleado_id;
    END IF;

    v_mes  := EXTRACT(MONTH FROM p_periodo)::int;
    v_anio := EXTRACT(YEAR  FROM p_periodo)::int;

    -- ─── Acumular bruto + aportes del año hasta el mes (incluido) ───
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
    INTO v_bruto_acum, v_aportes_acum
    FROM rrhh_liquidacion
    WHERE empleado_id = p_empleado_id
      AND periodo >= make_date(v_anio, 1, 1)
      AND periodo <= p_periodo;

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
    v_domestica_anual    := COALESCE(v_emp.domestica_mensual, 0) * 13;
    v_domestica_deducible := LEAST(v_domestica_anual, v_mni.mni_mensual * 13);

    v_prepaga_anual := COALESCE(v_emp.prepaga_mensual, 0) * 12;  -- prepaga no tiene SAC
    -- Cap prepaga: 5% de la ganancia neta acumulada anualizada.
    -- (Si estamos en mes M, ganancia anualizada estimada = ganancia_neta_acum / M * 12)
    IF v_mes > 0 THEN
        v_prepaga_deducible := LEAST(
            v_prepaga_anual,
            (v_ganancia_neta_acum / v_mes * 12) * 0.05
        );
    ELSE
        v_prepaga_deducible := 0;
    END IF;
    IF v_prepaga_deducible < 0 THEN v_prepaga_deducible := 0; END IF;

    v_ded_anuales :=
          v_mni.mni_mensual      * 13
        + v_mni.especial_mensual * 13
        + (CASE WHEN v_emp.conyuge_a_cargo THEN v_mni.conyuge_mensual * 13 ELSE 0 END)
        + (v_mni.hijo_mensual * 13 * COALESCE(v_emp.hijos_a_cargo, 0))
        + v_domestica_deducible
        + v_prepaga_deducible;

    -- ─── Deducciones acumuladas hasta el mes M ───
    v_ded_acum := v_ded_anuales * (v_mes::numeric / 12);

    v_excedente := v_ganancia_neta_acum - v_ded_acum;

    -- ─── Tasa de aportes aplicable al empleado (para revertir bruto) ───
    -- Si bruto_acum > 0 → tasa real = aportes_acum / bruto_acum
    -- Si bruto_acum = 0 → tasa default 0 (caso Claudia LRT) o 17% (JP fuera convenio)
    IF v_bruto_acum > 0 THEN
        v_tasa_aportes := v_aportes_acum / v_bruto_acum;
    ELSE
        v_tasa_aportes := 0;
    END IF;

    -- ─── Bruto extra disponible este mes sin gatillar retención ───
    -- Queremos: (bruto_acum + bruto_extra) × (1 − tasa) ≤ ded_acum
    --   bruto_extra ≤ (ded_acum / (1 − tasa)) − bruto_acum
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

    -- ─── Bruto sugerido para ESTE mes ───
    -- Si estamos al borde o excedidos → 0 (no liquidar más este mes).
    -- Si OK → todo el bruto_extra_disponible, capeado al promedio razonable.
    v_bruto_sug_mes := v_disp;

    RETURN jsonb_build_object(
        'empleado_id',                p_empleado_id,
        'periodo',                    p_periodo,
        'mes',                        v_mes,
        'anio',                       v_anio,
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

GRANT EXECUTE ON FUNCTION public.rrhh_calcular_retencion_mensual(bigint, date) TO authenticated;

-- ─── Función wrapper que ejecuta y guarda en rrhh_ganancias_revision ──
CREATE OR REPLACE FUNCTION public.rrhh_revisar_ganancias_mes(p_periodo date)
RETURNS TABLE (
    empleado_id          bigint,
    nombre_completo      text,
    estado               text,
    excedente            numeric,
    bruto_extra          numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r record;
    j jsonb;
BEGIN
    FOR r IN
        SELECT id, nombre_completo
          FROM rrhh_empleados
         WHERE calcular_tope_ganancias = true
           AND estado = 'activo'
    LOOP
        j := rrhh_calcular_retencion_mensual(r.id, p_periodo);

        INSERT INTO rrhh_ganancias_revision (
            empleado_id, periodo,
            bruto_acumulado_anual, aportes_acumulados_anual,
            ganancia_neta_acumulada,
            deducciones_anuales, deducciones_acumuladas,
            excedente, bruto_extra_disponible, bruto_sugerido_mes,
            estado, detalle
        ) VALUES (
            r.id, p_periodo,
            (j->>'bruto_acumulado_anual')::numeric,
            (j->>'aportes_acumulados_anual')::numeric,
            (j->>'ganancia_neta_acumulada')::numeric,
            (j->>'deducciones_anuales')::numeric,
            (j->>'deducciones_acumuladas')::numeric,
            (j->>'excedente')::numeric,
            (j->>'bruto_extra_disponible')::numeric,
            (j->>'bruto_sugerido_mes')::numeric,
            j->>'estado',
            j
        );

        empleado_id := r.id;
        nombre_completo := r.nombre_completo;
        estado := j->>'estado';
        excedente := (j->>'excedente')::numeric;
        bruto_extra := (j->>'bruto_extra_disponible')::numeric;
        RETURN NEXT;
    END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_revisar_ganancias_mes(date) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ═══════════════════════════════════════════════════════════════════════
--  Verificación: simular corrida para mayo 2026 y junio 2026
-- ═══════════════════════════════════════════════════════════════════════

-- (a) Cálculo individual para Claudia y JP, mayo 2026
SELECT
    e.nombre_completo,
    rrhh_calcular_retencion_mensual(e.id, '2026-05-01') AS calc_mayo
FROM rrhh_empleados e
WHERE e.calcular_tope_ganancias = true;

-- (b) Corrida masiva (la que va a hacer el cron los días 25 y último)
--     ATENCIÓN: ejecuta el INSERT en rrhh_ganancias_revision (historiza).
--     Si solo querés VER sin guardar, comentá esta sección.
-- SELECT * FROM rrhh_revisar_ganancias_mes('2026-05-01');
