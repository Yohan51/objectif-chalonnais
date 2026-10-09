/* ============================================================
   ACTUS — outils communs (page Actus, accueil, rédaction)
   ============================================================ */
(function(){
  const cfg = window.OC_CONFIG || {};
  const URL_BASE = (cfg.supabaseUrl || '').replace(/\/+$/, '');
  const CLE = cfg.supabaseCle || '';
  const entetes = { 'apikey': CLE, 'Content-Type': 'application/json' };
  if(CLE.startsWith('eyJ')) entetes['Authorization'] = 'Bearer ' + CLE;

  const RUBRIQUES = {
    actu:      'Actualité locale',
    sport:     'Sport',
    culture:   'Culture',
    evenement: 'Événements',
    asso:      'Vie de l\'asso'
  };

  function esc(s){
    return String(s == null ? '' : s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }

  // Gras **texte** et liens https://… (le texte est déjà échappé)
  function enLigne(t){
    return t
      .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
      .replace(/(https?:\/\/[^\s<]+[^\s<.,;:!?)])/g, '<a href="$1" target="_blank" rel="noopener">$1</a>');
  }

  // Texte de l'article → HTML sûr.
  // Paragraphes séparés par une ligne vide, « ## » = intertitre, « - » = liste.
  function rendreContenu(texte){
    const blocs = esc(texte || '').replace(/\r\n?/g, '\n').split(/\n\s*\n/);
    return blocs.map(b => b.trim()).filter(Boolean).map(b => {
      if(/^##\s+/.test(b)) return `<h2>${enLigne(b.replace(/^##\s+/, '').replace(/\n/g,' '))}</h2>`;
      const lignes = b.split('\n');
      if(lignes.every(l => /^\s*[-•]\s+/.test(l))){
        return '<ul>' + lignes.map(l => `<li>${enLigne(l.replace(/^\s*[-•]\s+/, ''))}</li>`).join('') + '</ul>';
      }
      return `<p>${lignes.map(enLigne).join('<br>')}</p>`;
    }).join('\n');
  }

  const MOIS = ['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'];
  function dateLongue(iso){
    if(!iso) return '';
    const d = new Date(iso);
    if(isNaN(d)) return '';
    return `${d.getDate()} ${MOIS[d.getMonth()]} ${d.getFullYear()}`;
  }

  function youtubeId(url){
    if(!url) return null;
    const m = String(url).match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|live\/|embed\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/);
    return m ? m[1] : null;
  }

  function libelleLien(url, libelle){
    if(libelle) return libelle;
    if(/youtu/.test(url)) return 'Voir la vidéo sur YouTube';
    if(/tiktok\.com/.test(url)) return 'Voir la vidéo sur TikTok';
    if(/instagram\.com/.test(url)) return 'Voir sur Instagram';
    return 'En savoir plus';
  }

  // Transforme un titre en adresse : « Foire de Châlons ! » → foire-de-chalons
  function slugifier(t){
    return String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '')
      .toLowerCase().replace(/œ/g,'oe').replace(/æ/g,'ae')
      .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80).replace(/-+$/,'') || 'actu';
  }

  async function lire(chemin){
    const r = await fetch(`${URL_BASE}/rest/v1/${chemin}`, { headers: entetes });
    if(!r.ok) throw new Error('lecture ' + r.status);
    return r.json();
  }
  async function rpc(nom, params){
    const r = await fetch(`${URL_BASE}/rest/v1/rpc/${nom}`, { method:'POST', headers: entetes, body: JSON.stringify(params) });
    let j = null;
    try{ j = await r.json(); }catch(e){}
    if(!r.ok) throw new Error((j && j.message) || ('erreur ' + r.status));
    if(j && j.erreur) throw new Error(j.erreur);
    return j;
  }

  window.OCActus = {
    configure: !!(URL_BASE && CLE),
    RUBRIQUES, esc, rendreContenu, dateLongue, youtubeId, libelleLien, slugifier,
    // Liste publique (sans le texte ni la grande photo)
    async liste({ categorie = '', limite = 12, decalage = 0 } = {}){
      let q = `actus?select=id,slug,titre,chapo,categorie,auteur,miniature,publie_le&order=publie_le.desc&limit=${limite}&offset=${decalage}`;
      if(categorie && RUBRIQUES[categorie]) q += `&categorie=eq.${categorie}`;
      return lire(q);
    },
    async article(slug){
      const rows = await lire(`actus?select=*&slug=eq.${encodeURIComponent(slug)}&limit=1`);
      return rows[0] || null;
    },
    rpc
  };
})();
