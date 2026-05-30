-- ═══════════════════════════════════════════════════════════════════════
--  52_email_outbox_normaganancias.sql
--  Sistema de notificación por email para cambios en norma ARCA Ganancias.
--
--  ARQUITECTURA:
--   1. Tabla rrhh_email_outbox: cola de emails pendientes de envío
--   2. Trigger en rrhh_ganancias_mni: encola email cuando se carga norma nueva
--   3. pg_cron 1 enero y 1 julio: recordatorio calendárico
--   4. pg_cron diario 1-15 enero/julio: invoca Edge Function de web search ARCA
--   5. Script Python local procesa outbox y envía vía Gmail OAuth
--      (claudiaadornosrl@gmail.com → JP + alegr@claudiaadorno.com)
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Cola de emails ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rrhh_email_outbox (
    id            bigserial PRIMARY KEY,
    created_at    timestamptz NOT NULL DEFAULT now(),
    to_addr       text NOT NULL,
    cc_addr       text,
    subject       text NOT NULL,
    body_html     text,
    body_text     text NOT NULL,
    categoria     text NOT NULL,                    -- 'norma_ganancias_cambio' | 'norma_ganancias_recordatorio' | etc.
    metadata      jsonb,
    status        text NOT NULL DEFAULT 'pendiente',-- 'pendiente' | 'enviado' | 'error'
    intentos      int NOT NULL DEFAULT 0,
    sent_at       timestamptz,
    error_msg     text
);

CREATE INDEX IF NOT EXISTS rrhh_email_outbox_pendientes
    ON public.rrhh_email_outbox(created_at) WHERE status = 'pendiente';

ALTER TABLE public.rrhh_email_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rrhh_email_outbox_admin ON public.rrhh_email_outbox;
CREATE POLICY rrhh_email_outbox_admin
    ON public.rrhh_email_outbox FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

COMMENT ON TABLE public.rrhh_email_outbox IS
    'Cola de emails pendientes para procesar por script Python local con Gmail OAuth.';

-- ─── 2. Trigger: encolar email cuando se carga nueva norma ARCA ──────
CREATE OR REPLACE FUNCTION public.rrhh_notificar_norma_ganancias_nueva()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_anterior rrhh_ganancias_mni%ROWTYPE;
    v_diff_mni numeric := 0;
    v_diff_esp numeric := 0;
    v_pct_mni numeric := 0;
    v_pct_esp numeric := 0;
    v_body text;
BEGIN
    -- Buscar fila inmediatamente anterior por fecha
    SELECT * INTO v_anterior
      FROM rrhh_ganancias_mni
     WHERE vigente_desde < NEW.vigente_desde
     ORDER BY vigente_desde DESC LIMIT 1;

    IF FOUND THEN
        v_diff_mni := NEW.mni_mensual - v_anterior.mni_mensual;
        v_diff_esp := NEW.especial_mensual - v_anterior.especial_mensual;
        v_pct_mni := CASE WHEN v_anterior.mni_mensual > 0
                          THEN round((v_diff_mni / v_anterior.mni_mensual) * 100, 2)
                          ELSE 0 END;
        v_pct_esp := CASE WHEN v_anterior.especial_mensual > 0
                          THEN round((v_diff_esp / v_anterior.especial_mensual) * 100, 2)
                          ELSE 0 END;
    END IF;

    v_body := format(
        E'Se cargaron nuevos valores ARCA Ganancias 4ta categoría en el sistema RRHH:\n\n'
     || E'Período vigente desde: %s\n\n'
     || E'Valores mensuales:\n'
     || E'  • Mínimo No Imponible: $%s%s\n'
     || E'  • Deducción especial:  $%s%s\n'
     || E'  • Cónyuge a cargo:     $%s\n'
     || E'  • Hijo a cargo:        $%s\n\n'
     || E'Notas: %s\n\n'
     || E'El sistema usará automáticamente estos valores para los cálculos del próximo mes y siguientes.\n'
     || E'Si hay que ajustar el bruto de Claudia / JP por este cambio, ver el banner Ganancias en el panel Liquidación.\n\n'
     || E'— Sistema RRHH Claudia Adorno',
        NEW.vigente_desde::text,
        trim(to_char(NEW.mni_mensual, 'FM999G999G999D00')),
        CASE WHEN v_anterior.id IS NOT NULL THEN format(' (antes $%s, %s%s%%)',
            trim(to_char(v_anterior.mni_mensual, 'FM999G999G999D00')),
            CASE WHEN v_pct_mni > 0 THEN '+' ELSE '' END, v_pct_mni) ELSE '' END,
        trim(to_char(NEW.especial_mensual, 'FM999G999G999D00')),
        CASE WHEN v_anterior.id IS NOT NULL THEN format(' (antes $%s, %s%s%%)',
            trim(to_char(v_anterior.especial_mensual, 'FM999G999G999D00')),
            CASE WHEN v_pct_esp > 0 THEN '+' ELSE '' END, v_pct_esp) ELSE '' END,
        trim(to_char(NEW.conyuge_mensual, 'FM999G999G999D00')),
        trim(to_char(NEW.hijo_mensual, 'FM999G999G999D00')),
        COALESCE(NEW.notas, '(sin notas)')
    );

    INSERT INTO rrhh_email_outbox (to_addr, cc_addr, subject, body_text, categoria, metadata)
    VALUES (
        'juanpsimonelli@gmail.com',
        'alegr@claudiaadorno.com',
        format('🔔 ARCA Ganancias 4ta — nuevos valores vigentes desde %s', NEW.vigente_desde::text),
        v_body,
        'norma_ganancias_cambio',
        jsonb_build_object(
            'mni_id', NEW.id,
            'vigente_desde', NEW.vigente_desde,
            'mni_mensual', NEW.mni_mensual,
            'especial_mensual', NEW.especial_mensual,
            'diff_mni_pct', v_pct_mni,
            'diff_esp_pct', v_pct_esp
        )
    );

    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_norma_ganancias_nueva ON public.rrhh_ganancias_mni;
