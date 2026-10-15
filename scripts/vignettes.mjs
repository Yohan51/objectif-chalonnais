// =====================================================================
// Galerie rapide — L'Objectif Châlonnais
//
// Lancé par GitHub toutes les 15 minutes (.github/workflows/apercus.yml).
//  1. Pour chaque photo de la galerie (Supabase Storage), fabrique deux
//     versions légères au format WebP, rangées dans le dossier _vignettes :
//       <album>/<photo>.m.webp  → 800 px, pour les grilles (≈ 60–100 Ko)
//       <album>/<photo>.g.webp  → 2000 px, pour la visionneuse (≈ 250–450 Ko)
//     Si la photo fait déjà 2000 px ou moins (cas des photos envoyées par la
//     page « Ajouter des photos »), seule la petite version est fabriquée :
//     la visionneuse affiche directement la photo (v: 2 dans galerie.json).
//     Les originaux ne sont jamais modifiés.
//  2. Écrit data/galerie.json : la liste des albums et des photos, lue par
//     la galerie et l'accueil en une seule fois (au lieu d'une requête par album).
//
// Les vignettes demandent la clé secrète de Supabase, rangée dans GitHub :
// Settings → Secrets and variables → Actions → New repository secret
// nom SUPABASE_SERVICE_KEY. Sans elle, seule la liste (2.) est fabriquée.
// =====================================================================
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const racine = process.cwd();
const bac = { window: {} };
try{ vm.runInNewContext(fs.readFileSync(path.join(racine, 'config.js'), 'utf8'), bac); }catch(e){}
const cfg = bac.window.OC_CONFIG || {};
const SUPABASE = (process.env.SUPABASE_URL || cfg.supabaseUrl || '').replace(/\/+$/, '');
const CLE_PUBLIQUE = process.env.SUPABASE_CLE || cfg.supabaseCle || '';
const CLE_SECRETE = process.env.SUPABASE_SERVICE_KEY || '';
const BUCKET = cfg.galerieBucket || 'galerie';
const DOSSIER_V = '_vignettes';
const MAX_PAR_PASSAGE = parseInt(process.env.VIGNETTES_MAX || '200', 10);
const IMG = /\.(jpe?g|png|webp|avif|gif|heic|heif|tiff?)$/i;
const TAILLES = { m: { long: 800, qualite: 72 }, g: { long: 2000, qualite: 80 } };
const fichier = path.join(racine, 'data', 'galerie.json');

if(!SUPABASE || !CLE_PUBLIQUE){ console.log('Supabase non configuré dans config.js : rien à faire.'); process.exit(0); }

function entetes(cle){ const h = { apikey: cle }; if(cle.startsWith('eyJ')) h.Authorization = 'Bearer ' + cle; return h; }
const cleLecture = CLE_SECRETE || CLE_PUBLIQUE;
const enc = (p)=> p.split('/').map(encodeURIComponent).join('/');
export const nomVignette = (album, photo, t)=> `${DOSSIER_V}/${album}/${photo.replace(/\.[^.]+$/, '')}.${t}.webp`;

async function lister(prefix){
  const out = [];
  for(let offset = 0; ; offset += 1000){
    const r = await fetch(`${SUPABASE}/storage/v1/object/list/${BUCKET}`, {
      method: 'POST', headers: { ...entetes(cleLecture), 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } })
    });
    if(!r.ok) throw new Error(`liste « ${prefix} » : ${r.status} ${await r.text()}`);
    const lignes = await r.json();
    out.push(...lignes);
    if(lignes.length < 1000) break;
  }
  return out;
}
const estDossier = (o)=> o.id === null || (!o.metadata && !IMG.test(o.name));

