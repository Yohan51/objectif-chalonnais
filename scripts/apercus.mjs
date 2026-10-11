// =====================================================================
// Pages des actus (Google + partage) — L'Objectif Châlonnais
//
// Lancé automatiquement par GitHub toutes les 15 minutes
// (.github/workflows/apercus.yml). Pour chaque article publié, crée :
//   a/<adresse-de-l-article>.html  → l'article complet en page « fixe » :
//                                    lisible par Google (fiche NewsArticle),
//                                    et titre/résumé/photo pour WhatsApp,
//                                    Facebook, Messenger, X…
//   a/<adresse-de-l-article>.jpg   → la photo réduite (partages)
//   a/<adresse-de-l-article>-photo.jpg → la photo de l'article
//   a/index.html                   → les archives : tous les articles
//   sitemap.xml                    → le plan du site pour Google
// et supprime les pages des articles retirés.
// =====================================================================
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';

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
  // Nom de domaine personnalisé (fichier CNAME créé par GitHub Pages)
  try{
    const domaine = fs.readFileSync(path.join(racine, 'CNAME'), 'utf8').trim();
    if(domaine) return `https://${domaine}/`;
  }catch(e){}
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

// Dimensions d'une image JPEG/PNG (sans bibliothèque) : Facebook et WhatsApp
// affichent la photo dès le premier partage quand largeur et hauteur sont fournies.
function dimensions(buf){
  if(buf[0] === 0x89 && buf[1] === 0x50) return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
  if(buf[0] !== 0xFF || buf[1] !== 0xD8) return null;
  let i = 2;
  while(i + 9 < buf.length){
    if(buf[i] !== 0xFF){ i++; continue; }
    const m = buf[i + 1];
    if(m >= 0xC0 && m <= 0xCF && ![0xC4, 0xC8, 0xCC].includes(m)) return { h: buf.readUInt16BE(i + 5), w: buf.readUInt16BE(i + 7) };
    i += 2 + buf.readUInt16BE(i + 2);
  }
  return null;
}

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
const r = await fetch(`${SUPABASE}/rest/v1/actus?select=slug,titre,chapo,contenu,photo,miniature,legende,lien,lien_libelle,categorie,auteur,publie_le,modifie_le&order=publie_le.desc&limit=2000`, { headers: entetes });
if(!r.ok){ console.error('Lecture des actus impossible :', r.status, await r.text()); process.exit(1); }
const actus = await r.json();

fs.mkdirSync(dossier, { recursive: true });
const gardes = new Set(['LISEZMOI.txt']);
const RUBRIQUES = { actu:'Actualité locale', sport:'Sport', culture:'Culture', evenement:'Événements', asso:'Vie de l\'asso' };

// Mise en forme du texte : la même que sur le site (actus-rendu.js)
const bacRendu = { window: { OC_CONFIG: {} }, console };
vm.runInNewContext(fs.readFileSync(path.join(racine, 'actus-rendu.js'), 'utf8'), bacRendu);
const R = bacRendu.window.OCActus;
const MOIS = ['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'];
const dateFr = (iso)=>{ const d = new Date(iso); return isNaN(d) ? '' : `${d.toLocaleDateString('fr-FR', { day: 'numeric', timeZone: 'Europe/Paris' })} ${MOIS[+d.toLocaleDateString('fr-FR', { month: 'numeric', timeZone: 'Europe/Paris' }) - 1]} ${d.toLocaleDateString('fr-FR', { year: 'numeric', timeZone: 'Europe/Paris' })}`; };
const extMini = (x)=>{ const d = x.miniature || x.photo; const m = d && d.match(/^data:image\/(jpeg|png|webp);/); return m ? (m[1] === 'jpeg' ? 'jpg' : m[1]) : null; };
const json = (o)=> JSON.stringify(o).replace(/</g, '\\u003c');

