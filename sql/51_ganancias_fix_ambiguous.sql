-- ═══════════════════════════════════════════════════════════════════════
--  51_ganancias_fix_ambiguous.sql
--  Fix bug: "column reference nombre_completo is ambiguous" en
--  rrhh_revisar_ganancias_mes. Las columnas del RETURNS TABLE chocaban
--  con las columnas de rrhh_empleados.
--
--  Solución: usar alias de tabla + variables locales distintas.
-- ═══════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.rrhh_revisar_ganancias_mes(date);

CREATE OR REPLACE FUNCTION public.rrhh_revisar_ganancias_mes(p_periodo date)
RETURNS TABLE (
    o_empleado_id        bigint,
    o_nombre_completo    text,
    o_estado             text,
    o_excedente          numeric,
    o_bruto_extra        numeric
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
        SELECT e.id AS eid, e.nombre_completo AS enombre
          FROM public.rrhh_empleados e
         WHERE e.calcular_tope_ganancias = true
           AND e.estado = 'activo'
    LOOP
        j := public.rrhh_calcular_retencion_mensual(r.eid, p_periodo);

        INSERT INTO public.rrhh_ganancias_revision (
            empleado_id, periodo,
            bruto_acumulado_anual, aportes_acumulados_anual,
            ganancia_neta_acumulada,
            deducciones_anuales, deducciones_acumuladas,
            excedente, bruto_extra_disponible, bruto_sugerido_mes,
            estado, detalle
        ) VALUES (
            r.eid, p_periodo,
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

        o_empleado_id     := r.eid;
        o_nombre_completo := r.enombre;
        o_estado          := j->>'estado';
        o_excedente       := (j->>'excedente')::numeric;
        o_bruto_extra     := (j->>'bruto_extra_disponible')::numeric;
        RETURN NEXT;
    END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_revisar_ganancias_mes(date) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ─── Test ─────────────────────────────────────────────────────────────
-- Forzar corrida manual para mayo 2026
SELECT * FROM public.rrhh_revisar_ganancias_mes('2026-05-01'::date);

-- Ver filas guardadas
SELECT r.fecha_corrida, r.empleado_id,
       e.nombre_completo AS empleada,
       r.estado, r.excedente, r.bruto_extra_disponible, r.bruto_sugerido_mes
  FROM public.rrhh_ganancias_revision r
  JOIN public.rrhh_empleados e ON e.id = r.empleado_id
 ORDER BY r.fecha_corrida DESC, r.empleado_id;
