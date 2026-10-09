# Site de L'Objectif Châlonnais

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `index.html` | Accueil : présentation, dernières actus, réseaux, inscription à la lettre, contact |
| `actus.html` | La rubrique Actualités (liste et articles) |
| `rediger.html` | Rédaction des actus, réservée à l'équipe (non visible dans le menu) |
| `actus-rendu.js` | Mise en forme des articles (ne pas modifier) |
| `.github/workflows/apercus.yml`, `scripts/apercus.mjs` | Robot qui fabrique les aperçus de partage des articles (ne pas modifier) |
| `a/` | Pages de partage des articles, fabriquées par le robot (ne pas modifier) |
| `404.html` | Page « introuvable », qui redirige aussi les liens de partage pas encore fabriqués |
| `bons-plans.html` | Le guide des bons plans, avec la carte OpenStreetMap |
| `galerie.html` | La galerie photo, alimentée par les dossiers déposés dans Supabase |
| `quiz.html` | Le quiz « Connais-tu Châlons ? » |
| `config.js` | **Le seul fichier à modifier** : liens des réseaux, contact, dons, base de données |
| `storage.js` | Enregistrement des données (ne pas modifier) |
| `site.css` | Barre de navigation commune |
| `logo.png` | Logo de l'association |
| `envoyer.html` | Page réservée pour envoyer une alerte (non visible dans le menu) |
| `supabase/actus.sql` | Table des actualités, à exécuter dans Supabase après `securite.sql` |
| `supabase/securite.sql` | Protection de la carte des bons plans, à exécuter dans Supabase |
| `push.js`, `supabase/envoyer-notification.ts` | Alertes : abonnement des téléphones et fonction d'envoi à coller dans Supabase |
| `manifest.webmanifest`, `sw.js`, `app.js`, `offline.html`, `icons/` | Mode application : installation sur téléphone et fonctionnement hors ligne (ne pas modifier) |

## 1. Mettre en ligne sur GitHub Pages

1. Sur GitHub, crée un dépôt (par ex. `objectif-chalonnais`).
2. Dépose tous les fichiers du dossier à la racine du dépôt (bouton *Add file → Upload files*).
3. *Settings → Pages* : source *Deploy from a branch*, branche `main`, dossier `/ (root)`.
4. Le site sera en ligne à l'adresse `https://yohan51.github.io/objectif-chalonnais/` après une minute ou deux.

Plus tard, tu pourras brancher un nom de domaine à vous (ex. `lobjectifchalonnais.fr`) dans la même page *Settings → Pages*.

## 2. Personnaliser `config.js`

