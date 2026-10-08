/* Service worker — L'Objectif Châlonnais
   - Pages et fichiers du site : toujours la version la plus récente quand on
     est en ligne, la dernière version enregistrée quand on est hors ligne.
   - Polices et bibliothèque de carte : gardées en mémoire.
   - Base de données, photos et fonds de carte : jamais mis en cache ici. */
const VERSION = 'oc-v1';
const SHELL = [
  './', './index.html', './bons-plans.html', './galerie.html', './quiz.html', './offline.html',
  './site.css', './config.js', './storage.js', './app.js', './logo.png',
  './icons/icon-192.png', './manifest.webmanifest'
];
const STATIC_HOSTS = ['fonts.googleapis.com', 'fonts.gstatic.com', 'unpkg.com'];

self.addEventListener('install', (event)=>{
  event.waitUntil(
    caches.open(VERSION).then(cache => Promise.allSettled(SHELL.map(u => cache.add(u))))
      .then(()=> self.skipWaiting())
  );
});

self.addEventListener('activate', (event)=>{
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
      .then(()=> self.clients.claim())
  );
});

self.addEventListener('fetch', (event)=>{
  const req = event.request;
  if(req.method !== 'GET') return;
  const url = new URL(req.url);

  // Fichiers du site : réseau d'abord (sans cache navigateur), sinon copie locale
  if(url.origin === self.location.origin){
    event.respondWith((async ()=>{
      const cache = await caches.open(VERSION);
      try{
        const fresh = await fetch(req.url, { cache: 'no-cache', credentials: 'same-origin' });
        if(fresh.ok && !url.search) cache.put(req.url, fresh.clone());
        return fresh;
      }catch(e){
        const hit = await cache.match(req.url, { ignoreSearch: true });
        if(hit) return hit;
        if(req.mode === 'navigate') return cache.match('./offline.html');
        return Response.error();
      }
    })());
    return;
  }

  // Polices et Leaflet : copie locale d'abord
  if(STATIC_HOSTS.includes(url.hostname)){
    event.respondWith((async ()=>{
      const cache = await caches.open(VERSION);
      const hit = await cache.match(req);
      if(hit) return hit;
      const res = await fetch(req);
      if(res.ok || res.type === 'opaque') cache.put(req, res.clone());
      return res;
    })());
  }
  // Tout le reste (Supabase, OpenStreetMap…) passe directement par le réseau
});
