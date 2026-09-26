// Sur3ati service worker — offline shell only. Never touches measurement traffic:
// it only handles same-origin GET requests, and always tries the network first for pages.
const CACHE = 'sur3ati-shell-v1';
const SHELL = ['/', '/manifest.webmanifest', '/fonts/qabas-light.woff2', '/fonts/qabas-regular.woff2', '/fonts/qabas-bold.woff2', '/icons/icon-192.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;           // leave speed-test traffic alone
  if (url.pathname.endsWith('.apk') || url.pathname.endsWith('.ipa') || url.pathname.endsWith('.json')) return;
  if (req.mode === 'navigate') {                                                   // network-first for the page
    e.respondWith(fetch(req).then(r => { const c = r.clone(); caches.open(CACHE).then(x => x.put('/', c)); return r; })
      .catch(() => caches.match('/')));
    return;
  }
  if (url.pathname.startsWith('/fonts/') || url.pathname.startsWith('/icons/')) {  // cache-first for static assets
    e.respondWith(caches.match(req).then(m => m || fetch(req).then(r => { const c = r.clone(); caches.open(CACHE).then(x => x.put(req, c)); return r; })));
  }
});