- **Réseaux** : vérifie les adresses TikTok, Instagram et YouTube (elles sont pré-remplies au hasard d'un nom probable : remplace-les par les vraies).
- **dons** : colle le lien HelloAsso quand la collecte sera ouverte, le bouton « Soutenir l'association » apparaîtra.

## 3. Rendre les bons plans partagés (Supabase, gratuit)

Sans cette étape, le site fonctionne, mais chaque visiteur ne voit que les bons plans d'origine et ceux qu'il a ajoutés lui-même, et la lettre d'information ne garde aucune adresse.

1. Crée un compte sur [supabase.com](https://supabase.com) puis un projet (région *Europe*).
2. Menu *SQL Editor* → *New query*, colle ce bloc puis *Run* :

```sql
-- Bons plans, commentaires, notes, photos, signalements
create table kv (
  key text primary key,
  value text not null,
  updated_at timestamptz default now()
);
alter table kv enable row level security;
create policy "lecture publique" on kv for select using (true);
create policy "ajout public"     on kv for insert with check (true);
create policy "mise a jour"      on kv for update using (true);

-- Inscriptions à la lettre (lisibles seulement depuis ton tableau de bord Supabase)
create table newsletter (
  id bigserial primary key,
  email text not null unique,
  created_at timestamptz default now()
);
alter table newsletter enable row level security;
create policy "inscription publique" on newsletter for insert with check (true);
```

3. Menu *Project Settings → API* : copie la *Project URL* et la clé *anon public*, puis colle-les dans `config.js` (`supabaseUrl` et `supabaseCle`).
4. Les adresses inscrites se retrouvent dans *Table Editor → newsletter*, exportables en CSV pour Brevo, Mailchimp, etc.

## 4. La galerie photo

### Mise en place (une seule fois)

Dans Supabase, *SQL Editor → New query*, colle ce bloc puis *Run* :

```sql
-- Espace de stockage public pour les photos
insert into storage.buckets (id, name, public)
values ('galerie', 'galerie', true)
on conflict (id) do nothing;

-- Le site peut lister les albums et les photos (lecture seule)
create policy "galerie lecture publique"
on storage.objects for select
using (bucket_id = 'galerie');
```

Seul toi, depuis le tableau de bord Supabase, peux ajouter ou supprimer des photos.

### Ajouter un album

1. Supabase → *Storage* → *galerie* → *Create folder*.
2. Nomme le dossier avec la date puis le titre : `2026-10-04 Foire de Châlons`. Le site affiche alors « Foire de Châlons · 4 octobre 2026 ». Pour un album sans jour précis : `2025-12 Marché de Noël`. Les albums les plus récents s'affichent en premier.
3. Ouvre le dossier et glisse-y les photos (JPG, PNG ou WebP).

Les photos apparaissent sur le site immédiatement, dans l'ordre alphabétique de leur nom de fichier. La première sert de couverture à l'album.

### Préparer les photos

- **Redimensionne-les avant l'envoi** : 2 000 pixels sur le grand côté, qualité JPG 80 %. Une photo pèse alors 300 à 600 Ko au lieu de 5 à 10 Mo. Le site se charge vite et l'offre gratuite (1 Go) contient 2 000 à 3 000 photos.
- Outils gratuits pour redimensionner par lots : *Aperçu* sur Mac (Outils → Ajuster la taille), *XnConvert* sur Windows et Mac, ou l'export de Lightroom.
- **Droit à l'image** : évite les gros plans de personnes identifiables sans leur accord, surtout les enfants. Les photos de foule et d'ambiance ne posent en général pas de problème.

## 5. L'application sur téléphone

Le site s'installe comme une application, sans passer par les stores :

- **Android (Chrome)** : une invitation « Installer » apparaît en bas de l'accueil. Sinon : menu ⋮ → *Installer l'application*.
- **iPhone (Safari)** : bouton *Partager* → *Sur l'écran d'accueil*. L'accueil affiche ce mode d'emploi aux visiteurs sur iPhone.
- Un lien « Installer l'application » est aussi en bas de l'accueil.

Une fois installée, l'application s'ouvre en plein écran avec l'icône de l'œil. Les pages déjà visitées restent consultables sans connexion. Chaque mise à jour du site sur GitHub arrive automatiquement dans l'application, au prochain lancement avec une connexion.

Attention : le mode application ne fonctionne qu'en ligne sur GitHub Pages (adresse en `https://`), pas en ouvrant les fichiers depuis ton ordinateur.

## 6. Les alertes (notifications)

### Mise en place (une seule fois)

1. **Table des abonnés** : Supabase → *SQL Editor* → *New query* :

```sql
create table if not exists public.push_subscriptions (
  endpoint text primary key,
  p256dh text not null,
  auth text not null,
  created_at timestamptz default now()
);
alter table push_subscriptions enable row level security;
create policy "abonnement public" on push_subscriptions for insert with check (true);
grant insert on push_subscriptions to anon, authenticated;
notify pgrst, 'reload schema';
```

2. **Secrets** : *Edge Functions* → *Secrets* → ajoute :
   - `VAPID_PUBLIC_KEY` et `VAPID_PRIVATE_KEY` (les deux clés données par Claude ; la clé privée ne doit jamais être publiée sur GitHub)
   - `VAPID_SUBJECT` : `mailto:lobjectifchalonnais@gmail.com`
   - `CODE_ENVOI` : un code de ton choix, que tu taperas pour envoyer une alerte

3. **Fonction d'envoi** : *Edge Functions* → *Deploy a new function* → *Via Editor*. Nom : `envoyer-notification`. Remplace tout le code par le contenu de `supabase/envoyer-notification.ts`, puis *Deploy*.

4. Dans les réglages de la fonction (*Details*), **désactive « Enforce JWT verification »** (ou « Verify JWT ») et enregistre. C'est ton code d'envoi qui protège la fonction.

### Envoyer une alerte

1. Ouvre `…/objectif-chalonnais/envoyer.html` (garde cette adresse en favori, elle n'est pas dans le menu).
2. Tape ton code, un titre, un message, et choisis ce qui s'ouvre au toucher : une page du site, votre compte TikTok, Instagram ou YouTube (liens repris de `config.js`), ou une vidéo précise (colle son lien de partage).
3. *M'envoyer un test* pour vérifier sur ton téléphone, puis *Envoyer à tous*.

Les visiteurs s'abonnent avec le bouton « Recevoir les alertes » de l'accueil. Sur iPhone, ils doivent d'abord installer l'application.

## 7. Sécurité de la carte des bons plans

Les visiteurs peuvent **ajouter** (bons plans, notes, commentaires, photos, signalements) mais ni effacer ni modifier ce qui existe. Seul le code modérateur permet de supprimer, publier ou marquer un partenaire, et ce code est vérifié par Supabase, plus dans la page.

### Installation (une seule fois, à refaire seulement si Claude te fournit une nouvelle version)

1. *SQL Editor* → *New query* → colle tout le fichier `supabase/securite.sql` → *Run*.
2. Choisis ton code modérateur (nouvelle requête) :

```sql
update oc_private.reglages
set code_moderateur = extensions.crypt('TON-NOUVEAU-CODE', extensions.gen_salt('bf'))
where id = 1;
```

Pour changer de code plus tard, relance simplement cette requête.

### En cas de problème : revenir en arrière

Chaque enregistrement est gardé (les 100 dernières versions des bons plans). Pour voir les versions :

```sql
select id, enregistre_le at time zone 'Europe/Paris' as quand, par_moderateur
from oc_private.historique
where cle = 'chalons-bons-plans'
order by id desc limit 30;
```

Puis, pour restaurer une version (remplace 123 par son numéro) :

```sql
select oc_private.restaurer(123);
```

### Limites anti-abus

- 40 enregistrements par appareil en 10 minutes (le modérateur n'est pas limité).
- 2 nouveaux bons plans, 3 commentaires ou 3 notes au maximum par envoi.
- Code modérateur : bloqué 15 minutes après 8 essais ratés.
- Lettre et alertes : 10 inscriptions par heure et par appareil, adresses vérifiées.

## 8. Les actualités

### Installation (une seule fois)

*SQL Editor* → *New query* → colle tout le fichier `supabase/actus.sql` → *Run*. (Il faut avoir installé `securite.sql` avant.)

### Écrire un article

1. Ouvre `…/objectif-chalonnais/rediger.html` (garde l'adresse en favori, elle n'est pas dans le menu) et tape le **code modérateur**.
2. *Nouvel article* : titre, rubrique, chapô (le résumé affiché dans la liste), photo, texte.
3. Mise en forme du texte : une ligne vide entre deux paragraphes, `## ` en début de ligne pour un intertitre, `- ` pour une liste, `**texte**` pour du gras. Les boutons au-dessus du texte le font pour toi. Les liens `https://…` deviennent cliquables.
4. *Vidéo ou lien* : un lien YouTube affiche la vidéo dans l'article ; un lien TikTok, Instagram ou autre affiche un bouton.
5. *Publication* : brouillon (invisible), publier maintenant, ou programmer une date.
6. *Aperçu* pour vérifier, puis *Enregistrer*. Après publication, le bouton *Annoncer par une alerte* ouvre la page d'alerte déjà remplie.

La photo est redimensionnée automatiquement : envoie-la directement depuis ton téléphone. Ce que tu tapes pour un nouvel article est gardé sur l'appareil tant qu'il n'est pas enregistré.

Pour modifier ou supprimer un article, clique dessus dans la liste de gauche. L'adresse d'un article ne change pas si tu modifies son titre : les liens déjà partagés restent valables.

## 9. Aperçus de partage des articles

Le bouton *Partager* d'un article donne un lien en `…/a/nom-de-l-article.html`. Dans WhatsApp, Facebook ou Messenger, ce lien affiche le titre, le résumé et la photo de l'article, puis ouvre l'article.

Ces pages sont fabriquées par un robot GitHub toutes les 15 minutes (onglet *Actions* → *Aperçus des actus*). Pour l'installer, une seule fois : sur GitHub, *Add file* → *Create new file*, nom `.github/workflows/apercus.yml`, colle le contenu du fichier, puis *Commit changes*. Pour lancer le robot tout de suite : *Actions* → *Aperçus des actus* → *Run workflow*.

Si tu passes un jour à un nom de domaine à toi, ajoute-le dans *Settings* → *Secrets and variables* → *Actions* → onglet *Variables* : nom `SITE_URL`, valeur `https://ton-domaine.fr/`.

## Bon à savoir

- **Modération** : bouton *Modération* de la carte, avec le code choisi à la section 7.
- **Ajouter un lieu depuis la carte** : un clic (ou un appui) sur la carte propose « Ajouter un bon plan ici », avec le quartier présélectionné.
- **Sauvegardes** : en plus de l'historique automatique, exporte de temps en temps la table `kv` (*Table Editor → Export*).
- **Sauvegarde automatique** : voir la section 7 pour revenir à une version précédente.
