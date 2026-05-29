// ═══════════════════════════════════════════════════════════════════════
//  Service Worker — RRHH Claudia Adorno
//  Estrategia: network-first con cache fallback
//  (no agresivo — para que JP siempre vea la última versión cuando hay red)
// ═══════════════════════════════════════════════════════════════════════

const CACHE_VERSION = 'rrhh-v28-planilla-sac-adelantos';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => cache.addAll(ASSETS))
  );
  self.skipWaiting();
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
      .catch(() => caches.match(event.request))
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
    icon:    payload.icon  || './icon-192.png',
    badge:   payload.badge || './icon-192.png',
    tag:     payload.tag   || 'rrhh-default',     // notifs con mismo tag se reemplazan
    data:    { url: payload.url || './' },
    requireInteraction: false,
    vibrate: [200, 100, 200],
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || './';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // Si ya hay una ventana del RRHH abierta, le mandamos foco y navegamos
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.focus();
          if ('navigate' in client) client.navigate(targetUrl).catch(() => {});
          return;
        }
      }
      // Si no hay ninguna ventana, abrimos una nueva
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});
