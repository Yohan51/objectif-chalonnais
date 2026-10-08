/* ============================================================
   MODE APPLICATION — L'Objectif Châlonnais
   - Active le fonctionnement hors ligne (service worker).
   - Affiche l'invitation à installer l'application sur la page
     qui contient un élément #install-banner.
   ============================================================ */
(function(){
  if('serviceWorker' in navigator){
    window.addEventListener('load', ()=>{
      navigator.serviceWorker.register('sw.js').catch(()=>{});
    });
  }

  const banner = document.getElementById('install-banner');
  if(!banner) return;

  const DISMISS_KEY = 'oc-install-dismissed';
  const DISMISS_DAYS = 30;
  const ua = navigator.userAgent || '';
  const isIOS = /iphone|ipad|ipod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;

  const text = banner.querySelector('[data-install-text]');
  const actionBtn = banner.querySelector('[data-install-action]');
  const closeBtn = banner.querySelector('[data-install-close]');
  const footerLink = document.getElementById('install-link');
  let deferredPrompt = null;

  function recentlyDismissed(){
    try{
      const t = parseInt(localStorage.getItem(DISMISS_KEY) || '0', 10);
      return Date.now() - t < DISMISS_DAYS * 24 * 3600 * 1000;
    }catch(e){ return false; }
  }
  function show(mode){
    if(mode === 'ios'){
      text.innerHTML = 'Installez l\'appli : touchez <strong>Partager</strong> <svg aria-hidden="true" width="14" height="16" viewBox="0 0 14 16" style="vertical-align:-2px"><path d="M7 1v9M3.5 4.5 7 1l3.5 3.5M2 7.5v6.5h10V7.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg> puis <strong>Sur l\'écran d\'accueil</strong>.';
      actionBtn.hidden = true;
    }else if(mode === 'prompt'){
      text.textContent = 'Ajoutez L\'Objectif Châlonnais à votre écran d\'accueil, comme une application.';
      actionBtn.hidden = false;
    }else{
      text.innerHTML = 'Dans le menu de votre navigateur, choisissez <strong>Installer l\'application</strong> ou <strong>Ajouter à l\'écran d\'accueil</strong>.';
      actionBtn.hidden = true;
    }
    banner.hidden = false;
  }
  function hide(remember){
    banner.hidden = true;
    if(remember){ try{ localStorage.setItem(DISMISS_KEY, String(Date.now())); }catch(e){} }
  }

  if(isStandalone){
    if(footerLink) footerLink.hidden = true;
    return;
  }

  window.addEventListener('beforeinstallprompt', (e)=>{
    e.preventDefault();
    deferredPrompt = e;
    if(!recentlyDismissed()) show('prompt');
  });
  window.addEventListener('appinstalled', ()=>{ hide(false); deferredPrompt = null; });

  if(isIOS && !recentlyDismissed()) setTimeout(()=> show('ios'), 1200);

  actionBtn.addEventListener('click', async ()=>{
    if(!deferredPrompt) return;
    deferredPrompt.prompt();
    const choice = await deferredPrompt.userChoice.catch(()=> null);
    deferredPrompt = null;
    hide(!choice || choice.outcome !== 'accepted');
  });
  closeBtn.addEventListener('click', ()=> hide(true));

  if(footerLink){
    footerLink.addEventListener('click', (e)=>{
      e.preventDefault();
      show(deferredPrompt ? 'prompt' : (isIOS ? 'ios' : 'menu'));
    });
  }
})();
