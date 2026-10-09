/* ============================================================
   CHAT — L'Objectif Châlonnais
   Une bulle en bas à droite de chaque page, avec deux onglets :
   - « La discussion » : salon public, lisible par tous ; pour écrire,
     il faut avoir activé les alertes (anti-spam).
   - « Écrire à l'équipe » : conversation privée avec l'association.
   Données dans Supabase (voir supabase/chat.sql).
   À charger après config.js et push.js.
   ============================================================ */
(function(){
  const cfg = window.OC_CONFIG || {};
  const URL_BASE = (cfg.supabaseUrl || '').replace(/\/+$/, '');
  const CLE = cfg.supabaseCle || '';
  if(!URL_BASE || !CLE || cfg.chat === false) return;

  const entetes = { apikey: CLE, 'Content-Type': 'application/json' };
  if(CLE.startsWith('eyJ')) entetes.Authorization = 'Bearer ' + CLE;
  async function rpc(nom, corps){
    const r = await fetch(`${URL_BASE}/rest/v1/rpc/${nom}`, { method:'POST', headers: entetes, body: JSON.stringify(corps || {}) });
    let j = null; try{ j = await r.json(); }catch(e){}
    if(!r.ok) throw new Error((j && j.message) || 'Connexion impossible.');
    if(j && j.erreur) throw new Error(j.erreur);
    return j;
  }
  const ls = {
    get(k){ try{ return localStorage.getItem(k); }catch(e){ return null; } },
    set(k, v){ try{ localStorage.setItem(k, v); }catch(e){} }
  };
  function jeton(){
    let j = ls.get('oc-chat-jeton');
    if(!j){
      const a = new Uint8Array(24); crypto.getRandomValues(a);
      j = Array.from(a, b=> b.toString(16).padStart(2, '0')).join('');
      ls.set('oc-chat-jeton', j);
    }
    return j;
  }
  function quand(iso){
    const d = new Date(iso), maint = new Date();
    const min = Math.round((maint - d) / 60000);
    if(min < 1) return 'à l\'instant';
    if(min < 60) return `il y a ${min} min`;
    const h = d.toLocaleTimeString('fr-FR', { hour:'2-digit', minute:'2-digit' });
    if(d.toDateString() === maint.toDateString()) return h;
    const hier = new Date(maint); hier.setDate(maint.getDate() - 1);
    if(d.toDateString() === hier.toDateString()) return 'hier ' + h;
    return d.toLocaleDateString('fr-FR', { day:'numeric', month:'short' }) + ' ' + h;
  }
  const el = (tag, cls, txt)=>{ const e = document.createElement(tag); if(cls) e.className = cls; if(txt != null) e.textContent = txt; return e; };

  // ---------- Styles ----------
  const css = `
  .ocx{--x-bg:#F4F8FA;--x-surface:#FFFFFF;--x-ink:#183140;--x-soft:#4B6372;--x-muted:#7A8F9C;--x-line:#D7E3EA;--x-sky:#2E97C7;--x-tile:#E3EDF2;--x-mine:#183140;--x-mine-ink:#F4F8FA;--x-err:#C0472F;
    font-family:'Nunito',system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--x-ink);}
  @media (prefers-color-scheme: dark){ :root:not([data-theme="light"]) .ocx{--x-bg:#0F2230;--x-surface:#183140;--x-ink:#EAF4F9;--x-soft:#A9C2D0;--x-muted:#7F99A8;--x-line:#2B4A5E;--x-sky:#6CC1EA;--x-tile:#1D3A4C;--x-mine:#EAF4F9;--x-mine-ink:#0F2230;--x-err:#F08A73;} }
  :root[data-theme="dark"] .ocx{--x-bg:#0F2230;--x-surface:#183140;--x-ink:#EAF4F9;--x-soft:#A9C2D0;--x-muted:#7F99A8;--x-line:#2B4A5E;--x-sky:#6CC1EA;--x-tile:#1D3A4C;--x-mine:#EAF4F9;--x-mine-ink:#0F2230;--x-err:#F08A73;}
  .ocx *{box-sizing:border-box;}
  .ocx-bulle{
    position:fixed;right:18px;bottom:calc(18px + env(safe-area-inset-bottom,0px));z-index:1400;
    display:flex;align-items:center;gap:8px;border:none;cursor:pointer;
    background:#183140;color:#F4F8FA;font:inherit;font-weight:800;font-size:15px;
    padding:0 20px 0 16px;height:52px;border-radius:999px;box-shadow:0 10px 28px -8px rgba(10,24,34,.5);
    transition:transform .15s ease, bottom .2s ease;
  }
  .ocx-bulle:hover{transform:translateY(-2px);}
  .ocx-bulle:focus-visible{outline:3px solid #9FD8F5;outline-offset:3px;}
  .ocx-bulle .ico{font-size:21px;line-height:1;}
  .ocx-bulle .pastille{position:absolute;top:-3px;right:-3px;width:16px;height:16px;border-radius:50%;background:#E5484D;border:2.5px solid #F4F8FA;}
  @media (max-width:640px){ .ocx-bulle{padding:0;width:56px;height:56px;justify-content:center;} .ocx-bulle .txt{display:none;} }
  .ocx-panneau{
    position:fixed;right:18px;bottom:calc(84px + env(safe-area-inset-bottom,0px));z-index:1450;
    width:380px;max-width:calc(100vw - 36px);height:min(600px, calc(100vh - 120px));
    display:flex;flex-direction:column;background:var(--x-surface);border:1px solid var(--x-line);
    border-radius:18px;box-shadow:0 24px 60px -16px rgba(10,24,34,.45);overflow:hidden;
  }
  .ocx-panneau[hidden]{display:none;}
  @media (max-width:640px){ .ocx-panneau{inset:0;width:auto;max-width:none;height:auto;border-radius:0;border:none;padding-top:env(safe-area-inset-top,0px);} }
  .ocx-tete{display:flex;align-items:center;gap:10px;padding:14px 14px 0 18px;}
  .ocx-tete h2{font-family:'Baloo 2','Nunito',sans-serif;font-size:21px;font-weight:800;margin:0;flex:1;}
  .ocx-fermer{border:none;background:var(--x-tile);color:var(--x-ink);width:36px;height:36px;border-radius:50%;font-size:17px;cursor:pointer;}
  .ocx-onglets{display:flex;gap:6px;padding:12px 14px;border-bottom:1px solid var(--x-line);}
  .ocx-onglets button{flex:1;font:inherit;font-weight:800;font-size:14px;border:1.5px solid var(--x-line);background:transparent;color:var(--x-ink);border-radius:999px;padding:8px 6px;cursor:pointer;position:relative;}
  .ocx-onglets button[aria-selected="true"]{background:var(--x-mine);border-color:var(--x-mine);color:var(--x-mine-ink);}
  .ocx-onglets .pastille{position:absolute;top:-3px;right:6px;width:11px;height:11px;border-radius:50%;background:#E5484D;}
  .ocx-vue{flex:1;display:flex;flex-direction:column;min-height:0;}
  .ocx-vue[hidden]{display:none;}
  .ocx-fil{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:10px;background:var(--x-bg);overscroll-behavior:contain;}
  .ocx-intro{font-size:14px;color:var(--x-soft);text-align:center;padding:6px 10px 2px;line-height:1.5;}
  .ocx-msg{max-width:86%;align-self:flex-start;}
  .ocx-msg .q{font-size:12px;color:var(--x-muted);margin:0 4px 3px;display:flex;gap:8px;align-items:baseline;}
  .ocx-msg .q b{color:var(--x-soft);font-weight:800;}
  .ocx-msg .b{background:var(--x-surface);border:1px solid var(--x-line);border-radius:16px 16px 16px 4px;padding:9px 13px;font-size:15px;line-height:1.45;white-space:pre-wrap;overflow-wrap:anywhere;}
  .ocx-msg.moi{align-self:flex-end;}
  .ocx-msg.moi .q{justify-content:flex-end;}
  .ocx-msg.moi .b{background:var(--x-mine);color:var(--x-mine-ink);border-color:var(--x-mine);border-radius:16px 16px 4px 16px;}
  .ocx-msg.equipe .b{background:var(--x-tile);border-color:var(--x-tile);}
  .ocx-signaler{border:none;background:none;color:var(--x-muted);font:inherit;font-size:11.5px;cursor:pointer;padding:0;text-decoration:underline;opacity:.8;}
  .ocx-saisie{border-top:1px solid var(--x-line);padding:10px 12px calc(12px + env(safe-area-inset-bottom,0px));background:var(--x-surface);display:flex;flex-direction:column;gap:8px;}
  .ocx-ligne{display:flex;gap:8px;align-items:flex-end;}
  .ocx-saisie input, .ocx-saisie textarea{
    width:100%;font:inherit;font-size:16px;color:var(--x-ink);background:var(--x-bg);
    border:1.5px solid var(--x-line);border-radius:14px;padding:9px 12px;resize:none;
  }
  .ocx-saisie input:focus, .ocx-saisie textarea:focus{outline:none;border-color:var(--x-sky);}
  .ocx-saisie textarea{min-height:44px;max-height:120px;}
  .ocx-envoyer{flex-shrink:0;border:none;background:var(--x-mine);color:var(--x-mine-ink);font:inherit;font-weight:800;font-size:15px;border-radius:999px;height:44px;padding:0 16px;cursor:pointer;}
  .ocx-envoyer:disabled{opacity:.5;cursor:wait;}
  .ocx-mini{font-size:12.5px;color:var(--x-muted);line-height:1.45;}
  .ocx-mini a{color:var(--x-sky);}
  .ocx-mini button{border:none;background:none;color:var(--x-sky);font:inherit;font-weight:700;text-decoration:underline;cursor:pointer;padding:0;}
  .ocx-err{font-size:13px;color:var(--x-err);}
  .ocx-err:empty{display:none;}
  .ocx-cond{padding:14px 16px calc(16px + env(safe-area-inset-bottom,0px));border-top:1px solid var(--x-line);background:var(--x-surface);font-size:14px;line-height:1.5;color:var(--x-soft);}
  .ocx-cond strong{color:var(--x-ink);}
  .ocx-cond .ocx-envoyer{margin-top:10px;width:100%;}
  .ocx-champs{display:flex;gap:8px;}
  .ocx-champs input{font-size:15px;}
  .ocx-pseudo{font-size:15px !important;}
  .ocx-hp{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden;}
  `;
  const style = document.createElement('style'); style.textContent = css; document.head.appendChild(style);

  // ---------- Structure ----------
  const racine = el('div', 'ocx');
  racine.innerHTML = `
    <button type="button" class="ocx-bulle" aria-haspopup="dialog" aria-expanded="false" aria-controls="ocx-panneau">
      <span class="ico" aria-hidden="true">💬</span><span class="txt">Discuter</span><span class="pastille" hidden></span>
    </button>
    <section class="ocx-panneau" id="ocx-panneau" role="dialog" aria-modal="false" aria-labelledby="ocx-titre" hidden>
      <div class="ocx-tete"><h2 id="ocx-titre">On discute ?</h2><button type="button" class="ocx-fermer" aria-label="Fermer">✕</button></div>
      <div class="ocx-onglets" role="tablist">
        <button type="button" role="tab" data-v="salon" aria-selected="true">La discussion</button>
        <button type="button" role="tab" data-v="equipe" aria-selected="false">Écrire à l'équipe<span class="pastille" hidden></span></button>
      </div>

      <div class="ocx-vue" data-vue="salon" role="tabpanel">
        <div class="ocx-fil" aria-live="polite"><p class="ocx-intro">Chargement de la discussion…</p></div>
        <div class="ocx-cond" hidden></div>
        <form class="ocx-saisie" hidden>
          <div class="ocx-mini ocx-pseudo-ligne"></div>
          <div class="ocx-ligne">
            <textarea rows="1" maxlength="500" placeholder="Votre message…" aria-label="Votre message"></textarea>
            <button type="submit" class="ocx-envoyer">Envoyer</button>
          </div>
          <div class="ocx-err" role="alert"></div>
        </form>
      </div>

      <div class="ocx-vue" data-vue="equipe" role="tabpanel" hidden>
        <div class="ocx-fil" aria-live="polite"></div>
        <form class="ocx-saisie">
          <div class="ocx-champs">
            <input type="text" name="nom" maxlength="40" placeholder="Prénom (facultatif)" autocomplete="given-name" aria-label="Prénom">
            <input type="email" name="email" maxlength="254" placeholder="E-mail (facultatif)" autocomplete="email" aria-label="E-mail">
          </div>
          <div class="ocx-hp" aria-hidden="true"><input type="text" name="site" tabindex="-1" autocomplete="off"></div>
          <div class="ocx-ligne">
            <textarea rows="1" maxlength="1500" placeholder="Votre message à l'équipe…" aria-label="Votre message à l'équipe"></textarea>
            <button type="submit" class="ocx-envoyer">Envoyer</button>
          </div>
          <div class="ocx-err" role="alert"></div>
          <div class="ocx-mini">Laissez votre e-mail si vous voulez aussi une réponse par mail. <a href="mentions-legales.html#confidentialite">Confidentialité</a></div>
        </form>
      </div>
    </section>`;
  document.body.appendChild(racine);

  const $ = (s)=> racine.querySelector(s);
  const bulle = $('.ocx-bulle'), panneau = $('.ocx-panneau');
  const vueSalon = $('[data-vue="salon"]'), vueEquipe = $('[data-vue="equipe"]');
  const filSalon = vueSalon.querySelector('.ocx-fil'), filEquipe = vueEquipe.querySelector('.ocx-fil');
  const formSalon = vueSalon.querySelector('form'), condSalon = vueSalon.querySelector('.ocx-cond');
  const formEquipe = vueEquipe.querySelector('form');
  let vue = 'salon', ouvert = false, minuteur = null, dernierId = 0, ouvertLe = 0;
  const mesMessages = new Set(JSON.parse(ls.get('oc-chat-mes') || '[]'));

  // Textareas qui grandissent avec le texte ; Entrée envoie (Maj+Entrée = retour à la ligne)
  racine.querySelectorAll('textarea').forEach(t=>{
    t.addEventListener('input', ()=>{ t.style.height = 'auto'; t.style.height = Math.min(120, t.scrollHeight) + 'px'; });
    t.addEventListener('keydown', (e)=>{ if(e.key === 'Enter' && !e.shiftKey && !e.isComposing){ e.preventDefault(); t.form.requestSubmit(); } });
  });

  // La bulle remonte quand le bandeau « Installer l'application » est affiché
  const bandeau = document.querySelector('.oc-install');
  function placerBulle(){
    const visible = bandeau && !bandeau.hidden && bandeau.offsetHeight > 0;
    bulle.style.bottom = visible ? `calc(${bandeau.offsetHeight + 24}px + env(safe-area-inset-bottom,0px))` : '';
  }
  if(bandeau){ new MutationObserver(placerBulle).observe(bandeau, { attributes:true }); window.addEventListener('resize', placerBulle); placerBulle(); }

  // ---------- Ouvrir / fermer ----------
  function ouvrir(v){
    ouvert = true; ouvertLe = Date.now();
    panneau.hidden = false; bulle.setAttribute('aria-expanded', 'true');
    if(matchMedia('(max-width:640px)').matches){ document.documentElement.style.overflow = 'hidden'; bulle.hidden = true; }
    choisir(v || vue);
  }
  function fermer(){
    ouvert = false; panneau.hidden = true; bulle.hidden = false; bulle.setAttribute('aria-expanded', 'false');
    document.documentElement.style.overflow = '';
    clearInterval(minuteur); minuteur = null;
    if(location.hash === '#discussion' || location.hash === '#equipe') history.replaceState(null, '', location.pathname + location.search);
    bulle.focus();
  }
  bulle.onclick = ()=> ouvert ? fermer() : ouvrir();
  $('.ocx-fermer').onclick = fermer;
  document.addEventListener('keydown', (e)=>{ if(e.key === 'Escape' && ouvert) fermer(); });
  racine.querySelectorAll('[role="tab"]').forEach(b=> b.onclick = ()=> choisir(b.dataset.v));

  function choisir(v){
    vue = v;
    racine.querySelectorAll('[role="tab"]').forEach(b=> b.setAttribute('aria-selected', b.dataset.v === v));
    vueSalon.hidden = v !== 'salon'; vueEquipe.hidden = v !== 'equipe';
    clearInterval(minuteur);
    if(v === 'salon'){ chargerSalon(true); preparerSaisieSalon(); minuteur = setInterval(()=>{ if(!document.hidden) chargerSalon(false); }, 8000); }
    else { chargerEquipe(); minuteur = setInterval(()=>{ if(!document.hidden) chargerEquipe(); }, 20000); }
  }

  // ---------- La discussion ----------
  function bulleMessage(m, moi, extra){
    const d = el('div', 'ocx-msg' + (moi ? ' moi' : '') + (extra || ''));
    const q = el('div', 'q');
    const qui = el('b', '', m.pseudo || '');
    q.append(qui, el('span', '', quand(m.le)));
    d.append(q, el('div', 'b', m.texte));
    return d;
  }
  async function chargerSalon(tout){
    try{
      const liste = await rpc('oc_salon_lire', { p_apres: tout ? 0 : dernierId });
      const enBas = filSalon.scrollHeight - filSalon.scrollTop - filSalon.clientHeight < 80;
      if(tout){
        filSalon.innerHTML = '';
        filSalon.append(el('p', 'ocx-intro', 'Bienvenue dans la discussion des Chalonnais ! Restez cordiaux : les messages signalés sont masqués.'));
        dernierId = 0;
      }
      liste.forEach(m=>{
        if(m.id <= dernierId) return;
        const moi = mesMessages.has(m.id);
        const b = bulleMessage(m, moi);
        if(!moi){
          const s = el('button', 'ocx-signaler', 'Signaler'); s.type = 'button';
          s.onclick = async ()=>{
            if(!confirm('Signaler ce message à l\'équipe ? Il sera masqué s\'il est signalé plusieurs fois.')) return;
            try{ await rpc('oc_salon_signaler', { p_id: m.id }); s.textContent = 'Signalé, merci'; s.disabled = true; }catch(e){ s.textContent = e.message; }
          };
          b.querySelector('.q').append(s);
        }
        filSalon.append(b);
        dernierId = Math.max(dernierId, m.id);
      });
      if(tout && !liste.length) filSalon.append(el('p', 'ocx-intro', 'Personne n\'a encore écrit. Lancez la conversation !'));
      if(tout || enBas) filSalon.scrollTop = filSalon.scrollHeight;
    }catch(e){
      if(tout) filSalon.innerHTML = '<p class="ocx-intro">La discussion est momentanément indisponible.</p>';
    }
  }
  async function abonnement(){
    const OA = window.OCAlertes;
    if(!OA || !OA.disponible) return null;
    try{ return await Promise.race([OA.abonnement(), new Promise(r=> setTimeout(()=> r(null), 4000))]); }catch(e){ return null; }
  }
  async function preparerSaisieSalon(){
    if(formSalon.hidden){ condSalon.hidden = false; condSalon.textContent = 'Vérification de vos alertes…'; }
    const sub = await abonnement();
    const OA = window.OCAlertes;
    if(sub){
      condSalon.hidden = true; formSalon.hidden = false;
      const ligne = formSalon.querySelector('.ocx-pseudo-ligne');
      const pseudo = ls.get('oc-chat-pseudo');
      ligne.innerHTML = '';
      if(pseudo){
        ligne.append(document.createTextNode('Vous écrivez en tant que '), el('strong', '', pseudo), document.createTextNode(' · '));
        const chg = el('button', '', 'changer'); chg.type = 'button';
        chg.onclick = ()=>{ ls.set('oc-chat-pseudo', ''); preparerSaisieSalon().then(()=>{ const i = formSalon.querySelector('.ocx-pseudo'); i.value = pseudo; i.focus(); i.select(); }); };
        ligne.append(chg);
      }else{
        const i = el('input', 'ocx-pseudo'); i.type = 'text'; i.maxLength = 30; i.placeholder = 'Votre pseudo (2 à 30 caractères)'; i.setAttribute('aria-label', 'Votre pseudo'); i.autocomplete = 'nickname';
        ligne.append(i);
      }
      return;
    }
    formSalon.hidden = true; condSalon.hidden = false;
    condSalon.innerHTML = '';
    if(OA && OA.iphoneSansAppli){
      condSalon.innerHTML = '<strong>Pour écrire, activez nos alertes.</strong> Sur iPhone, elles ne fonctionnent que dans l\'application : touchez Partager puis « Sur l\'écran d\'accueil », ouvrez l\'appli et revenez ici.';
      return;
    }
    if(!OA || !OA.disponible){
      condSalon.innerHTML = '<strong>Lecture seule sur ce navigateur.</strong> Pour écrire, il faut pouvoir recevoir nos alertes : utilisez Chrome sur Android, ou l\'application sur iPhone.';
      return;
    }
    if(typeof Notification !== 'undefined' && Notification.permission === 'denied'){
      condSalon.innerHTML = '<strong>Pour écrire, autorisez nos alertes</strong> dans les réglages de votre téléphone, puis rechargez la page.';
      return;
    }
    condSalon.innerHTML = '<strong>Pour écrire, activez les alertes de L\'Objectif.</strong> C\'est notre façon d\'éviter le spam, et vous serez prévenu(e) des nouveautés.';
    const b = el('button', 'ocx-envoyer', 'Activer les alertes'); b.type = 'button';
    b.onclick = async ()=>{
      b.disabled = true;
      try{ const r = await OA.activer(); if(r === 'refuse') condSalon.insertAdjacentHTML('beforeend', '<div class="ocx-err">Alertes refusées : elles sont nécessaires pour écrire.</div>'); }
      catch(e){ condSalon.insertAdjacentHTML('beforeend', '<div class="ocx-err">L\'activation n\'a pas abouti, réessayez.</div>'); }
      b.disabled = false;
      preparerSaisieSalon();
    };
    condSalon.append(b);
  }
  formSalon.addEventListener('submit', async (e)=>{
    e.preventDefault();
    const ta = formSalon.querySelector('textarea'), err = formSalon.querySelector('.ocx-err'), btn = formSalon.querySelector('.ocx-envoyer');
    const texte = ta.value.trim();
    err.textContent = '';
    if(!texte) return;
    let pseudo = ls.get('oc-chat-pseudo');
    const champ = formSalon.querySelector('.ocx-pseudo');
    if(!pseudo){
      pseudo = champ ? champ.value.trim().slice(0, 30) : '';
      if(pseudo.length < 2){ err.textContent = 'Choisissez d\'abord un pseudo (2 caractères au moins).'; if(champ) champ.focus(); return; }
    }
    const sub = await abonnement();
    if(!sub){ preparerSaisieSalon(); return; }
    btn.disabled = true; err.textContent = '';
    try{
      if(window.OCAlertes.enregistrer) await window.OCAlertes.enregistrer(sub).catch(()=>{});
      const r = await rpc('oc_salon_ecrire', { p_pseudo: pseudo, p_texte: texte, p_endpoint: sub.endpoint });
      mesMessages.add(r.id); ls.set('oc-chat-mes', JSON.stringify([...mesMessages].slice(-200)));
      if(!ls.get('oc-chat-pseudo')){ ls.set('oc-chat-pseudo', pseudo); preparerSaisieSalon(); }
      ta.value = ''; ta.style.height = '';
      await chargerSalon(false);
      filSalon.scrollTop = filSalon.scrollHeight;
    }catch(ex){ err.textContent = ex.message; }
    finally{ btn.disabled = false; ta.focus(); }
  });

  // ---------- Écrire à l'équipe ----------
  async function chargerEquipe(){
    let msgs = [];
    try{ msgs = (await rpc('oc_conv_lire', { p_jeton: jeton() })).messages || []; }catch(e){}
    const enBas = filEquipe.scrollHeight - filEquipe.scrollTop - filEquipe.clientHeight < 80;
    filEquipe.innerHTML = '';
    filEquipe.append(el('p', 'ocx-intro', 'Une question, une info, un événement à couvrir ? Écrivez-nous : on vous répond ici, en général dans la journée.'));
    msgs.forEach(m=>{
      const moi = m.auteur === 'visiteur';
      filEquipe.append(bulleMessage({ pseudo: moi ? 'Vous' : 'L\'Objectif Châlonnais', texte: m.texte, le: m.le }, moi, moi ? '' : ' equipe'));
    });
    if(msgs.length && msgs[msgs.length - 1].auteur === 'visiteur'){
      filEquipe.append(el('p', 'ocx-intro', 'Message bien reçu ✓ Revenez ici pour lire notre réponse.'));
    }
    if(enBas || msgs.length) filEquipe.scrollTop = filEquipe.scrollHeight;
    marquerLu();
    const nom = formEquipe.querySelector('[name="nom"]'), mail = formEquipe.querySelector('[name="email"]');
    if(!nom.value) nom.value = ls.get('oc-chat-nom') || '';
    if(!mail.value) mail.value = ls.get('oc-chat-email') || '';
  }
  formEquipe.addEventListener('submit', async (e)=>{
    e.preventDefault();
    const ta = formEquipe.querySelector('textarea'), err = formEquipe.querySelector('.ocx-err'), btn = formEquipe.querySelector('.ocx-envoyer');
    const texte = ta.value.trim();
    if(!texte) return;
    if(formEquipe.querySelector('[name="site"]').value || Date.now() - ouvertLe < 1500) return;
    const nom = formEquipe.querySelector('[name="nom"]').value.trim(), email = formEquipe.querySelector('[name="email"]').value.trim();
    btn.disabled = true; err.textContent = '';
    try{
      await rpc('oc_conv_envoyer', { p_jeton: jeton(), p_nom: nom, p_email: email, p_texte: texte });
      ls.set('oc-chat-nom', nom); ls.set('oc-chat-email', email);
      ta.value = ''; ta.style.height = '';
      await chargerEquipe();
    }catch(ex){ err.textContent = ex.message; }
    finally{ btn.disabled = false; }
  });

  // ---------- Pastille « réponse de l'équipe » ----------
  function pastille(on){
    bulle.querySelector('.pastille').hidden = !on;
    racine.querySelector('[data-v="equipe"] .pastille').hidden = !on;
  }
  function marquerLu(){ pastille(false); }
  if(ls.get('oc-chat-jeton')){
    rpc('oc_conv_nouveau', { p_jeton: jeton() }).then(n=>{
      if(n === true){ pastille(true); bulle.setAttribute('aria-label', 'Discuter — nouvelle réponse de l\'équipe'); }
    }).catch(()=>{});
  }

  // Liens « #discussion » et « #equipe », et ouverture depuis la page
  window.OCChat = { ouvrir };
  if(location.hash === '#discussion') ouvrir('salon');
  if(location.hash === '#equipe') ouvrir('equipe');
})();