const TETE_COMMUNE = `<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Baloo+2:wght@600;700;800&family=Nunito:wght@400;600;700;800&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&family=IBM+Plex+Mono:wght@500&display=swap">
<link rel="stylesheet" href="../site.css">
<link rel="manifest" href="../manifest.webmanifest">
<meta name="theme-color" content="#FBFAF6">
<link rel="apple-touch-icon" href="../icons/apple-touch-icon.png">
<link rel="icon" type="image/png" href="../icons/favicon-48.png">
<style>
  :root{--bg:#F4F8FA;--surface:#fff;--ink:#183140;--ink-soft:#4B6372;--line:#D7E3EA;--sky:#9FD8F5;--sky-deep:#2E97C7;--tile:#E3EDF2;
    --font-display:'Baloo 2','Nunito',system-ui,sans-serif;--font-body:'Nunito',system-ui,-apple-system,'Segoe UI',sans-serif;
    --font-read:'Source Serif 4',Georgia,'Times New Roman',serif;--font-mono:'IBM Plex Mono',ui-monospace,Menlo,monospace;}
  @media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#0F2230;--surface:#183140;--ink:#EAF4F9;--ink-soft:#A9C2D0;--line:#2B4A5E;--sky-deep:#6CC1EA;--tile:#1D3A4C;color-scheme:dark;}}
  *{box-sizing:border-box;} html,body{margin:0;}
  body{background:var(--bg);color:var(--ink);font-family:var(--font-body);font-size:16px;line-height:1.6;}
  a{color:var(--sky-deep);}
  h1,h2,h3{font-family:var(--font-display);line-height:1.12;margin:0;text-wrap:balance;}
  .article{max-width:760px;margin:0 auto;padding:28px 20px 40px;}
  .retour{font-weight:800;font-size:14px;text-decoration:none;color:var(--ink);display:inline-flex;gap:6px;margin-bottom:24px;}
  .meta{display:flex;gap:10px;flex-wrap:wrap;align-items:center;font-family:var(--font-mono);font-size:12.5px;color:var(--ink-soft);}
  .tag{background:var(--tile);border-radius:999px;padding:2px 10px;color:var(--ink);}
  .article h1{font-size:clamp(32px,5vw,48px);font-weight:800;margin:12px 0 14px;}
  .chapo{font-size:20px;line-height:1.5;color:var(--ink-soft);margin:0 0 20px;font-weight:600;}
  .figure{margin:28px 0;} .figure img{width:100%;height:auto;border-radius:12px;display:block;background:var(--tile);}
  .figure figcaption{font-size:13.5px;color:var(--ink-soft);margin-top:8px;}
  .corps{font-family:var(--font-read);font-size:19px;line-height:1.7;}
  .corps p{margin:0 0 1.1em;} .corps h2{font-family:var(--font-display);font-size:26px;font-weight:800;margin:1.6em 0 .5em;}
  .corps ul{margin:0 0 1.1em;padding-left:1.2em;} .corps li{margin-bottom:.35em;} .corps a{overflow-wrap:anywhere;}
  .btn{display:inline-flex;align-items:center;gap:8px;font:inherit;font-weight:800;font-size:15px;padding:11px 18px;border-radius:999px;border:2px solid var(--line);background:var(--surface);color:var(--ink);cursor:pointer;text-decoration:none;}
  .btn-main{background:var(--ink);color:var(--bg);border-color:var(--ink);}
  .partage{display:flex;flex-wrap:wrap;gap:10px;align-items:center;border-top:1px solid var(--line);border-bottom:1px solid var(--line);padding-block:16px;margin:36px 0;}
  .partage span{font-weight:800;margin-right:6px;}
  .autres{max-width:1080px;margin:0 auto;padding:8px 20px 56px;}
  .autres h2{font-size:26px;font-weight:800;margin-bottom:18px;}
  .grille{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px;}
  .carte{text-decoration:none;color:inherit;display:flex;flex-direction:column;gap:8px;}
  .carte img{width:100%;aspect-ratio:16/10;object-fit:cover;border-radius:12px;background:var(--tile);display:block;}
  .carte h3{font-size:19px;font-weight:700;}
  .carte p{margin:0;color:var(--ink-soft);font-size:15px;}
  .liste{max-width:820px;margin:0 auto;padding:8px 20px 56px;}
  .ligne{display:grid;grid-template-columns:120px minmax(0,1fr);gap:16px;padding:16px 0;border-bottom:1px solid var(--line);text-decoration:none;color:inherit;}
  .ligne img{width:120px;aspect-ratio:4/3;object-fit:cover;border-radius:10px;background:var(--tile);}
  .ligne h2{font-size:20px;font-weight:700;margin:4px 0;}
  .ligne p{margin:0;color:var(--ink-soft);font-size:15px;}
  @media (max-width:760px){.grille{grid-template-columns:minmax(0,1fr);}.corps{font-size:18px;}.chapo{font-size:18px;}.ligne{grid-template-columns:84px minmax(0,1fr);}.ligne img{width:84px;}}
</style>`;
const MENU = `<nav class="oc-nav" aria-label="Navigation principale">
  <a class="oc-nav-logo" href="../index.html"><img src="../logo.png" alt="L'Objectif Châlonnais — accueil"></a>
  <div class="oc-nav-links">
    <a href="../index.html">Accueil</a>
    <a href="../actus.html" aria-current="page">Actus</a>
    <a href="../agenda.html">Agenda</a>
    <a href="../direct.html">Direct</a>
    <a href="../jeux.html">Jeux</a>
    <a href="../bons-plans.html">Bons plans</a>
    <a href="../galerie.html">Galerie</a>
    <a href="../quiz.html">Quiz</a>
  </div>
</nav>`;
const PIED = `<footer class="oc-pied">
  <span>© L'Objectif Châlonnais · Association loi 1901</span>
  <a href="index.html">Toutes les actus</a>
  <a href="../proposer.html">Envoyez-nous votre info</a>
  <a href="../mentions-legales.html">Mentions légales et confidentialité</a>
</footer>
<script src="../config.js"></script>
<script src="../direct.js" defer></script>
<script src="../compteur.js" defer></script>`;
const EDITEUR = { '@type': 'NewsMediaOrganization', name: 'L\'Objectif Châlonnais', url: SITE, logo: { '@type': 'ImageObject', url: SITE + 'icons/icon-512.png', width: 512, height: 512 } };

