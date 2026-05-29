// ═══════════════════════════════════════════════════════════════════════
//  enviar-push · Supabase Edge Function
//  ───────────────────────────────────────────────────────────────────────
//  Manda una push notification a todas las suscripciones activas de un
//  empleado (puede tener varias: celular + tablet + desktop).
//
//  POST /functions/v1/enviar-push
//  Body: {
//    empleado_id: bigint,
//    title:       string,
//    body:        string,
//    url?:        string,   // ruta a la que ir cuando clickea (ej '#mis-vacaciones')
//    tag?:        string,   // notifs con mismo tag se reemplazan
//  }
//
//  Secrets que necesita en Supabase Dashboard → Edge Functions → Secrets:
//    - VAPID_PUBLIC_KEY        (la misma del frontend)
//    - VAPID_PRIVATE_KEY       (formato raw base64url, 32 bytes)
//    - VAPID_SUBJECT           (ej "mailto:juanpsimonelli@gmail.com")
//    - SUPABASE_SERVICE_ROLE_KEY  (ya disponible automaticamente)
//    - SUPABASE_URL               (ya disponible automaticamente)
//
//  Si una suscripción devuelve 410/404 (gone) la marcamos `activa=false`.
// ═══════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "https://esm.sh/web-push@3.6.7";

interface PushPayload {
  empleado_id: number;
  title: string;
  body: string;
  url?: string;
  tag?: string;
  icon?: string;
}

const VAPID_PUBLIC_KEY  = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT     = Deno.env.get("VAPID_SUBJECT") || "mailto:juanpsimonelli@gmail.com";

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const supa = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin":  "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  let payload: PushPayload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }

  if (!payload.empleado_id || !payload.title) {
    return json({ error: "empleado_id y title son obligatorios" }, 400);
  }

  // Traer suscripciones activas
  const { data: subs, error } = await supa
    .from("rrhh_push_subscriptions")
    .select("id, endpoint, p256dh, auth")
    .eq("empleado_id", payload.empleado_id)
    .eq("activa", true);

  if (error)         return json({ error: error.message }, 500);
  if (!subs?.length) return json({ ok: true, sent: 0, msg: "sin suscripciones activas" });

  const notifPayload = JSON.stringify({
    title: payload.title,
    body:  payload.body,
    url:   payload.url  || "./",
    tag:   payload.tag  || "rrhh-default",
    icon:  payload.icon || "./icon-192.png",
  });

  const resultados = await Promise.allSettled(
    subs.map((s) =>
      webpush.sendNotification(
        {
          endpoint: s.endpoint,
          keys: { p256dh: s.p256dh, auth: s.auth },
        },
        notifPayload,
        { TTL: 60 * 60 * 24 }, // 24hs de TTL
      ).then(
        () => ({ id: s.id, ok: true }),
        (err) => ({ id: s.id, ok: false, status: err?.statusCode, err: err?.message || String(err) }),
      )
    ),
  );

  // Limpiar suscripciones muertas (404 o 410)
  const dead: number[] = [];
  let okCount = 0;
  for (const r of resultados) {
    if (r.status === "fulfilled") {
      const v = r.value as { id: number; ok: boolean; status?: number; err?: string };
      if (v.ok) okCount++;
      else if (v.status === 404 || v.status === 410) dead.push(v.id);
      else {
        // Log soft error
        await supa.from("rrhh_push_subscriptions")
          .update({ ultimo_error_at: new Date().toISOString(), ultimo_error: v.err })
          .eq("id", v.id);
      }
    }
  }

  if (dead.length) {
    await supa.from("rrhh_push_subscriptions")
      .update({ activa: false, ultimo_error_at: new Date().toISOString(), ultimo_error: "gone" })
      .in("id", dead);
  }

  // Marcar last_seen_at de las que sí enviaron
  const aliveIds = subs
    .filter((s) => !dead.includes(s.id))
    .map((s) => s.id);
  if (aliveIds.length) {
    await supa.from("rrhh_push_subscriptions")
      .update({ last_seen_at: new Date().toISOString() })
      .in("id", aliveIds);
  }

  return json({ ok: true, sent: okCount, total: subs.length, dead: dead.length });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