CREATE TRIGGER trg_norma_ganancias_nueva
AFTER INSERT ON public.rrhh_ganancias_mni
FOR EACH ROW
EXECUTE FUNCTION public.rrhh_notificar_norma_ganancias_nueva();

-- ─── 3. Función: encolar recordatorio calendárico ────────────────────
CREATE OR REPLACE FUNCTION public.rrhh_encolar_recordatorio_norma_ganancias()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_hoy date := (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
    v_mes int := EXTRACT(MONTH FROM v_hoy)::int;
    v_dia int := EXTRACT(DAY FROM v_hoy)::int;
    v_periodo_esperado date;
    v_existe boolean;
    v_ultima_vigente date;
BEGIN
    -- Solo corre 1 enero y 1 julio
    IF NOT (v_dia = 1 AND v_mes IN (1, 7)) THEN
        RETURN format('Skip: hoy es %s, no es 1 ene ni 1 jul', v_hoy);
    END IF;

    -- Período esperado (H1 o H2 del año)
    v_periodo_esperado := make_date(EXTRACT(YEAR FROM v_hoy)::int, v_mes, 1);

    SELECT EXISTS (
        SELECT 1 FROM rrhh_ganancias_mni
         WHERE vigente_desde = v_periodo_esperado
    ) INTO v_existe;

    SELECT MAX(vigente_desde) INTO v_ultima_vigente FROM rrhh_ganancias_mni;

    IF v_existe THEN
        RETURN format('Skip: ya están cargados los valores ARCA para %s', v_periodo_esperado);
    END IF;

    INSERT INTO rrhh_email_outbox (to_addr, cc_addr, subject, body_text, categoria, metadata)
    VALUES (
        'juanpsimonelli@gmail.com',
        'alegr@claudiaadorno.com',
        format('⏰ Recordatorio: chequear publicación ARCA %s %s',
            CASE WHEN v_mes = 1 THEN 'H1' ELSE 'H2' END,
            EXTRACT(YEAR FROM v_hoy)::int),
        format(
            E'Recordatorio automático del sistema RRHH:\n\n'
         || E'Hoy es %s — fecha estimada de publicación de los nuevos valores ARCA para Ganancias 4ta categoría (%s).\n\n'
         || E'Última norma cargada en el sistema: %s\n\n'
         || E'Pasos:\n'
         || E'  1. Verificar en https://www.argentina.gob.ar/normativa si ARCA publicó la resolución del semestre.\n'
         || E'  2. Si está publicada, pasarle los valores al sistema RRHH (Claude / JP).\n'
         || E'  3. Una vez cargados, el sistema confirma automáticamente con un nuevo email.\n\n'
         || E'Mientras tanto, los cálculos del cron usarán los últimos valores cargados ($%s).\n\n'
         || E'— Sistema RRHH Claudia Adorno',
            v_hoy::text,
            CASE WHEN v_mes = 1 THEN 'enero-junio' ELSE 'julio-diciembre' END,
            COALESCE(v_ultima_vigente::text, 'ninguna'),
            (SELECT trim(to_char(mni_mensual, 'FM999G999G999D00'))
               FROM rrhh_ganancias_mni
              WHERE vigente_desde = v_ultima_vigente)
        ),
        'norma_ganancias_recordatorio',
        jsonb_build_object('fecha', v_hoy, 'mes', v_mes, 'ultima_vigente', v_ultima_vigente)
    );

    RETURN format('Recordatorio ARCA %s encolado para %s', v_mes, v_hoy);
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_encolar_recordatorio_norma_ganancias() TO authenticated;

-- ─── 4. Schedule pg_cron diario para recordatorio calendárico ─────────
SELECT cron.unschedule('rrhh_recordatorio_norma_ganancias')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rrhh_recordatorio_norma_ganancias');

SELECT cron.schedule(
    'rrhh_recordatorio_norma_ganancias',
    '0 12 * * *',  -- todos los días 09:00 ARG (12:00 UTC); la función filtra internamente 1 ene/1 jul
    $$SELECT public.rrhh_encolar_recordatorio_norma_ganancias();$$
);

NOTIFY pgrst, 'reload schema';

-- ─── Verificación ─────────────────────────────────────────────────────

-- (a) Tabla outbox creada
SELECT count(*) AS emails_pendientes FROM rrhh_email_outbox WHERE status = 'pendiente';

-- (b) Trigger registrado
SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE tgname = 'trg_norma_ganancias_nueva';

-- (c) Cron programado
SELECT jobname, schedule FROM cron.job
 WHERE jobname IN ('rrhh_revisar_ganancias', 'rrhh_recordatorio_norma_ganancias');

-- (d) Test del trigger: cargar la misma norma de H1 2026 de nuevo
--     (NO la voy a insertar — solo dejo el snippet para que JP lo pruebe si quiere)
-- INSERT INTO rrhh_ganancias_mni (vigente_desde, mni_mensual, especial_mensual, conyuge_mensual, hijo_mensual, notas)
-- VALUES ('2099-01-01', 9999999, 49999999, 8888888, 4444444, 'TEST trigger — borrar después')
-- ON CONFLICT (vigente_desde) DO NOTHING;
-- DELETE FROM rrhh_ganancias_mni WHERE vigente_desde = '2099-01-01';
