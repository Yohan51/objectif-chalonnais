/* Service worker — L'Objectif Châlonnais
   - Pages et fichiers du site : toujours la version la plus récente quand on
     est en ligne, la dernière version enregistrée quand on est hors ligne.
   - Polices et bibliothèque de carte : gardées en mémoire.
   - Base de données, photos et fonds de carte : jamais mis en cache ici. */
const VERSION = 'oc-v9';
const SHELL = [
  './', './index.html', './actus.html', './bons-plans.html', './galerie.html', './quiz.html', './jeux.html', './offline.html',
  './site.css', './config.js', './storage.js', './app.js', './push.js', './actus-rendu.js', './logo.png',
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

// ---------- Alertes (notifications) ----------
self.addEventListener('push', (event)=>{
  let data = {};
  try{ data = event.data ? event.data.json() : {}; }catch(e){ data = { titre: event.data && event.data.text() }; }
  const titre = data.titre || "L'Objectif Châlonnais";
  event.waitUntil(self.registration.showNotification(titre, {
    body: data.message || '',
    icon: 'icons/icon-192.png',
    badge: 'icons/icon-192.png',
    lang: 'fr',
    data: { lien: data.lien || './' }
  }));
});

self.addEventListener('notificationclick', (event)=>{
  event.notification.close();
  const cible = new URL((event.notification.data && event.notification.data.lien) || './', self.registration.scope).href;
  const externe = new URL(cible).origin !== new URL(self.registration.scope).origin;
  event.waitUntil((async ()=>{
    // Lien vers TikTok, Instagram, YouTube… : ouvert directement (dans leur appli si elle est installée)
    if(externe) return self.clients.openWindow(cible);
    const fenetres = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for(const f of fenetres){
      if(f.url.startsWith(self.registration.scope) && 'focus' in f){
        await f.focus();
        if('navigate' in f) return f.navigate(cible);
        return;
      }
    }
    return self.clients.openWindow(cible);
  })());
});