function pageArticle(a, { image, typeImage, dims, grande, autres }){
  const url = `${SITE}a/${a.slug}.html`;
  const titre = court(a.titre, 120);
  const desc = resume(a);
  const yt = R.youtubeId(a.lien);
  const lienExterne = a.lien && /^https:\/\//.test(a.lien);
  const ld = {
    '@context': 'https://schema.org', '@type': 'NewsArticle',
    headline: court(a.titre, 110), description: desc,
    datePublished: a.publie_le, dateModified: a.modifie_le || a.publie_le,
    mainEntityOfPage: url, url, inLanguage: 'fr-FR',
    articleSection: RUBRIQUES[a.categorie] || 'Actualité',
    image: grande ? [grande.abs] : [image],
    author: a.auteur ? { '@type': 'Person', name: a.auteur } : EDITEUR,
    publisher: EDITEUR,
    contentLocation: { '@type': 'Place', name: 'Châlons-en-Champagne' }
  };
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(titre)} — L'Objectif Châlonnais</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${esc(url)}">
<meta name="robots" content="max-image-preview:large">
<meta property="og:type" content="article">
<meta property="og:site_name" content="L'Objectif Châlonnais">
<meta property="og:locale" content="fr_FR">
<meta property="og:title" content="${esc(titre)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(url)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:image:secure_url" content="${esc(image)}">
<meta property="og:image:type" content="${typeImage}">${dims ? `
<meta property="og:image:width" content="${dims.w}">
<meta property="og:image:height" content="${dims.h}">` : ''}
<meta property="og:image:alt" content="${esc(titre)}">
<meta property="article:published_time" content="${esc(a.publie_le || '')}">
<meta property="article:modified_time" content="${esc(a.modifie_le || a.publie_le || '')}">
<meta property="article:section" content="${esc(RUBRIQUES[a.categorie] || 'Actualité')}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(titre)}">
<meta name="twitter:description" content="${esc(desc)}">
<meta name="twitter:image" content="${esc(image)}">
<script type="application/ld+json">${json(ld)}</script>
${TETE_COMMUNE}
</head>
<body>
${MENU}
<main>
<article class="article">
  <a class="retour" href="../actus.html">← Toutes les actus</a>
  <div class="meta"><span class="tag">${esc(RUBRIQUES[a.categorie] || 'Actualité')}</span><time datetime="${esc(a.publie_le || '')}">${esc(dateFr(a.publie_le))}</time></div>
  <h1>${esc(a.titre)}</h1>
  ${a.chapo ? `<p class="chapo">${esc(a.chapo)}</p>` : ''}
  ${a.auteur ? `<div class="meta"><span>Par ${esc(a.auteur)}</span></div>` : ''}
  ${grande ? `<figure class="figure"><img src="${esc(grande.src)}" alt="${esc(a.legende || a.titre)}"${grande.w ? ` width="${grande.w}" height="${grande.h}"` : ''} fetchpriority="high">${a.legende ? `<figcaption>${esc(a.legende)}</figcaption>` : ''}</figure>` : ''}
  <div class="corps">${R.rendreContenu(a.contenu)}</div>
  ${yt ? `<p><a class="btn btn-main" href="https://www.youtube.com/watch?v=${esc(yt)}" target="_blank" rel="noopener">▶ Voir la vidéo</a></p>` : (lienExterne ? `<p><a class="btn btn-main" href="${esc(a.lien)}" target="_blank" rel="noopener">${esc(R.libelleLien(a.lien, a.lien_libelle))} →</a></p>` : '')}
  <div class="partage">
    <span>Partager</span>
    <a class="btn" href="https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(url)}" target="_blank" rel="noopener">Facebook</a>
    <a class="btn" href="https://wa.me/?text=${encodeURIComponent(titre + ' ' + url)}" target="_blank" rel="noopener">WhatsApp</a>
    <button class="btn" type="button" id="copier">Copier le lien</button>
  </div>
  <a class="oc-proposer" href="../proposer.html"><span class="oc-proposer-ico" aria-hidden="true">📝</span><span><strong>Une info à partager ?</strong> Envoyez-la à l'équipe.</span><span class="oc-proposer-go">Envoyer →</span></a>
