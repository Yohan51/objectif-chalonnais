/* ============================================================
   STOCKAGE — L'Objectif Châlonnais
   Fournit window.storage.get / set utilisés par la carte des bons plans.
   - Si Supabase est configuré dans config.js : données partagées entre
     tous les visiteurs (table « kv »).
   - Sinon : données gardées dans le navigateur du visiteur (localStorage).
   Fournit aussi OC_inscrireNewsletter(email) pour la page d'accueil.
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
    async set(key, value){
      const r = await fetch(`${url}/rest/v1/kv`, {
        method: 'POST',
        headers: { ...entetes, 'Prefer': 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ key, value, updated_at: new Date().toISOString() })
      });
      if(!r.ok) throw new Error('enregistrement impossible (' + r.status + ')');
      return { key, value };
    }
  };

  window.OC_STOCKAGE_PARTAGE = partage;
  window.storage = partage ? distant : local;

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
