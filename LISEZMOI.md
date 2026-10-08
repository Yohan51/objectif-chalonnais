# Site de L'Objectif Châlonnais

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `index.html` | Accueil : présentation, réseaux, inscription à la lettre, contact |
| `bons-plans.html` | Le guide des bons plans, avec la carte OpenStreetMap |
| `galerie.html` | La galerie photo, alimentée par les dossiers déposés dans Supabase |
| `quiz.html` | Le quiz « Connais-tu Châlons ? » |
| `config.js` | **Le seul fichier à modifier** : liens des réseaux, contact, dons, base de données |
| `storage.js` | Enregistrement des données (ne pas modifier) |
| `site.css` | Barre de navigation commune |
| `logo.png` | Logo de l'association |
| `envoyer.html` | Page réservée pour envoyer une alerte (non visible dans le menu) |
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
create table push_subscriptions (
  endpoint text primary key,
  p256dh text not null,
  auth text not null,
  created_at timestamptz default now()
);
alter table push_subscriptions enable row level security;
create policy "abonnement public" on push_subscriptions for insert with check (true);
```

2. **Secrets** : *Edge Functions* → *Secrets* → ajoute :
   - `VAPID_PUBLIC_KEY` et `VAPID_PRIVATE_KEY` (les deux clés données par Claude ; la clé privée ne doit jamais être publiée sur GitHub)
   - `VAPID_SUBJECT` : `mailto:lobjectifchalonnais@gmail.com`
   - `CODE_ENVOI` : un code de ton choix, que tu taperas pour envoyer une alerte

3. **Fonction d'envoi** : *Edge Functions* → *Deploy a new function* → *Via Editor*. Nom : `envoyer-notification`. Remplace tout le code par le contenu de `supabase/envoyer-notification.ts`, puis *Deploy*.

4. Dans les réglages de la fonction (*Details*), **désactive « Enforce JWT verification »** (ou « Verify JWT ») et enregistre. C'est ton code d'envoi qui protège la fonction.

### Envoyer une alerte

1. Ouvre `…/objectif-chalonnais/envoyer.html` (garde cette adresse en favori, elle n'est pas dans le menu).
2. Tape ton code, un titre, un message, choisis la page à ouvrir.
3. *M'envoyer un test* pour vérifier sur ton téléphone, puis *Envoyer à tous*.

Les visiteurs s'abonnent avec le bouton « Recevoir les alertes » de l'accueil. Sur iPhone, ils doivent d'abord installer l'application.

## Bon à savoir

- **Modération** : le code d'accès reste celui du guide d'origine. Pour le changer, demande un nouveau code chiffré à Claude et remplace `ADMIN_PASSWORD_HASH` dans `bons-plans.html`.
- **Ajouter un lieu depuis la carte** : un clic (ou un appui) sur la carte propose « Ajouter un bon plan ici », avec le quartier présélectionné.
- **Sauvegardes** : pense à exporter de temps en temps la table `kv` depuis Supabase (*Table Editor → Export*).
- **Sécurité** : comme dans la version d'origine, l'ensemble des bons plans est enregistré d'un bloc et la clé publique permet d'écrire dans la table. C'est suffisant pour démarrer ; si le site devient une cible de vandalisme, il faudra passer à des comptes contributeurs.
