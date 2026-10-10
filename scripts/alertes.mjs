// =====================================================================
// Alertes automatiques — L'Objectif Châlonnais
//
// Lancé par GitHub toutes les 15 minutes (.github/workflows/apercus.yml).
// Demande à la fonction d'envoi de Supabase d'annoncer les articles
// programmés dont l'heure est arrivée (et toute publication pas encore
// annoncée). Chaque alerte n'est envoyée qu'une fois : relancer ce script
// ne crée jamais de doublon.
// =====================================================================
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const bac = { window: {} };
try{ vm.runInNewContext(fs.readFileSync(path.join(process.cwd(), 'config.js'), 'utf8'), bac); }catch(e){}
const cfg = bac.window.OC_CONFIG || {};
const SUPABASE = (process.env.SUPABASE_URL || cfg.supabaseUrl || '').replace(/\/+$/, '');
const CLE = process.env.SUPABASE_CLE || cfg.supabaseCle || '';
if(!SUPABASE || !CLE){ console.log('Supabase non configuré dans config.js : rien à faire.'); process.exit(0); }

const h = { apikey: CLE, 'Content-Type': 'application/json' };
if(CLE.startsWith('eyJ')) h.Authorization = 'Bearer ' + CLE;
try{
  const r = await fetch(`${SUPABASE}/functions/v1/envoyer-notification`, { method: 'POST', headers: h, body: JSON.stringify({ auto: true }) });
  const j = await r.json().catch(()=> ({}));
  if(j.erreur){ console.log('Alertes automatiques : ' + j.erreur); process.exit(0); }
  if(!j.alertes){ console.log('Aucune nouvelle publication à annoncer.'); process.exit(0); }
  console.log(`${j.alertes} alerte(s) envoyée(s) : ${(j.titres || []).join(' · ')} → ${j.envoyes} réussie(s), ${j.echecs} échec(s), ${j.supprimes} abonnement(s) expiré(s) retiré(s).`);
}catch(e){
  console.log('Fonction d\'envoi injoignable : ' + e.message);
}
