/* ============================================================
   COMPTEUR DE VISITES — L'Objectif Châlonnais
   Mesure d'audience anonyme : aucun cookie, aucun identifiant.
   Chaque page vue ajoute 1 au compteur du jour (table « visites »
   dans Supabase). Les robots et les appareils de l'équipe ne sont
   pas comptés.
   Sur l'accueil, affiche le total dans l'élément #compteur.
   ============================================================ */
(function(){
  const cfg = window.OC_CONFIG || {};
  const URL_BASE = (cfg.supabaseUrl || '').replace(/\/+$/, '');
  const CLE = cfg.supabaseCle || '';
  if(!URL_BASE || !CLE) return;
  const entetes = { apikey: CLE, 'Content-Type': 'application/json' };
  if(CLE.startsWith('eyJ')) entetes.Authorization = 'Bearer ' + CLE;
  const rpc = (nom, corps)=> fetch(`${URL_BASE}/rest/v1/rpc/${nom}`, { method:'POST', headers: entetes, body: JSON.stringify(corps || {}), keepalive: true });

  // ---------- Compter cette page ----------
  function aCompter(){
    if(location.protocol !== 'https:') return false;                 // pas en test sur l'ordinateur
    if(navigator.webdriver) return false;                             // navigateurs automatisés
    if(/bot|crawl|spider|slurp|facebookexternalhit|whatsapp|preview|lighthouse/i.test(navigator.userAgent || '')) return false;
    try{ if(localStorage.getItem('oc-ne-pas-compter')) return false; }catch(e){}   // appareils de l'équipe
    return true;
  }
  let page = (location.pathname.split('/').pop() || 'index.html').replace(/\.html$/, '');
  if(page === 'index' || page === '') page = 'accueil';
  if(aCompter()){
    let nouvelle = true;
    try{
      nouvelle = !sessionStorage.getItem('oc-visite');
      sessionStorage.setItem('oc-visite', '1');
    }catch(e){}
    rpc('oc_visite', { p_page: page, p_nouvelle: nouvelle }).catch(()=>{});
  }

  // ---------- Affichage du total (accueil) ----------
  const el = document.getElementById('compteur');
  if(!el || cfg.compteurPublic === false) return;
  const SEUIL = typeof cfg.compteurMinimum === 'number' ? cfg.compteurMinimum : 1000;
  rpc('oc_compteur').then(r=> r.ok ? r.json() : null).then(c=>{
    if(!c || !(c.visites >= SEUIL)) return;
    const nb = el.querySelector('[data-nb]');
    const cible = c.visites;
    const fmt = (n)=> n.toLocaleString('fr-FR');
    if(c.depuis){
      const d = new Date(c.depuis + 'T12:00:00');
      const depuis = el.querySelector('[data-depuis]');
      if(depuis) depuis.textContent = d.toLocaleDateString('fr-FR', { day:'numeric', month:'long', year:'numeric' });
    }
    el.hidden = false;
    // petit défilement des chiffres quand le compteur apparaît à l'écran
    if(matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)){
      nb.textContent = fmt(cible); return;
    }
    nb.textContent = fmt(0);
    const io = new IntersectionObserver((entrees)=>{
      if(!entrees.some(e=> e.isIntersecting)) return;
      io.disconnect();
      const t0 = performance.now(), duree = 1400;
      (function pas(t){
        const k = Math.min(1, (t - t0) / duree);
        nb.textContent = fmt(Math.round(cible * (1 - Math.pow(1 - k, 3))));
        if(k < 1) requestAnimationFrame(pas);
      })(t0);
    });
    io.observe(el);
  }).catch(()=>{});
})();
