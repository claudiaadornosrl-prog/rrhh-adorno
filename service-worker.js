// ═══════════════════════════════════════════════════════════════════════
//  Service Worker — RRHH Claudia Adorno
//  Estrategia: network-first con cache fallback
//  (no agresivo — para que JP siempre vea la última versión cuando hay red)
// ═══════════════════════════════════════════════════════════════════════

const CACHE_VERSION = 'rrhh-v498-feriados-por-local';
const ASSETS = [
  './',
  './index.html',
  './styles.css',
  './recibos-pdf.js',
  './vacaciones-pdf.js',
  './manuales.js',
  './exportaciones.js',
  './salary-workflow.js',
  './liquidaciones.js',
  './fonts/URWGothic-Book.ttf',
  './fonts/Forum-Regular.ttf',
  './fonts/ArchitectsDaughter-Regular.ttf',
  './manifest.json',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

// Mensaje del cliente: forzar skipWaiting si hay un SW en waiting
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  // No interceptamos llamadas a Supabase (deben ir siempre directo a la red)
  if (url.hostname.includes('supabase.co')) return;
  // No interceptamos POST/PUT/DELETE
  if (event.request.method !== 'GET') return;

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Cachear copia para fallback offline
        if (response.ok && url.origin === self.location.origin) {
          const copy = response.clone();
          caches.open(CACHE_VERSION).then((c) => c.put(event.request, copy));
        }
        return response;
      })
      .catch(() => caches.match(event.request, { ignoreSearch: true }))
  );
});

// ═══════════════════════════════════════════════════════════════════════
//  Web Push Notifications
//  El payload llega encriptado y lo decodifica el browser automáticamente.
//  La Edge Function nos manda un JSON con: { title, body, url?, tag?, icon? }
// ═══════════════════════════════════════════════════════════════════════

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (e) {
    // Si no es JSON, intentamos como texto plano
    payload = { title: 'RRHH Adorno', body: event.data ? event.data.text() : 'Tenés una novedad' };
  }

  const title = payload.title || 'RRHH Adorno';
  const options = {
    body:    payload.body  || '',
    icon:    payload.icon  || './icon-192-v2.png',
    badge:   payload.badge || './icon-192-v2.png',
    tag:     payload.tag   || 'rrhh-default',     // notifs con mismo tag se reemplazan
    data:    { url: payload.url || './' },
    requireInteraction: false,
    vibrate: [200, 100, 200],
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  // (2-nov-2026) URL absoluta dentro del scope de ESTA app (antes './#tab' relativo y se matcheaba cualquier
  // ventana del mismo origen, p.ej. el hub o el CRM, que quedaba enfocada sin ir a ningún lado).
  const targetUrl = new URL((event.notification.data && event.notification.data.url) || './', self.registration.scope).href;
  const scope = self.registration.scope;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.startsWith(scope) && 'focus' in client) {
          client.focus();
          // La app escucha este mensaje y cambia de pestaña sin recargar (hashchange también).
          try { client.postMessage({ tipo: 'abrir-url', url: targetUrl }); } catch (_) {}
          if ('navigate' in client) client.navigate(targetUrl).catch(() => {});
          return;
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});