</article>
${autres.length ? `<section class="autres"><h2>À lire aussi</h2><div class="grille">${autres.map(x=> `
  <a class="carte" href="${esc(x.slug)}.html">${extMini(x) ? `<img src="${esc(x.slug)}.${extMini(x)}" alt="" loading="lazy">` : ''}<h3>${esc(x.titre)}</h3>${x.chapo ? `<p>${esc(court(x.chapo, 140))}</p>` : ''}</a>`).join('')}
</div></section>` : ''}
</main>
${PIED}
<script>document.getElementById('copier').onclick=function(e){var b=e.target;(navigator.clipboard?navigator.clipboard.writeText(${json(url)}):Promise.reject()).then(function(){b.textContent='Lien copié ✓';},function(){prompt('Copiez ce lien :',${json(url)});});};</script>
</body>
</html>
`;
}

function pageArchives(liste){
  const url = `${SITE}a/`;
  const ld = { '@context': 'https://schema.org', '@type': 'CollectionPage', name: 'Toutes les actus — L\'Objectif Châlonnais', url, isPartOf: { '@type': 'WebSite', name: 'L\'Objectif Châlonnais', url: SITE } };
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Toutes les actus de Châlons-en-Champagne — L'Objectif Châlonnais</title>
<meta name="description" content="Tous les articles de L'Objectif Châlonnais : actualité locale, sport, culture et événements à Châlons-en-Champagne.">
<link rel="canonical" href="${esc(url)}">
<meta property="og:type" content="website">
<meta property="og:title" content="Toutes les actus — L'Objectif Châlonnais">
<meta property="og:url" content="${esc(url)}">
<meta property="og:image" content="${esc(SITE + 'icons/partage.jpg')}">
<script type="application/ld+json">${json(ld)}</script>
${TETE_COMMUNE}
</head>
<body>
${MENU}
<main class="liste">
  <p class="meta" style="margin-top:32px">ARCHIVES</p>
  <h1 style="font-size:clamp(32px,5vw,46px);font-weight:800;margin:6px 0 18px">Toutes les actus</h1>
  ${liste.map(x=> `<a class="ligne" href="${esc(x.slug)}.html">${extMini(x) ? `<img src="${esc(x.slug)}.${extMini(x)}" alt="" loading="lazy">` : '<span></span>'}<span><span class="meta"><span class="tag">${esc(RUBRIQUES[x.categorie] || 'Actualité')}</span><time datetime="${esc(x.publie_le || '')}">${esc(dateFr(x.publie_le))}</time></span><h2>${esc(x.titre)}</h2>${x.chapo || x.contenu ? `<p>${esc(resume(x))}</p>` : ''}</span></a>`).join('\n  ')}
</main>
${PIED}
</body>
</html>
`;
}

