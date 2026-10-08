/* ============================================================
   ALERTES (notifications) — L'Objectif Châlonnais
   Gère le bouton « Recevoir les alertes » (#alertes-btn) :
   demande l'autorisation, abonne le téléphone et l'enregistre
   dans Supabase (table push_subscriptions).
   ============================================================ */
(function(){
  // Clé publique de signature des alertes (elle peut être publique)
  const VAPID_PUBLIC_KEY = 'BFRu7fLOPv3NAc08DrzMfeI50M78-WOQe9hH_FGcT2FQKyXzWurFSho0xDBgzTzM3p1wmDGfiS1t028MsaWuc30';

  const cfg = window.OC_CONFIG || {};
  const URL_BASE = (cfg.supabaseUrl || '').replace(/\/+$/, '');
  const CLE = cfg.supabaseCle || '';

  const btn = document.getElementById('alertes-btn');
  const statusEl = document.getElementById('alertes-status');
  if(!btn || !statusEl) return;

  const ua = navigator.userAgent || '';
  const isIOS = /iphone|ipad|ipod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const supported = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;

  function setStatus(msg, kind){
    statusEl.textContent = msg;
    statusEl.className = 'news-status' + (kind ? ' ' + kind : '');
  }
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
  async function saveSubscription(sub){
    const headers = { 'apikey': CLE, 'Content-Type': 'application/json', 'Prefer': 'resolution=ignore-duplicates,return=minimal' };
    if(CLE.startsWith('eyJ')) headers['Authorization'] = 'Bearer ' + CLE;
    const r = await fetch(`${URL_BASE}/rest/v1/push_subscriptions`, {
      method: 'POST', headers,
      body: JSON.stringify({ endpoint: sub.endpoint, p256dh: keyToB64u(sub.getKey('p256dh')), auth: keyToB64u(sub.getKey('auth')) })
    });
    if(!r.ok && r.status !== 409) throw new Error('enregistrement ' + r.status);
  }

  function showSubscribed(){
    btn.textContent = 'Désactiver les alertes';
    btn.dataset.state = 'on';
    setStatus('Alertes activées sur cet appareil.', 'ok');
  }
  function showOff(){
    btn.textContent = 'Recevoir les alertes';
    btn.dataset.state = 'off';
  }

  async function init(){
    if(!URL_BASE || !CLE){ btn.disabled = true; setStatus('Les alertes seront bientôt disponibles.'); return; }
    if(isIOS && !isStandalone){
      btn.hidden = true;
      setStatus('Sur iPhone, installez d\'abord l\'application (Partager → Sur l\'écran d\'accueil), puis ouvrez-la pour activer les alertes.');
      return;
    }
    if(!supported){ btn.hidden = true; setStatus('Ce navigateur ne permet pas de recevoir des alertes.'); return; }
    if(Notification.permission === 'denied'){
      showOff();
      setStatus('Les alertes sont bloquées pour ce site. Autorisez-les dans les réglages de votre navigateur.', 'err');
      return;
    }
    try{
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if(sub){ showSubscribed(); saveSubscription(sub).catch(()=>{}); }
      else showOff();
    }catch(e){ showOff(); }
  }

  btn.addEventListener('click', async ()=>{
    btn.disabled = true;
    try{
      const reg = await navigator.serviceWorker.ready;
      if(btn.dataset.state === 'on'){
        const sub = await reg.pushManager.getSubscription();
        if(sub) await sub.unsubscribe();
        showOff();
        setStatus('Alertes désactivées sur cet appareil.');
        return;
      }
      const perm = await Notification.requestPermission();
      if(perm !== 'granted'){
        setStatus(perm === 'denied'
          ? 'Vous avez refusé les alertes. Vous pourrez les autoriser plus tard dans les réglages du navigateur.'
          : 'Alertes non activées.', perm === 'denied' ? 'err' : '');
        return;
      }
      const sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64uToUint8(VAPID_PUBLIC_KEY) });
      await saveSubscription(sub);
      showSubscribed();
    }catch(e){
      setStatus('L\'activation n\'a pas abouti. Réessayez dans quelques instants.', 'err');
    }finally{
      btn.disabled = false;
    }
  });

  init();
})();
