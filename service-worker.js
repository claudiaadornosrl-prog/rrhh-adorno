// ═══════════════════════════════════════════════════════════════════════
//  Service Worker — RRHH Claudia Adorno
//  Estrategia: network-first con cache fallback
//  (no agresivo — para que JP siempre vea la última versión cuando hay red)
// ═══════════════════════════════════════════════════════════════════════

const CACHE_VERSION = 'rrhh-v1';
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