async function main(){
  // ---------- Inventaire ----------
  const albums = (await lister('')).filter(estDossier).map(o=> o.name).filter(n=> !n.startsWith('_') && !n.startsWith('.')).sort();
  const inventaire = {};
  for(const a of albums){
    inventaire[a] = (await lister(a + '/')).filter(o=> !estDossier(o) && IMG.test(o.name) && !o.name.startsWith('.')).map(o=> o.name);
  }
  let ancien = {};
  try{ ancien = JSON.parse(fs.readFileSync(fichier, 'utf8')).albums || {}; }catch(e){}

  // ---------- Vignettes ----------
  const faites = {};      // album -> Set des photos qui ont leurs versions légères
  const dims = {};        // album/photo -> [w, h]
  for(const [a, liste] of Object.entries(ancien)) for(const p of liste){ if(p.w) dims[a + '/' + p.n] = [p.w, p.h]; }
  const grandes = {};     // album -> Set des photos qui ont aussi la grande version
  const WEB = /\.(jpe?g|png|webp|gif|avif)$/i;   // formats que tous les navigateurs affichent
  const dejaLegere = (k)=> WEB.test(k) && !!(dims[k] && dims[k][0] && Math.max(dims[k][0], dims[k][1]) <= TAILLES.g.long);
  let sharp = null;
  if(CLE_SECRETE){
    try{ sharp = (await import('sharp')).default; }catch(e){ console.log('Module sharp absent : vignettes ignorées.'); }
  }else{
    console.log('Pas de clé SUPABASE_SERVICE_KEY dans GitHub : liste mise à jour, vignettes non fabriquées.');
  }
  let traitees = 0, erreurs = 0;
  for(const a of albums){
    let existantes = new Set();
    try{ existantes = new Set((await lister(`${DOSSIER_V}/${a}/`)).map(o=> o.name)); }catch(e){}
    const aLa = (p, t)=> existantes.has(path.posix.basename(nomVignette(a, p, t)));
    faites[a] = new Set(inventaire[a].filter(p=> aLa(p, 'm') && (aLa(p, 'g') || dejaLegere(a + '/' + p))));
    grandes[a] = new Set(inventaire[a].filter(p=> aLa(p, 'g')));
    if(!sharp) continue;
    for(const p of inventaire[a]){
      if(faites[a].has(p)) continue;
      if(traitees >= MAX_PAR_PASSAGE) break;
      traitees++;
      try{
        const r = await fetch(`${SUPABASE}/storage/v1/object/public/${BUCKET}/${enc(a + '/' + p)}`);
        if(!r.ok) throw new Error('téléchargement ' + r.status);
        const brut = Buffer.from(await r.arrayBuffer());
        const base = sharp(brut, { failOn: 'none' }).rotate();     // rotate() : respecte l'orientation des téléphones
        const meta = await base.clone().metadata();
        const tourne = (meta.orientation || 1) >= 5;
        dims[a + '/' + p] = tourne ? [meta.height, meta.width] : [meta.width, meta.height];
        const legere = WEB.test(p) && meta.width > 0 && Math.max(meta.width, meta.height || 0) <= TAILLES.g.long;
        for(const [t, { long, qualite }] of Object.entries(TAILLES)){
          if(t === 'g' && legere) continue;      // la photo sert directement de grande version
          const sortie = await base.clone()
            .resize({ width: long, height: long, fit: 'inside', withoutEnlargement: true })
            .webp({ quality: qualite, effort: 4 })
            .toBuffer();
          const u = await fetch(`${SUPABASE}/storage/v1/object/${BUCKET}/${enc(nomVignette(a, p, t))}`, {
            method: 'POST',
            headers: { ...entetes(CLE_SECRETE), 'Content-Type': 'image/webp', 'x-upsert': 'true', 'Cache-Control': 'max-age=31536000' },
            body: sortie
          });
          if(!u.ok) throw new Error(`envoi ${t} : ${u.status} ${await u.text()}`);
        }
        faites[a].add(p);
        if(!legere) grandes[a].add(p);
        console.log(`✓ ${a}/${p} (${Math.round(brut.length / 1024)} Ko)`);
      }catch(e){
        erreurs++;
        console.log(`✗ ${a}/${p} : ${e.message}`);
      }
    }
  }

  // ---------- Titres avec accents (fichier _album.json créé par la page « Ajouter des photos ») ----------
  const titres = {};
  for(const a of albums){
    try{
      const r = await fetch(`${SUPABASE}/storage/v1/object/public/${BUCKET}/${enc(a + '/_album.json')}`);
      if(r.ok){ const j = await r.json(); if(j && typeof j.titre === 'string' && j.titre.trim()) titres[a] = j.titre.trim().slice(0, 100); }
    }catch(e){}
  }

  // ---------- Liste pour le site ----------
  const sortie = {};
  for(const a of albums){
    sortie[a] = inventaire[a].map(p=>{
      const o = { n: p };
      if(faites[a] && faites[a].has(p)) o.v = grandes[a].has(p) ? 1 : 2;
      const d = dims[a + '/' + p]; if(d && d[0]){ o.w = d[0]; o.h = d[1]; }
      return o;
    });
  }
  const json = JSON.stringify({ bucket: BUCKET, vignettes: DOSSIER_V, titres, albums: sortie });
  let avant = '';
  try{ const x = JSON.parse(fs.readFileSync(fichier, 'utf8')); delete x.maj; avant = JSON.stringify(x); }catch(e){}
  if(avant !== json){
    fs.mkdirSync(path.dirname(fichier), { recursive: true });
    fs.writeFileSync(fichier, JSON.stringify({ maj: new Date().toISOString(), ...JSON.parse(json) }) + '\n');
    console.log('data/galerie.json mis à jour.');
  }
  const total = Object.values(inventaire).reduce((s, l)=> s + l.length, 0);
  const pretes = Object.values(faites).reduce((s, l)=> s + l.size, 0);
  console.log(`${albums.length} album(s), ${total} photo(s), ${pretes} avec vignettes · ${traitees - erreurs} fabriquée(s) à ce passage${erreurs ? `, ${erreurs} erreur(s)` : ''}.`);
}

if(import.meta.url === `file://${process.argv[1]}`){
  main().catch(e=>{ console.log('Galerie : ' + e.message); });
}
