// =====================================================================
// Pages de partage des actus — L'Objectif Châlonnais
//
// Lancé automatiquement par GitHub toutes les 15 minutes
// (.github/workflows/apercus.yml). Pour chaque article publié, crée :
//   a/<adresse-de-l-article>.html  → titre, résumé et photo lisibles par
//                                    WhatsApp, Facebook, Messenger, X…
//                                    puis renvoi immédiat vers l'article
//   a/<adresse-de-l-article>.jpg   → la photo de l'article
// et supprime les pages des articles retirés.
// =====================================================================
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const racine = process.cwd();
const dossier = path.join(racine, 'a');

// Réglages : config.js du site (ou variables d'environnement pour les tests)
const bac = { window: {} };
vm.runInNewContext(fs.readFileSync(path.join(racine, 'config.js'), 'utf8'), bac);
const cfg = bac.window.OC_CONFIG || {};
const SUPABASE = (process.env.SUPABASE_URL || cfg.supabaseUrl || '').replace(/\/+$/, '');
const CLE = process.env.SUPABASE_CLE || cfg.supabaseCle || '';
if(!SUPABASE || !CLE){ console.log('Supabase non configuré dans config.js : rien à faire.'); process.exit(0); }

// Adresse publique du site
function adresseSite(){
  if(process.env.SITE_URL) return process.env.SITE_URL.replace(/\/?$/, '/');
  const depot = process.env.GITHUB_REPOSITORY || '';
  const [proprio, nom] = depot.split('/');
  if(proprio && nom){
    return nom.toLowerCase() === `${proprio.toLowerCase()}.github.io`
      ? `https://${nom.toLowerCase()}/`
      : `https://${proprio.toLowerCase()}.github.io/${nom}/`;
  }
  return 'https://yohan51.github.io/objectif-chalonnais/';
}
const SITE = adresseSite();

const esc = (s)=> String(s == null ? '' : s)
  .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const court = (s, n)=> { s = String(s || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s; };

// Résumé : le chapô, sinon le début du texte sans mise en forme
function resume(a){
  if(a.chapo) return court(a.chapo, 200);
  return court(String(a.contenu || '').replace(/^##\s+/gm, '').replace(/\*\*/g, '').replace(/^\s*[-•]\s+/gm, ''), 200);
}

const entetes = { apikey: CLE };
if(CLE.startsWith('eyJ')) entetes.Authorization = 'Bearer ' + CLE;
const r = await fetch(`${SUPABASE}/rest/v1/actus?select=slug,titre,chapo,contenu,photo,miniature,categorie,auteur,publie_le,modifie_le&order=publie_le.desc&limit=2000`, { headers: entetes });
if(!r.ok){ console.error('Lecture des actus impossible :', r.status, await r.text()); process.exit(1); }
const actus = await r.json();

fs.mkdirSync(dossier, { recursive: true });
const gardes = new Set(['LISEZMOI.txt']);
const RUBRIQUES = { actu:'Actualité locale', sport:'Sport', culture:'Culture', evenement:'Événements', asso:'Vie de l\'asso' };

for(const a of actus){
  if(!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(a.slug)) continue;
  const versionImage = Date.parse(a.modifie_le || a.publie_le || '') || 0;

  // Photo
  let image = SITE + 'icons/partage.jpg', typeImage = 'image/jpeg';
  const data = a.photo || a.miniature;
  const m = data && data.match(/^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/]+=*)$/);
  if(m){
    const ext = m[1] === 'jpeg' ? 'jpg' : m[1];
    const fichier = `${a.slug}.${ext}`;
    const contenu = Buffer.from(m[2], 'base64');
    const chemin = path.join(dossier, fichier);
    if(!fs.existsSync(chemin) || !fs.readFileSync(chemin).equals(contenu)) fs.writeFileSync(chemin, contenu);
    gardes.add(fichier);
    image = `${SITE}a/${fichier}?v=${versionImage}`;
    typeImage = 'image/' + m[1];
  }

  const cible = `../actus.html#${a.slug}`;
  const titre = court(a.titre, 120);
  const desc = resume(a);
  const html = `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(titre)} — L'Objectif Châlonnais</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${esc(SITE + 'actus.html#' + a.slug)}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="L'Objectif Châlonnais">
<meta property="og:locale" content="fr_FR">
<meta property="og:title" content="${esc(titre)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(SITE + 'a/' + a.slug + '.html')}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:image:type" content="${typeImage}">
<meta property="og:image:alt" content="${esc(titre)}">
<meta property="article:published_time" content="${esc(a.publie_le || '')}">
<meta property="article:section" content="${esc(RUBRIQUES[a.categorie] || 'Actualité')}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(titre)}">
<meta name="twitter:description" content="${esc(desc)}">
<meta name="twitter:image" content="${esc(image)}">
<meta http-equiv="refresh" content="0; url=${esc(cible)}">
<link rel="icon" type="image/png" href="../icons/favicon-48.png">
<script>location.replace(${JSON.stringify(cible)});</script>
<style>body{font-family:system-ui,sans-serif;background:#F4F8FA;color:#183140;display:grid;place-items:center;min-height:100vh;margin:0;padding:16px;text-align:center}a{color:#2E97C7;font-weight:700}</style>
</head>
<body>
<p>${esc(titre)}<br><a href="${esc(cible)}">Lire l'article sur L'Objectif Châlonnais</a></p>
</body>
</html>
`;
  const fichierHtml = `${a.slug}.html`;
  const cheminHtml = path.join(dossier, fichierHtml);
  if(!fs.existsSync(cheminHtml) || fs.readFileSync(cheminHtml, 'utf8') !== html) fs.writeFileSync(cheminHtml, html);
  gardes.add(fichierHtml);
}

// Ménage : articles supprimés ou repassés en brouillon
let retires = 0;
for(const f of fs.readdirSync(dossier)){
  if(!gardes.has(f)){ fs.rmSync(path.join(dossier, f)); retires++; }
}
fs.writeFileSync(path.join(dossier, 'LISEZMOI.txt'),
  'Dossier fabriqué automatiquement par le robot « Aperçus des actus » (voir .github/workflows/apercus.yml).\nNe pas modifier à la main : il est regénéré toutes les 15 minutes.\n');

console.log(`${actus.length} article(s) publié(s) · ${retires} fichier(s) retiré(s) · site : ${SITE}`);
