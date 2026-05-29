-- ═══════════════════════════════════════════════════════════════════════
--  36_push_subscriptions.sql
--  Web Push Notifications — Fase A
--
--  Guarda las suscripciones de cada empleada (un mismo empleado puede tener
--  varias: una en su celular, otra en su tablet, etc.).
--
--  El endpoint es único por device+navegador (lo asigna FCM/APNS).
--  Si la empleada desinstala la PWA o limpia datos del browser, su próxima
--  re-suscripción tendrá un endpoint nuevo — la vieja queda obsoleta y la
--  Edge Function la borra cuando recibe 410 Gone al enviar.
--
--  Después de correr: NOTIFY pgrst, 'reload schema';
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.rrhh_push_subscriptions (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES public.rrhh_empleados(id) ON DELETE CASCADE,
    endpoint        text   NOT NULL,
    p256dh          text   NOT NULL,
    auth            text   NOT NULL,
    user_agent      text,
    plataforma      text,           -- 'android', 'ios', 'desktop', 'otro' (inferido en el cliente)
    activa          boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    last_seen_at    timestamptz NOT NULL DEFAULT now(),
    ultimo_error_at timestamptz,
    ultimo_error    text,
    UNIQUE (endpoint)
);

CREATE INDEX IF NOT EXISTS idx_push_subs_empleado
    ON public.rrhh_push_subscriptions(empleado_id)
    WHERE activa = true;

COMMENT ON TABLE public.rrhh_push_subscriptions IS
    'Suscripciones Web Push de empleadas. Una empleada puede tener N (uno por device).';
COMMENT ON COLUMN public.rrhh_push_subscriptions.endpoint IS
    'URL del push service (FCM para Chrome/Android, APNS para Safari/iOS). Único.';
COMMENT ON COLUMN public.rrhh_push_subscriptions.p256dh IS
    'Clave pública del cliente para encriptar el payload (base64url).';
COMMENT ON COLUMN public.rrhh_push_subscriptions.auth IS
    'Auth secret del cliente (base64url).';

-- ─── RLS ────────────────────────────────────────────────────────────────
ALTER TABLE public.rrhh_push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Empleada: solo ve y gestiona sus propias subs
CREATE POLICY rrhh_push_self_select
    ON public.rrhh_push_subscriptions
    FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

CREATE POLICY rrhh_push_self_insert
    ON public.rrhh_push_subscriptions
    FOR INSERT
    WITH CHECK (empleado_id = rrhh_mi_empleado_id());

CREATE POLICY rrhh_push_self_update
    ON public.rrhh_push_subscriptions
    FOR UPDATE
    USING (empleado_id = rrhh_mi_empleado_id());

CREATE POLICY rrhh_push_self_delete
    ON public.rrhh_push_subscriptions
    FOR DELETE
    USING (empleado_id = rrhh_mi_empleado_id());

-- Admin: ve y gestiona todas (para debug + para que la Edge Function pueda
--        leer con service role, aunque service role bypasea RLS de todas formas).
CREATE POLICY rrhh_push_admin_all
    ON public.rrhh_push_subscriptions
    FOR ALL
    USING (rrhh_is_admin());

-- Refrescar cache de PostgREST
NOTIFY pgrst, 'reload schema';
