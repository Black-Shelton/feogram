// FeoGram Service Worker v1
const CACHE = 'feogram-v1';
const STATIC = ['/'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(STATIC)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  // Network first for API / supabase, cache first for static
  const url = new URL(e.request.url);
  if (url.hostname.includes('supabase') || url.pathname.startsWith('/rest/') || url.pathname.startsWith('/auth/')) {
    return; // Let Supabase requests pass through uncached
  }
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  );
});
