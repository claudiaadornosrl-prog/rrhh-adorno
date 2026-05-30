-- ═══════════════════════════════════════════════════════════════════════
--  50_ganancias_cron.sql
--  Cron Supabase pg_cron: revisar Ganancias días 25 y último de cada mes.
--
--  IMPORTANTE: requiere que pg_cron esté habilitado en el proyecto.
--    Dashboard → Database → Extensions → buscar 'pg_cron' → Enable
--  Si no está habilitado, ejecutar PRIMERO:
--    CREATE EXTENSION IF NOT EXISTS pg_cron;
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Job wrapper que decide si corresponde correr hoy ──────────────
-- Solo corre el día 25 o el último día del mes.
CREATE OR REPLACE FUNCTION public.rrhh_cron_revisar_ganancias()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_hoy date := (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
    v_dia int := EXTRACT(DAY FROM v_hoy)::int;
    v_ultimo_dia int := EXTRACT(DAY FROM (date_trunc('month', v_hoy) + interval '1 month' - interval '1 day'))::int;
    v_es_dia_25 boolean := v_dia = 25;
    v_es_ultimo boolean := v_dia = v_ultimo_dia;
    v_periodo date := date_trunc('month', v_hoy)::date;
    v_count int;
BEGIN
    IF NOT (v_es_dia_25 OR v_es_ultimo) THEN
        RETURN format('Skip: hoy es día %s, ni 25 ni último', v_dia);
    END IF;

    -- Correr la revisión y contar empleadas revisadas
    SELECT count(*) INTO v_count
      FROM rrhh_revisar_ganancias_mes(v_periodo);

    RETURN format(
        'Revisión Ganancias ejecutada %s (día %s) para período %s — %s empleadas revisadas',
        v_hoy::text, v_dia, v_periodo::text, v_count
    );
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_cron_revisar_ganancias() TO authenticated;

-- ─── 2. Schedule en pg_cron ───────────────────────────────────────────
-- Corre todos los días a las 09:00 (UTC = 06:00 ARG; ajustar si se quiere).
-- El wrapper internamente decide si ejecuta o no.

-- Primero desprogramar si existe (idempotente)
SELECT cron.unschedule('rrhh_revisar_ganancias')
 WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'rrhh_revisar_ganancias'
 );

-- Programar: todos los días a las 09:00 (UTC) — 06:00 hora ARG.
-- pg_cron usa formato POSIX cron: minuto hora día mes día_semana
SELECT cron.schedule(
    'rrhh_revisar_ganancias',
    '0 9 * * *',
    $$SELECT public.rrhh_cron_revisar_ganancias();$$
);

-- ─── 3. Tabla de log para auditar las corridas del cron ───────────────
CREATE TABLE IF NOT EXISTS public.rrhh_ganancias_cron_log (
    id          bigserial PRIMARY KEY,
    corrida_at  timestamptz NOT NULL DEFAULT now(),
    resultado   text NOT NULL,
    metadata    jsonb
);

ALTER TABLE public.rrhh_ganancias_cron_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rrhh_gan_cron_log_admin ON public.rrhh_ganancias_cron_log;
CREATE POLICY rrhh_gan_cron_log_admin
    ON public.rrhh_ganancias_cron_log FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- ─── 4. Wrapper con logging ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rrhh_cron_revisar_ganancias_logged()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_resultado text;
BEGIN
    BEGIN
        v_resultado := public.rrhh_cron_revisar_ganancias();
    EXCEPTION WHEN OTHERS THEN
        v_resultado := 'ERROR: ' || SQLERRM;
    END;
    INSERT INTO rrhh_ganancias_cron_log (resultado) VALUES (v_resultado);
    RETURN v_resultado;
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_cron_revisar_ganancias_logged() TO authenticated;

-- Re-programar el schedule para que use la versión con logging
SELECT cron.unschedule('rrhh_revisar_ganancias')
 WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'rrhh_revisar_ganancias'
 );

SELECT cron.schedule(
    'rrhh_revisar_ganancias',
    '0 9 * * *',
    $$SELECT public.rrhh_cron_revisar_ganancias_logged();$$
);

NOTIFY pgrst, 'reload schema';

-- ─── Verificación ─────────────────────────────────────────────────────
-- (a) Job programado
SELECT jobid, jobname, schedule, command FROM cron.job WHERE jobname = 'rrhh_revisar_ganancias';

-- (b) Test manual del wrapper (corre solo si hoy es 25 o último)
SELECT public.rrhh_cron_revisar_ganancias() AS test_manual;
