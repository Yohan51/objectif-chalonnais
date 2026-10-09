/* ============================================================
   STOCKAGE — L'Objectif Châlonnais
   Fournit window.storage.get / set utilisés par la carte des bons plans.
   - Si Supabase est configuré dans config.js : données partagées entre
     tous les visiteurs (table « kv »).
   - Sinon : données gardées dans le navigateur du visiteur (localStorage).
   Les enregistrements passent par la fonction Supabase « oc_enregistrer »,
   qui contrôle chaque changement (voir supabase/securite.sql).
   Fournit aussi OC_verifierCode(code) pour l'espace modérateur et
   OC_inscrireNewsletter(email) pour la page d'accueil.
   ============================================================ */
(function(){
  const cfg = window.OC_CONFIG || {};
  const url = (cfg.supabaseUrl || '').replace(/\/+$/, '');
  const cle = cfg.supabaseCle || '';
  const partage = !!(url && cle);

  // Fonctionne avec l'ancienne clé « anon » (eyJ...) comme avec la nouvelle « publishable » (sb_publishable_...)
  const entetes = { 'apikey': cle, 'Content-Type': 'application/json' };
  if(cle.startsWith('eyJ')) entetes['Authorization'] = 'Bearer ' + cle;

  const local = {
    async get(key){
      try{
        const v = localStorage.getItem('oc:' + key);
        return v === null ? null : { key, value: v };
      }catch(e){ return null; }
    },
    async set(key, value){
      try{ localStorage.setItem('oc:' + key, value); return { key, value }; }
      catch(e){ return null; }
    }
  };

  const distant = {
    async get(key){
      const r = await fetch(`${url}/rest/v1/kv?key=eq.${encodeURIComponent(key)}&select=value`, { headers: entetes });
      if(!r.ok) throw new Error('lecture impossible (' + r.status + ')');
      const rows = await r.json();
      return rows.length ? { key, value: rows[0].value } : null;
    },
    // Renvoie la version enregistrée par la base (qui peut contenir les ajouts
    // d'autres visiteurs) : la page s'en sert pour se remettre à jour.
    async set(key, value){
      const operations = window.OC_OPERATIONS || null;
      window.OC_OPERATIONS = null;
      const r = await fetch(`${url}/rest/v1/rpc/oc_enregistrer`, {
        method: 'POST',
        headers: entetes,
        body: JSON.stringify({
          p_cle: key,
          p_valeur: value,
          p_code: window.OC_CODE_MODERATEUR || null,
          p_operations: operations
        })
      });
      if(!r.ok){
        let message = '';
        try{ const j = await r.json(); if(j && j.code === 'P0001') message = j.message || ''; }catch(e){}
        window.OC_DERNIERE_ERREUR = message;
        throw new Error(message || ('enregistrement impossible (' + r.status + ')'));
      }
      window.OC_DERNIERE_ERREUR = '';
      const enregistre = await r.json();
      return { key, value: typeof enregistre === 'string' ? enregistre : value };
    }
  };

  window.OC_STOCKAGE_PARTAGE = partage;
  window.storage = partage ? distant : local;

  // Code modérateur : vérifié par la base, jamais dans la page.
  // Renvoie true / false, ou null si la base partagée n'est pas configurée.
  window.OC_verifierCode = async function(code){
    if(!partage) return null;
    const r = await fetch(`${url}/rest/v1/rpc/oc_verifier_code`, {
      method: 'POST', headers: entetes, body: JSON.stringify({ p_code: code })
    });
    if(!r.ok) throw new Error('vérification impossible (' + r.status + ')');
    return (await r.json()) === true;
  };

  // Inscription newsletter : renvoie 'ok', 'deja' ou 'indisponible'
  window.OC_inscrireNewsletter = async function(email){
    if(!partage) return 'indisponible';
    const r = await fetch(`${url}/rest/v1/newsletter`, {
      method: 'POST',
      headers: { ...entetes, 'Prefer': 'return=minimal' },
      body: JSON.stringify({ email: email.trim().toLowerCase() })
    });
    if(r.status === 409) return 'deja';
    if(!r.ok) throw new Error('inscription impossible (' + r.status + ')');
    return 'ok';
  };
})();
