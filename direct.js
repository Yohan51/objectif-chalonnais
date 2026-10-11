/* ============================================================
   LES DIRECTS — état partagé par toutes les pages publiques
   - point rouge sur le lien « Direct » du menu pendant un direct ;
   - bandeau « EN DIRECT » et annonce du prochain direct sur l'accueil.
   L'état est lu dans Supabase (table direct, lecture publique),
   au plus une fois par minute.
   ============================================================ */
(function(){
  const cfg = window.OC_CONFIG || {};
  const base = (cfg.supabaseUrl || '').replace(/\/+$/, ''), cle = cfg.supabaseCle || '';
  const CHAINE = cfg.youtubeChaineId || 'UC3ehDb-pE4B8E-xOiPD76XQ';
  const DUREE_MAX = 8 * 3600e3;     // un direct oublié « en cours » s'éteint tout seul après 8 h
  const CLE_CACHE = 'oc-direct';

  const esc = (s)=> String(s == null ? '' : s).replace(/[&<>"']/g, c=> ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' })[c]);
  function dateFr(iso){
    const d = new Date(iso), auj = new Date(), dem = new Date(); dem.setDate(auj.getDate() + 1);
    const h = d.toLocaleTimeString('fr-FR', { hour:'2-digit', minute:'2-digit' }).replace(':', 'h').replace(/h00$/, 'h');
    if(d.toDateString() === auj.toDateString()) return `aujourd'hui à ${h}`;
    if(d.toDateString() === dem.toDateString()) return `demain à ${h}`;
    return d.toLocaleDateString('fr-FR', { weekday:'long', day:'numeric', month:'long' }) + ' à ' + h;
  }
  function normaliser(v){
    v = v || {};
    const maint = Date.now();
    return {
      live: !!v.en_direct && !!v.debut && maint - new Date(v.debut) < DUREE_MAX,
      titre: v.titre || '',
      video: v.video_id || '',
      fb: v.lien_fb || '',
      debut: v.debut || null,
      prochain: v.prochain_le && new Date(v.prochain_le) > maint - 2 * 3600e3
        ? { le: v.prochain_le, titre: v.prochain_titre || '' } : null
    };
  }
  async function etat(force){
    if(!force){
      try{
        const c = JSON.parse(sessionStorage.getItem(CLE_CACHE) || 'null');
        if(c && Date.now() - c.t < 60000) return normaliser(c.v);
      }catch(e){}
    }
    if(!base || !cle) return normaliser(null);
    const h = { apikey: cle }; if(cle.startsWith('eyJ')) h.Authorization = 'Bearer ' + cle;
    try{
      const r = await fetch(`${base}/rest/v1/direct?id=eq.1&select=*`, { headers: h, cache: 'no-store' });
      if(!r.ok) return normaliser(null);           // directs pas encore installés
      const v = (await r.json())[0] || null;
      try{ sessionStorage.setItem(CLE_CACHE, JSON.stringify({ t: Date.now(), v })); }catch(e){}
      return normaliser(v);
    }catch(e){ return normaliser(null); }
  }

  function afficher(e){
    document.querySelectorAll('.oc-nav-links a[href="direct.html"]').forEach(a=> a.classList.toggle('oc-live', e.live));
    const b = document.getElementById('oc-bandeau-direct');
    if(b){
      b.hidden = !e.live;
      if(e.live) b.innerHTML = `<span class="oc-live-pastille">En direct</span>
        <span class="oc-live-titre">${esc(e.titre || 'L\'Objectif Châlonnais est en direct')}</span>
        <span class="oc-live-voir">Regarder →</span>`;
    }
    const p = document.getElementById('oc-prochain-direct');
    if(p){
      p.hidden = e.live || !e.prochain;
      if(!p.hidden) p.innerHTML = `<span class="oc-prochain-ico" aria-hidden="true">📅</span>
        <span><strong>Prochain direct : ${esc(dateFr(e.prochain.le))}</strong>${e.prochain.titre ? ' · ' + esc(e.prochain.titre) : ''}</span>
        <span class="oc-live-voir">En savoir plus →</span>`;
    }
    document.dispatchEvent(new CustomEvent('oc-direct', { detail: e }));
  }
  async function rafraichir(force){ afficher(await etat(force)); }

  window.OCDirect = { etat, CHAINE, dateFr, rafraichir };
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ()=> rafraichir());
  else rafraichir();
  setInterval(()=>{ if(!document.hidden) rafraichir(true); }, 60000);
  document.addEventListener('visibilitychange', ()=>{ if(!document.hidden) rafraichir(); });
})();
