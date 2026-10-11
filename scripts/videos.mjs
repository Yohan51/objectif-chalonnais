// =====================================================================
// Dernières vidéos YouTube — L'Objectif Châlonnais
//
// Lancé par GitHub toutes les 15 minutes (.github/workflows/apercus.yml).
// Lit le flux public de la chaîne YouTube et écrit data/videos.json,
// affiché sur la page Direct (rubrique « Nos dernières vidéos »).
// Aucune clé nécessaire. L'identifiant de la chaîne peut être changé
// dans config.js (youtubeChaineId).
// =====================================================================
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const racine = process.cwd();
const bac = { window: {} };
try{ vm.runInNewContext(fs.readFileSync(path.join(racine, 'config.js'), 'utf8'), bac); }catch(e){}
const cfg = bac.window.OC_CONFIG || {};
const CHAINE = process.env.YOUTUBE_CHAINE || cfg.youtubeChaineId || 'UC3ehDb-pE4B8E-xOiPD76XQ';
const fichier = path.join(racine, 'data', 'videos.json');

const decoder = (s)=> s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
  .replace(/&#(\d+);/g, (_, n)=> String.fromCodePoint(+n)).replace(/&amp;/g, '&');
const champ = (bloc, balise)=> { const m = bloc.match(new RegExp(`<${balise}[^>]*>([\\s\\S]*?)</${balise}>`)); return m ? decoder(m[1].trim()) : ''; };

export function lireFlux(xml){
  return [...xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)].map(([, e])=>{
    const id = champ(e, 'yt:videoId');
    const lien = (e.match(/<link[^>]*href="([^"]+)"/) || [])[1] || '';
    return { id, titre: champ(e, 'title'), date: champ(e, 'published'), court: /\/shorts\//.test(lien) || undefined };
  }).filter(v=> /^[A-Za-z0-9_-]{11}$/.test(v.id)).slice(0, 15);
}

if(import.meta.url === `file://${process.argv[1]}`){
  try{
    const r = await fetch(`https://www.youtube.com/feeds/videos.xml?channel_id=${encodeURIComponent(CHAINE)}`, { headers: { 'User-Agent': 'Mozilla/5.0 (L\'Objectif Chalonnais)' } });
    if(!r.ok){ console.log(`Flux YouTube indisponible (${r.status}) : on garde la liste actuelle.`); process.exit(0); }
    const videos = lireFlux(await r.text());
    if(!videos.length){ console.log('Aucune vidéo dans le flux : on garde la liste actuelle.'); process.exit(0); }
    let avant = '';
    try{ avant = JSON.stringify(JSON.parse(fs.readFileSync(fichier, 'utf8')).videos); }catch(e){}
    if(avant === JSON.stringify(videos)){ console.log('Vidéos inchangées.'); process.exit(0); }
    fs.mkdirSync(path.dirname(fichier), { recursive: true });
    fs.writeFileSync(fichier, JSON.stringify({ chaine: CHAINE, maj: new Date().toISOString(), videos }, null, 1) + '\n');
    console.log(`${videos.length} vidéo(s) enregistrée(s) — la plus récente : « ${videos[0].titre} »`);
  }catch(e){
    console.log('Lecture du flux YouTube impossible : ' + e.message);
  }
}