for(const a of actus){
  if(!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(a.slug)) continue;

  // Photo
  let image = SITE + 'icons/partage.jpg', typeImage = 'image/jpeg', dims = { w: 1200, h: 630 };
  // La version réduite (640 px, < 100 Ko) passe partout : WhatsApp ignore les images trop lourdes
  const data = a.miniature || a.photo;
  const m = data && data.match(/^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/]+=*)$/);
  if(m){
    const ext = m[1] === 'jpeg' ? 'jpg' : m[1];
    const fichier = `${a.slug}.${ext}`;
    const contenu = Buffer.from(m[2], 'base64');
    const chemin = path.join(dossier, fichier);
    if(!fs.existsSync(chemin) || !fs.readFileSync(chemin).equals(contenu)) fs.writeFileSync(chemin, contenu);
    gardes.add(fichier);
    // nouvelle adresse dès que la photo change : les applis ne gardent pas l'ancienne en mémoire
    const empreinte = crypto.createHash('sha1').update(contenu).digest('hex').slice(0, 10);
    image = `${SITE}a/${fichier}?v=${empreinte}`;
    typeImage = 'image/' + m[1];
    dims = dimensions(contenu);
  }

  // Grande photo de l'article (affichée dans la page)
  let grande = null;
  const mg = a.photo && a.photo.match(/^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/]+=*)$/);
  if(mg){
    const ext = mg[1] === 'jpeg' ? 'jpg' : mg[1];
    const fichier = `${a.slug}-photo.${ext}`;
    const contenu = Buffer.from(mg[2], 'base64');
    const chemin = path.join(dossier, fichier);
    if(!fs.existsSync(chemin) || !fs.readFileSync(chemin).equals(contenu)) fs.writeFileSync(chemin, contenu);
    gardes.add(fichier);
    const empreinte = crypto.createHash('sha1').update(contenu).digest('hex').slice(0, 10);
    grande = { src: `${fichier}?v=${empreinte}`, abs: `${SITE}a/${fichier}?v=${empreinte}`, ...(dimensions(contenu) || {}) };
  }

  const html = pageArticle(a, { image, typeImage, dims, grande, autres: actus.filter(x=> x.slug !== a.slug).slice(0, 3) });
  const fichierHtml = `${a.slug}.html`;
  const cheminHtml = path.join(dossier, fichierHtml);
  if(!fs.existsSync(cheminHtml) || fs.readFileSync(cheminHtml, 'utf8') !== html) fs.writeFileSync(cheminHtml, html);
  gardes.add(fichierHtml);
}

// Archives : tous les articles
const valides = actus.filter(a=> /^[a-z0-9]+(-[a-z0-9]+)*$/.test(a.slug));
const archives = pageArchives(valides);
const cheminArch = path.join(dossier, 'index.html');
if(!fs.existsSync(cheminArch) || fs.readFileSync(cheminArch, 'utf8') !== archives) fs.writeFileSync(cheminArch, archives);
gardes.add('index.html');

// Plan du site pour Google (sitemap.xml à la racine)
const jour = (iso)=> (iso || '').slice(0, 10);
const PAGES = [['', 'daily', '1.0'], ['actus.html', 'hourly', '0.9'], ['a/', 'daily', '0.8'], ['agenda.html', 'daily', '0.8'], ['direct.html', 'daily', '0.6'],
  ['jeux.html', 'daily', '0.7'], ['bons-plans.html', 'daily', '0.7'], ['galerie.html', 'weekly', '0.6'], ['quiz.html', 'monthly', '0.4'],
  ['proposer.html', 'monthly', '0.4'], ['mentions-legales.html', 'yearly', '0.1']];
const derniere = jour(valides[0] && (valides[0].modifie_le || valides[0].publie_le)) || new Date().toISOString().slice(0, 10);
const plan = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${PAGES.map(([p, f, pr])=> `  <url><loc>${esc(SITE + p)}</loc>${['', 'actus.html', 'a/'].includes(p) ? `<lastmod>${derniere}</lastmod>` : ''}<changefreq>${f}</changefreq><priority>${pr}</priority></url>`).join('\n')}
${valides.map(a=> `  <url><loc>${esc(SITE + 'a/' + a.slug + '.html')}</loc><lastmod>${jour(a.modifie_le || a.publie_le)}</lastmod></url>`).join('\n')}
</urlset>
`;
const cheminPlan = path.join(racine, 'sitemap.xml');
if(!fs.existsSync(cheminPlan) || fs.readFileSync(cheminPlan, 'utf8') !== plan) fs.writeFileSync(cheminPlan, plan);

// Ménage : articles supprimés ou repassés en brouillon
let retires = 0;
for(const f of fs.readdirSync(dossier)){
  if(!gardes.has(f)){ fs.rmSync(path.join(dossier, f)); retires++; }
}
fs.writeFileSync(path.join(dossier, 'LISEZMOI.txt'),
  'Dossier fabriqué automatiquement par le robot « Aperçus des actus » (voir .github/workflows/apercus.yml).\nNe pas modifier à la main : il est regénéré toutes les 15 minutes.\n');

console.log(`${actus.length} article(s) publié(s) · ${retires} fichier(s) retiré(s) · site : ${SITE}`);
