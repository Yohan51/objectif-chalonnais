/* ============================================================
   ALERTES (notifications) — L'Objectif Châlonnais
   - À la première ouverture de l'application installée : fenêtre
     de bienvenue qui propose d'activer les alertes.
   - Sur l'accueil : bouton « Recevoir les alertes » (#alertes-btn).
   Les abonnements sont enregistrés dans Supabase (push_subscriptions).
   ============================================================ */
(function(){
  // Clé publique de signature des alertes (elle peut être publique)
  const VAPID_PUBLIC_KEY = 'BFRu7fLOPv3NAc08DrzMfeI50M78-WOQe9hH_FGcT2FQKyXzWurFSho0xDBgzTzM3p1wmDGfiS1t028MsaWuc30';
  const PROPOSE_KEY = 'oc-alertes-proposees';

  const cfg = window.OC_CONFIG || {};
  const URL_BASE = (cfg.supabaseUrl || '').replace(/\/+$/, '');
  const CLE = cfg.supabaseCle || '';

  const ua = navigator.userAgent || '';
  const isIOS = /iphone|ipad|ipod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const supported = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  const configured = !!(URL_BASE && CLE);

  // ---------- Outils ----------
  function b64uToUint8(s){
    s = s.replace(/-/g,'+').replace(/_/g,'/'); while(s.length % 4) s += '=';
    const bin = atob(s); const out = new Uint8Array(bin.length);
    for(let i=0;i<bin.length;i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function keyToB64u(buf){
    const b = new Uint8Array(buf); let bin = '';
    for(let i=0;i<b.length;i++) bin += String.fromCharCode(b[i]);
    return btoa(bin).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  }
  function store(key, val){ try{ localStorage.setItem(key, val); }catch(e){} }
  function read(key){ try{ return localStorage.getItem(key); }catch(e){ return null; } }

  async function saveSubscription(sub){
    const headers = { 'apikey': CLE, 'Content-Type': 'application/json', 'Prefer': 'return=minimal' };
    if(CLE.startsWith('eyJ')) headers['Authorization'] = 'Bearer ' + CLE;
    const r = await fetch(`${URL_BASE}/rest/v1/push_subscriptions`, {
      method: 'POST', headers,
      body: JSON.stringify({ endpoint: sub.endpoint, p256dh: keyToB64u(sub.getKey('p256dh')), auth: keyToB64u(sub.getKey('auth')) })
    });
    // 409 = ce téléphone est déjà enregistré : tout va bien
    if(!r.ok && r.status !== 409){
      let detail = '';
      try{ const j = await r.json(); detail = j.message || j.msg || ''; }catch(e){}
      throw new Error(`base ${r.status}${detail ? ' : ' + detail : ''}`);
    }
  }

  async function currentSubscription(){
    try{
      const reg = await navigator.serviceWorker.ready;
      return await reg.pushManager.getSubscription();
    }catch(e){ return null; }
  }

  // Active les alertes. À appeler directement depuis un toucher sur un bouton :
  // iPhone n'affiche la demande d'autorisation qu'à cette condition.
  // Renvoie 'ok', 'refuse' ou 'ignore' ; lève une erreur en cas de problème.
  async function activer(){
    const perm = await Notification.requestPermission();
    if(perm !== 'granted') return perm === 'denied' ? 'refuse' : 'ignore';
    const reg = await navigator.serviceWorker.ready;
    const sub = (await reg.pushManager.getSubscription())
      || await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64uToUint8(VAPID_PUBLIC_KEY) });
    await saveSubscription(sub);
    document.dispatchEvent(new CustomEvent('oc-alertes', { detail: 'on' }));
    return 'ok';
  }

  // ---------- Fenêtre de bienvenue (première ouverture de l'appli) ----------
  async function proposerAuDemarrage(){
    if(!configured || !supported || !isStandalone) return;
    if(Notification.permission !== 'default') return;
    if(read(PROPOSE_KEY)) return;
    if(await currentSubscription()) return;

    const overlay = document.createElement('div');
    overlay.className = 'oc-welcome';
    overlay.innerHTML = `
      <div class="oc-welcome-card" role="dialog" aria-modal="true" aria-labelledby="oc-welcome-title">
        <img src="icons/icon-192.png" alt="" width="64" height="64">
        <h2 id="oc-welcome-title">Bienvenue dans l'appli !</h2>
        <p>Activez les alertes pour être prévenu(e) des nouveaux albums photo, des événements à ne pas manquer et des infos importantes de Châlons.</p>
        <p class="oc-welcome-small">Quelques alertes par mois, pas plus. Vous pourrez les désactiver à tout moment depuis l'accueil.</p>
        <button type="button" class="oc-welcome-yes">Activer les alertes</button>
        <button type="button" class="oc-welcome-no">Plus tard</button>
        <p class="oc-welcome-status" aria-live="polite"></p>
      </div>`;
    document.body.appendChild(overlay);
    const yes = overlay.querySelector('.oc-welcome-yes');
    const no = overlay.querySelector('.oc-welcome-no');
    const status = overlay.querySelector('.oc-welcome-status');
    const fermer = ()=> overlay.remove();
    setTimeout(()=> yes.focus(), 50);

    no.addEventListener('click', ()=>{ store(PROPOSE_KEY, 'plus-tard'); fermer(); });
    yes.addEventListener('click', async ()=>{
      yes.disabled = true; no.disabled = true;
      status.textContent = 'Activation…';
      try{
        const res = await activer();
        store(PROPOSE_KEY, res);
        if(res === 'ok'){
          status.textContent = 'C\'est fait ! Vous recevrez nos prochaines alertes.';
          setTimeout(fermer, 1600);
        }else{
          fermer();
        }
      }catch(e){
        status.textContent = `L'activation n'a pas abouti (${e && e.message ? e.message : 'erreur inconnue'}). Vous pourrez réessayer depuis l'accueil.`;
        no.disabled = false; no.textContent = 'Fermer';
        store(PROPOSE_KEY, 'erreur');
      }
    });
  }

  // ---------- Bouton de l'accueil ----------
  function initBouton(){
    const btn = document.getElementById('alertes-btn');
    const statusEl = document.getElementById('alertes-status');
    if(!btn || !statusEl) return;

    const setStatus = (msg, kind)=>{
      statusEl.textContent = msg;
      statusEl.className = 'news-status' + (kind ? ' ' + kind : '');
    };
    const showOn = ()=>{
      btn.textContent = 'Désactiver les alertes';
      btn.dataset.state = 'on';
      setStatus('Alertes activées sur cet appareil.', 'ok');
    };
    const showOff = ()=>{
      btn.textContent = 'Recevoir les alertes';
      btn.dataset.state = 'off';
    };
    document.addEventListener('oc-alertes', (e)=>{ if(e.detail === 'on') showOn(); });

    if(!configured){ btn.disabled = true; setStatus('Les alertes seront bientôt disponibles.'); return; }
    if(isIOS && !isStandalone){
      btn.hidden = true;
      setStatus('Sur iPhone, installez d\'abord l\'application (Partager → Sur l\'écran d\'accueil), puis ouvrez-la pour activer les alertes.');
      return;
    }
    if(!supported){ btn.hidden = true; setStatus('Ce navigateur ne permet pas de recevoir des alertes.'); return; }
    if(Notification.permission === 'denied'){
      showOff();
      setStatus('Les alertes sont bloquées pour ce site. Autorisez-les dans les réglages de votre téléphone ou du navigateur.', 'err');
    }else{
      showOff();
      currentSubscription().then(sub=>{
        if(!sub) return;
        showOn();
        // Renvoie l'abonnement à la base à chaque visite (sans effet s'il y est déjà)
        saveSubscription(sub).catch(e=> setStatus(`Alertes activées, mais l'enregistrement a échoué (${e.message}).`, 'err'));
      });
    }

    btn.addEventListener('click', async ()=>{
      btn.disabled = true;
      try{
        if(btn.dataset.state === 'on'){
          const sub = await currentSubscription();
          if(sub) await sub.unsubscribe();
          showOff();
          setStatus('Alertes désactivées sur cet appareil.');
          return;
        }
        const res = await activer();
        if(res === 'refuse') setStatus('Vous avez refusé les alertes. Vous pourrez les autoriser plus tard dans les réglages.', 'err');
        else if(res === 'ignore') setStatus('Alertes non activées.');
      }catch(e){
        setStatus(`L'activation n'a pas abouti (${e && e.message ? e.message : 'erreur inconnue'}).`, 'err');
      }finally{
        btn.disabled = false;
      }
    });
  }

  // Pour les autres pages (jeux concours…)
  window.OCAlertes = {
    disponible: configured && supported && !(isIOS && !isStandalone),
    iphoneSansAppli: isIOS && !isStandalone,
    abonnement: currentSubscription,
    enregistrer: saveSubscription,
    activer
  };

  initBouton();
  proposerAuDemarrage();
})();
