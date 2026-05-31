-- ═══════════════════════════════════════════════════════════════════════
--  68_ipc_argentina_y_aumentos_push.sql
--
--  Tabla con el IPC mensual oficial INDEC + tabla de envíos de "rango de
--  aumento" a encargadas (registro de qué se mandó y cuándo).
--
--  El módulo Aumentos del admin va a mostrar el histórico para decidir
--  el % de aumento, y un wizard para mandar push a cada encargada con
--  los rangos en MONTOS redondeados (no en %) por cada vendedora.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. IPC mensual Argentina ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rrhh_ipc_argentina (
    mes              date PRIMARY KEY,             -- primer día del mes (yyyy-mm-01)
    variacion_pct    numeric(6,3) NOT NULL,        -- variación mensual % (ej. 2.7)
    fuente           text DEFAULT 'INDEC',          -- 'INDEC' / 'INDEC (estimado)' / 'manual'
    notas            text,
    cargado_at       timestamptz NOT NULL DEFAULT now(),
    cargado_por      text
);

CREATE INDEX IF NOT EXISTS idx_ipc_mes ON public.rrhh_ipc_argentina(mes DESC);

ALTER TABLE public.rrhh_ipc_argentina ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rrhh_ipc_select_all ON public.rrhh_ipc_argentina;
CREATE POLICY rrhh_ipc_select_all
    ON public.rrhh_ipc_argentina FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS rrhh_ipc_admin_all ON public.rrhh_ipc_argentina;
CREATE POLICY rrhh_ipc_admin_all
    ON public.rrhh_ipc_argentina FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- ─── 2. Seed con valores conocidos (INDEC oficiales + proyecciones) ──
-- Histórico INDEC + proyecciones de consultoras privadas (consenso REM-BCRA
-- y relevamientos Eco Go / LCG / Equilibra / OJF) para meses sin publicar.
-- JP puede actualizar desde la UI cuando salga cada dato oficial.
INSERT INTO public.rrhh_ipc_argentina (mes, variacion_pct, fuente, notas) VALUES
    ('2025-06-01', 1.6,  'INDEC', 'Histórico'),
    ('2025-07-01', 1.9,  'INDEC', 'Histórico'),
    ('2025-08-01', 1.9,  'INDEC', 'Histórico'),
    ('2025-09-01', 2.1,  'INDEC', 'Histórico'),
    ('2025-10-01', 2.7,  'INDEC', 'Histórico'),
    ('2025-11-01', 2.4,  'INDEC', 'Histórico'),
    ('2025-12-01', 2.7,  'INDEC', 'Histórico'),
    ('2026-01-01', 2.2,  'INDEC', 'Histórico'),
    ('2026-02-01', 2.4,  'INDEC', 'Histórico (mes del último aumento Adorno)'),
    ('2026-03-01', 3.7,  'INDEC', 'Histórico'),
    ('2026-04-01', 2.8,  'INDEC', 'Último dato oficial publicado'),
    ('2026-05-01', 2.5,  'Proyección consultoras', 'REM-BCRA / Eco Go / LCG promedio. Reemplazar cuando INDEC publique ~12/jun.'),
    ('2026-06-01', 2.2,  'Proyección consultoras', 'Estimado consenso. Reemplazar cuando INDEC publique ~14/jul.')
ON CONFLICT (mes) DO NOTHING;

-- Si el seed previo (v1) dejó may-26 en 0%, lo corrijo ahora:
UPDATE public.rrhh_ipc_argentina
   SET variacion_pct = 2.5,
       fuente = 'Proyección consultoras',
       notas = 'REM-BCRA / Eco Go / LCG promedio. Reemplazar cuando INDEC publique ~12/jun.'
 WHERE mes = '2026-05-01' AND variacion_pct = 0;

-- ─── 3. Función helper: IPC acumulado entre dos fechas ───────────────
CREATE OR REPLACE FUNCTION public.rrhh_ipc_acumulado(p_desde date, p_hasta date)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        ROUND( (EXP(SUM(LN(1 + variacion_pct/100.0))) - 1) * 100, 2),
        0
    )
    FROM rrhh_ipc_argentina
    WHERE mes >= p_desde AND mes <= p_hasta
      AND variacion_pct > 0;
$$;

GRANT EXECUTE ON FUNCTION public.rrhh_ipc_acumulado(date, date) TO authenticated;

-- ─── 4. Tabla de envíos de rango a encargadas ───────────────────────
-- Cada vez que JP dispara "enviar rangos a encargadas", se registra acá
-- para auditoría (qué % usó, qué rangos quedaron por vendedora, etc.)
CREATE TABLE IF NOT EXISTS public.rrhh_aumento_envio (
    id               bigserial PRIMARY KEY,
    enviado_at       timestamptz NOT NULL DEFAULT now(),
    enviado_por      text,
    periodo_aplica   date,                          -- mes en que se aplica (ej. 2026-06-01)
    pct_min          numeric(5,2),                  -- ej. 6.00
    pct_max          numeric(5,2),                  -- ej. 10.00
    notas            text,
    -- detalle JSON con la planilla enviada (lista de empleados con rango)
    detalle          jsonb
);

CREATE INDEX IF NOT EXISTS idx_aumento_envio_periodo
    ON public.rrhh_aumento_envio(periodo_aplica DESC, enviado_at DESC);

ALTER TABLE public.rrhh_aumento_envio ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rrhh_aum_envio_admin ON public.rrhh_aumento_envio;
CREATE POLICY rrhh_aum_envio_admin
    ON public.rrhh_aumento_envio FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

NOTIFY pgrst, 'reload schema';

-- ─── Verificación ────────────────────────────────────────────────────
SELECT mes, variacion_pct, fuente
FROM public.rrhh_ipc_argentina
ORDER BY mes DESC;

-- Test del helper: IPC acumulado feb 2026 → abr 2026
SELECT
    rrhh_ipc_acumulado('2026-02-01', '2026-04-01') AS acumulado_feb_abr,
    rrhh_ipc_acumulado('2026-03-01', '2026-04-01') AS acumulado_mar_abr;
