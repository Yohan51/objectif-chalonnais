/* ============================================================
   CONNEXION UNIQUE DE L'ÉQUIPE — L'Objectif Châlonnais
   Une seule connexion pour toutes les pages de l'équipe
   (rédaction, jeux, alertes, messages, statistiques, modération
   des bons plans). Le code est vérifié par Supabase à chaque action ;
   cet outil se contente de s'en souvenir.
   - « Rester connecté » coché : souvenu 30 jours sur cet appareil.
   - Sinon : seulement jusqu'à la fermeture du navigateur.
   ============================================================ */
(function(){
  const CLE_SESSION = 'oc-redaction-code';     // ancien nom, gardé pour compatibilité
  const CLE_DURABLE = 'oc-equipe';
  const DUREE = 30 * 24 * 3600 * 1000;

  function lire(){
    try{
      const s = sessionStorage.getItem(CLE_SESSION);
      if(s) return s;
      const o = JSON.parse(localStorage.getItem(CLE_DURABLE) || 'null');
      if(o && o.c && o.exp > Date.now()){ sessionStorage.setItem(CLE_SESSION, o.c); return o.c; }
      if(o) localStorage.removeItem(CLE_DURABLE);
      const ancien = localStorage.getItem('oc-code-envoi');
      if(ancien){ memoriser(ancien, true); return ancien; }
    }catch(e){}
    return null;
  }
  function memoriser(code, garder){
    if(!code) return;
    // choix de la case « Rester connecté » si l'on vient de se connecter avec le formulaire,
    // sinon (reconnexion automatique) on garde le réglage précédent
    if(garder === undefined) garder = dernierChoix !== null ? dernierChoix : souvenu();
    try{
      sessionStorage.setItem(CLE_SESSION, code);
      if(garder) localStorage.setItem(CLE_DURABLE, JSON.stringify({ c: code, exp: Date.now() + DUREE }));
      else localStorage.removeItem(CLE_DURABLE);
      localStorage.setItem('oc-ne-pas-compter', '1');   // les visites de l'équipe ne sont pas comptées
      localStorage.removeItem('oc-code-envoi');          // ancien stockage de la page des alertes
    }catch(e){}
  }
  function souvenu(){ try{ return !!localStorage.getItem(CLE_DURABLE); }catch(e){ return false; } }
  function oublier(){
    try{
      sessionStorage.removeItem(CLE_SESSION);
      localStorage.removeItem(CLE_DURABLE);
      localStorage.removeItem('oc-code-envoi');
    }catch(e){}
  }

  // Case « Rester connecté » ajoutée aux formulaires de connexion (data-equipe-login)
  function ajouterCase(form){
    if(!form || form.querySelector('[data-equipe-garder]')) return;
    const lab = document.createElement('label');
    lab.style.cssText = 'display:flex;align-items:center;justify-content:center;gap:8px;font-size:14px;margin:4px 0 12px;cursor:pointer;';
    const cb = document.createElement('input');
    cb.type = 'checkbox'; cb.checked = true; cb.setAttribute('data-equipe-garder', '');
    cb.style.cssText = 'width:17px;height:17px;margin:0;';
    lab.append(cb, document.createTextNode('Rester connecté sur cet appareil (30 jours)'));
    const bouton = form.querySelector('button[type="submit"], button:not([type])');
    if(bouton) bouton.before(lab); else form.append(lab);
  }
  let dernierChoix = null;
  function init(){
    document.querySelectorAll('[data-equipe-login]').forEach(f=>{
      ajouterCase(f);
      f.addEventListener('submit', ()=>{ const c = f.querySelector('[data-equipe-garder]'); dernierChoix = c ? c.checked : null; }, true);
    });
  }
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();

  window.OCEquipe = { code: lire, memoriser, oublier, souvenu };
})();
