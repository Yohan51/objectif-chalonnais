/* ============================================================
   Données de la galerie — L'Objectif Châlonnais
   Partagé par la galerie et l'accueil.
   - Liste des albums et des photos : fichier data/galerie.json fabriqué
     par le robot GitHub (une seule requête), complété par Supabase pour
     les albums tout juste ajoutés.
   - Images : versions légères (WebP) quand le robot les a fabriquées,
     sinon la photo originale.
   ============================================================ */
(function(){
  const cfg = window.OC_CONFIG || {};
  const URL_BASE = (cfg.supabaseUrl || '').replace(/\/+$/, '');
  const CLE = cfg.supabaseCle || '';
  const BUCKET = cfg.galerieBucket || 'galerie';
  const IMG = /\.(jpe?g|png|webp|gif|avif)$/i;
  const headers = { apikey: CLE, 'Content-Type': 'application/json' };
  if(CLE.startsWith('eyJ')) headers.Authorization = 'Bearer ' + CLE;

  const enc = (p)=> p.split('/').map(encodeURIComponent).join('/');
  const publicUrl = (p)=> `${URL_BASE}/storage/v1/object/public/${BUCKET}/${enc(p)}`;
  const estDossier = (o)=> o.id === null || (!o.metadata && !IMG.test(o.name));
  const visible = (nom)=> !nom.startsWith('_') && !nom.startsWith('.');

  let manifeste = null, racine = null;
  const lu = {};
  function chargerManifeste(){
    if(!manifeste) manifeste = fetch('data/galerie.json', { cache: 'no-cache' })
      .then(r=> r.ok ? r.json() : null).catch(()=> null);
    return manifeste;
  }
  async function lister(prefix){
    const out = [];
    for(let offset = 0; ; offset += 1000){
      const r = await fetch(`${URL_BASE}/storage/v1/object/list/${BUCKET}`, {
        method: 'POST', headers, body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } })
      });
      if(!r.ok) throw new Error('liste ' + r.status);
      const lignes = await r.json();
      out.push(...lignes);
      if(lignes.length < 1000) break;
    }
    return out;
  }

  // Noms des albums, du plus récent au plus ancien
  async function albums(){
    if(!URL_BASE || !CLE) return [];
    if(!racine) racine = (async ()=>{
      const [m, direct] = await Promise.all([
        chargerManifeste(),
        lister('').then(l=> l.filter(estDossier).map(o=> o.name)).catch(()=> null)
      ]);
      const noms = direct || (m ? Object.keys(m.albums || {}) : null);
      if(!noms) throw new Error('galerie injoignable');
      return noms.filter(visible).sort().reverse();
    })();
    return racine;
  }
  // Photos d'un album : [{ n: nom, v: 1 si versions légères, w, h }]
  async function photos(album){
    if(!lu[album]) lu[album] = (async ()=>{
      const m = await chargerManifeste();
      if(m && m.albums && m.albums[album]) return m.albums[album];
      const l = await lister(album + '/');
      return l.filter(o=> !estDossier(o) && IMG.test(o.name) && visible(o.name)).map(o=> ({ n: o.name }));
    })();
    return lu[album];
  }
  // taille : 'm' (grilles), 'g' (grand écran), 'o' (original)
  function url(album, p, taille){
    if(p.v && taille !== 'o'){
      return publicUrl(`_vignettes/${album}/${p.n.replace(/\.[^.]+$/, '')}.${taille === 'g' ? 'g' : 'm'}.webp`);
    }
    return publicUrl(album + '/' + p.n);
  }

  // Titre avec accents choisi à la création de l'album (fichier _album.json), sinon null
  const titres = {};
  function titre(album){
    if(!titres[album]) titres[album] = (async ()=>{
      const m = await chargerManifeste();
      if(m && m.titres && m.titres[album]) return m.titres[album];
      if(m && m.albums && m.albums[album]) return null;        // album connu du robot, sans titre particulier
      try{
        const r = await fetch(publicUrl(album + '/_album.json'), { cache: 'no-cache' });
        if(r.ok){ const j = await r.json(); return (j && typeof j.titre === 'string' && j.titre.trim()) ? j.titre.trim().slice(0, 100) : null; }
      }catch(e){}
      return null;
    })();
    return titres[album];
  }

  window.OCGalerie = { albums, photos, url, titre, configure: !!(URL_BASE && CLE) };
})();
