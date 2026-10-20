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
  const RESERVES = { 'photo-mystere': 1 };   // dossiers réservés, jamais affichés comme albums
  const visible = (nom)=> !nom.startsWith('_') && !nom.startsWith('.') && !RESERVES[nom];

  let manifeste = null, racine = null, cachesP = null;
  const lu = {};
  function chargerManifeste(){
    if(!manifeste) manifeste = fetch('data/galerie.json', { cache: 'no-cache' })
      .then(r=> r.ok ? r.json() : null).catch(()=> null);
    return manifeste;
  }
  // Dossiers d'albums programmés pas encore publiés (à masquer). Liste vide si la
  // fonctionnalité n'est pas installée ou si la base est injoignable.
  function listerCaches(){
    if(!cachesP){
      if(!URL_BASE || !CLE){ cachesP = Promise.resolve([]); }
      else cachesP = fetch(`${URL_BASE}/rest/v1/rpc/oc_albums_caches`, { method: 'POST', headers, body: '{}' })
        .then(r=> r.ok ? r.json() : []).then(a=> Array.isArray(a) ? a : []).catch(()=> []);
    }
    return cachesP;
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
      const [m, direct, caches] = await Promise.all([
        chargerManifeste(),
        lister('').then(l=> l.filter(estDossier).map(o=> o.name)).catch(()=> null),
        listerCaches()
      ]);
      const noms = direct || (m ? Object.keys(m.albums || {}) : null);
      if(!noms) throw new Error('galerie injoignable');
      const masques = new Set(caches);                       // albums programmés : cachés jusqu'à leur heure
      return noms.filter(visible).filter(n=> !masques.has(n)).sort().reverse();
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

  // Fiche de l'album (titre avec accents + crédit photographe), choisie à la
  // création de l'album (fichier _album.json), reprise par le robot dans le manifeste.
  const fiches = {};
  function fiche(album){
    if(!fiches[album]) fiches[album] = (async ()=>{
      const m = await chargerManifeste();
      const t = (m && m.titres && m.titres[album]) || null;
      const c = (m && m.credits && m.credits[album]) || null;
      if(m && m.albums && m.albums[album]) return { titre: t, credit: c };   // robot passé : fiche à jour
      if(t || c) return { titre: t, credit: c };
      try{                                                                    // album tout neuf : lire _album.json
        const r = await fetch(publicUrl(album + '/_album.json'), { cache: 'no-cache' });
        if(r.ok){ const j = await r.json(); return {
          titre: (j && typeof j.titre === 'string' && j.titre.trim()) ? j.titre.trim().slice(0, 100) : null,
          credit: (j && typeof j.credit === 'string' && j.credit.trim()) ? j.credit.trim().slice(0, 120) : null
        }; }
      }catch(e){}
      return { titre: null, credit: null };
    })();
    return fiches[album];
  }
  const titre = (album)=> fiche(album).then(f=> f.titre);
  const credit = (album)=> fiche(album).then(f=> f.credit);

  window.OCGalerie = { albums, photos, url, titre, credit, fiche, configure: !!(URL_BASE && CLE) };
})();
