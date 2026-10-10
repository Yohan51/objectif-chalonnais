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
| `bons-plans.html` | Le guide des bons plans (liste, filtres, notes, commentaires) |
| `galerie.html` | La galerie photo, alimentée par les dossiers déposés dans Supabase |
| `quiz.html` | Le quiz « Connais-tu Châlons ? » |
| `stats.html`, `compteur.js`, `supabase/compteur.sql` | Compteur de visites anonyme et page des statistiques de l'équipe |
| `chat.js`, `messages.html`, `supabase/chat.sql` | La bulle « Discuter » (discussion publique et messages à l'équipe) et la page de l'équipe pour répondre et modérer |
| `equipe.html`, `equipe.js` | L'espace équipe : une seule connexion pour tous les outils de l'équipe |
| `membres.html`, `supabase/membres.sql` | Gestion des membres de l'équipe : un code personnel par membre, droits limités |
| `mentions-legales.html` | Mentions légales et politique de confidentialité (lien en bas de chaque page) |
| `jeux.html` | Les jeux concours : participation des abonnés et gagnants |
| `tirage.html`, `qrcode.min.js` | Outil de l'équipe : créer les jeux, tirage au sort, certificats (non visible dans le menu) |
| `supabase/jeux.sql` | Tables des jeux concours, à exécuter dans Supabase après `actus.sql` |
| `config.js` | **Le seul fichier à modifier** : liens des réseaux, contact, dons, base de données |
| `storage.js` | Enregistrement des données (ne pas modifier) |
| `site.css` | Barre de navigation commune |
| `logo.png` | Logo de l'association |
| `envoyer.html` | Page réservée pour envoyer une alerte (non visible dans le menu) |
| `supabase/actus.sql` | Table des actualités, à exécuter dans Supabase après `securite.sql` |
| `supabase/securite.sql` | Protection du guide des bons plans, à exécuter dans Supabase |
| `push.js`, `supabase/envoyer-notification.ts` | Alertes : abonnement des téléphones et fonction d'envoi à coller dans Supabase |
| `manifest.webmanifest`, `sw.js`, `app.js`, `offline.html`, `icons/` | Mode application : installation sur téléphone et fonctionnement hors ligne (ne pas modifier) |

## 1. Mettre en ligne sur GitHub Pages

1. Sur GitHub, crée un dépôt (par ex. `objectif-chalonnais`).
2. Dépose tous les fichiers du dossier à la racine du dépôt (bouton *Add file → Upload files*).
3. *Settings → Pages* : source *Deploy from a branch*, branche `main`, dossier `/ (root)`.
4. Le site est en ligne à l'adresse `https://lobjectifchalonnais.fr/` (domaine relié dans *Settings → Pages → Custom domain*, DNS chez IONOS : 4 enregistrements A vers 185.199.108.153 / 109.153 / 110.153 / 111.153 et un CNAME `www` vers `yohan51.github.io`).

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

**Sur l'accueil** : les 6 derniers albums s'affichent sous la grande photo de tête.

### La grande photo de l'accueil

Une grande photo occupe toute la largeur du haut de l'accueil, avec le titre par-dessus.

- **Pour choisir ta photo** : sur GitHub, ouvre le dossier `photos`, puis *Add file → Upload files* et dépose ta photo nommée exactement `une.jpg`. Pour en changer, dépose une nouvelle photo du même nom : elle remplace l'ancienne.
- **Format conseillé** : en largeur, environ 2 400 pixels de large, moins de 500 Ko. Le côté gauche est assombri pour que le texte reste lisible ; un sujet placé à droite ou au centre ressort le mieux. Sur téléphone, la photo est recadrée en hauteur : garde le sujet principal au centre.
- **Sans photo choisie**, l'accueil affiche la couverture de l'album le plus récent de la galerie, avec un lien vers l'album en bas à droite. Pour choisir cette couverture, renomme la photo voulue pour qu'elle passe en premier, par exemple `00-couverture.jpg`.

### Les illustrations des 4 cartes de l'accueil

Les cartes *Bons plans*, *Galerie*, *Jeux concours* et *Quiz* sont illustrées par des dessins aux couleurs du site. Pour mettre une de tes photos à la place, dépose-la dans le dossier `photos` sous le nom `bons-plans.jpg`, `galerie.jpg`, `jeux.jpg` ou `quiz.jpg` (format paysage, environ 1 200 × 600 pixels, moins de 250 Ko). Pour revenir au dessin, supprime simplement le fichier. La carte *Galerie* n'a pas besoin de photo : sans `galerie.jpg`, elle affiche automatiquement une photo de tes derniers albums.

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

3. **Code** : *SQL Editor* → colle `supabase/alertes-code.sql` → *Run*. Le code demandé pour envoyer une alerte est ton **code modérateur**.

4. **Fonction d'envoi** : *Edge Functions* → *Deploy a new function* → *Via Editor*. Nom : `envoyer-notification`. Remplace tout le code par le contenu de `supabase/envoyer-notification.ts`, puis *Deploy*.

5. Dans les réglages de la fonction (*Details*), **désactive « Enforce JWT verification »** (ou « Verify JWT ») et enregistre. C'est ton code modérateur qui protège la fonction.

### Envoyer une alerte

1. Ouvre `https://lobjectifchalonnais.fr/envoyer.html` (garde cette adresse en favori, elle n'est pas dans le menu).
2. Tape ton code modérateur, un titre, un message, et choisis ce qui s'ouvre au toucher : une page du site, votre compte TikTok, Instagram ou YouTube (liens repris de `config.js`), ou une vidéo précise (colle son lien de partage).
3. *M'envoyer un test* pour vérifier sur ton téléphone, puis *Envoyer à tous*.

Les visiteurs s'abonnent avec le bouton « Recevoir les alertes » de l'accueil. Sur iPhone, ils doivent d'abord installer l'application.

## 7. Sécurité du guide des bons plans

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

1. Ouvre `https://lobjectifchalonnais.fr/rediger.html` (garde l'adresse en favori, elle n'est pas dans le menu) et tape le **code modérateur**.
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

Le robot lit automatiquement le nom de domaine dans le fichier `CNAME` du dépôt (créé par GitHub quand on règle *Settings → Pages → Custom domain*). Ne supprime pas ce fichier.

## 10. Jeux concours et tirage au sort

Les abonnés participent sur la page **Jeux** du site (prénom, nom, e-mail, téléphone). Condition : avoir activé les alertes sur l'appareil. Sur iPhone, cela veut dire passer par l'application installée. Une seule participation par e-mail et par numéro.

### Installation (une seule fois)

*SQL Editor* → *New query* → colle tout le fichier `supabase/jeux.sql` → *Run*. (Il faut avoir installé `securite.sql` et `actus.sql` avant.)

### Créer un jeu

1. Ouvre `https://lobjectifchalonnais.fr/tirage.html` (garde-la en favori) et tape le **code modérateur**.
2. *+ Nouveau jeu* : titre, lot, présentation, date de fin, nombre de gagnants, photo, conditions particulières.
3. Coche *Visible sur le site*, puis *Enregistrer le jeu*. Le lien *Annoncer ce jeu par une alerte* ouvre la page d'alerte déjà remplie.

Le règlement (gratuit, majeurs résidant en France, une participation par personne, données effacées sous 3 mois) est affiché automatiquement sur la page du jeu.

### Faire le tirage

1. Quand le jeu est terminé, il passe en *À tirer* : touche *Tirage*.
2. Choisis l'animation (défilement, rouleau ou roue) et lance le tirage. L'animation n'affiche que « Prénom N. » : tu peux la filmer pour TikTok ou Instagram.
3. Les coordonnées complètes des gagnants s'affichent pour les contacter, avec le certificat et le QR code de retrait.
4. *Publier les gagnants sur le site* : la page Jeux affiche « Prénom N. ». Ensuite *Annoncer par une alerte*.
5. Une fois les lots remis : *Effacer les coordonnées des participants*. Sinon, elles sont effacées automatiquement 3 mois après le tirage.

L'onglet *Tirage libre* reprend l'ancien outil : tu colles les commentaires d'une publication Instagram ou TikTok (ou une liste de noms) et tu tires au sort de la même façon, sans rien publier sur le site.

## 11. Mentions légales

La page `mentions-legales.html` reprend l'éditeur, le directeur de publication, les hébergeurs et la politique de confidentialité. Deux informations facultatives peuvent s'y ajouter depuis `config.js`, en ajoutant ces lignes juste après la ligne `contact` :

```
  telephone: '06 12 34 56 78',   // numéro de l'association (demandé par la loi)
  rna: 'W511234567',             // numéro RNA de l'association, s'il existe
```

Pense à mettre à jour la date en bas de la page si tu changes la façon dont le site utilise les données (nouveau formulaire, nouveau service…).

## 12. Compteur de visites

### Installation (une seule fois)

*SQL Editor* → *New query* → colle tout le fichier `supabase/compteur.sql` → *Run*.

### Ce qu'il fait

- Chaque page vue du site est comptée, jour par jour, sans cookie ni donnée personnelle. Une « visite », c'est une personne qui ouvre le site, quel que soit le nombre de pages qu'elle regarde.
- **Statistiques détaillées** : `https://lobjectifchalonnais.fr/stats.html` avec le code modérateur (visites du jour, de la semaine, du mois, graphique, pages les plus vues).
- **Sur l'accueil**, le total s'affiche sous les boutons (« 12 345 visites sur le site depuis le… ») dès qu'il dépasse 1 000, pour ne pas afficher un petit chiffre au lancement.
- Les téléphones et ordinateurs de l'équipe ne sont pas comptés dès qu'on s'y est connecté une fois avec le code (rédaction, alertes, jeux ou statistiques).

Réglages facultatifs dans `config.js`, après la ligne `contact` :

```
  compteurPublic: false,      // pour ne jamais afficher le total sur l'accueil
  compteurMinimum: 5000,      // pour l'afficher seulement à partir de 5 000 visites
```

## 13. La discussion et les messages

Une bulle **💬 Discuter** apparaît en bas à droite des pages du site, avec deux onglets :

- **La discussion** : un salon public où les Chalonnais échangent. Tout le monde peut lire ; pour écrire, il faut avoir activé les alertes (c'est le filtre anti-spam) et choisir un pseudo. Les liens vers d'autres sites, les insultes et les pseudos qui imitent l'équipe sont refusés. Un message signalé 3 fois est masqué automatiquement. Les messages sont effacés au bout de 90 jours.
- **Écrire à l'équipe** : un message privé à l'association. Le visiteur retrouve la conversation et votre réponse dans la bulle, à sa prochaine visite (une pastille rouge le prévient). S'il a laissé son e-mail, vous pouvez aussi lui répondre par mail.

### Installation (une seule fois)

*SQL Editor* → *New query* → colle tout le fichier `supabase/chat.sql` → *Run*. (Il faut avoir installé `securite.sql` et les alertes avant.)

### Répondre et modérer

`https://lobjectifchalonnais.fr/messages.html`, avec le code modérateur :
- **Messages reçus** : les conversations non lues ont une pastille rouge. Cliquez, répondez, puis *Marquer comme traitée*.
- **Modérer la discussion** : masquez ou rétablissez un message, ou **bannissez** son auteur (il ne pourra plus écrire et tous ses messages sont masqués).

Pas de notification automatique pour l'instant : passez sur cette page une ou deux fois par jour (le nombre de messages non lus s'affiche dans le titre de l'onglet).

La liste des mots refusés se complète dans Supabase : *Table Editor* → schéma `oc_private` → table `salon_mots` → *Insert row*.

Pour retirer la bulle du site : ajoute `chat: false,` dans `config.js`, après la ligne `contact`.

## 14. L'espace équipe (une seule connexion)

Garde en favori **`https://lobjectifchalonnais.fr/equipe.html`** (lien aussi en bas de l'accueil). Tu te connectes une fois avec le code modérateur, puis tous les outils s'ouvrent sans redemander le code : actus, jeux concours, alertes, messages, statistiques et modération des bons plans. Chaque case indique en direct ce qui t'attend (messages non lus, jeux à tirer au sort, événements à valider…).

- **Rester connecté sur cet appareil** (coché par défaut) : le code est retenu 30 jours sur ce téléphone ou cet ordinateur. Décoche-la sur un ordinateur partagé : tu seras alors déconnecté à la fermeture du navigateur.
- **Se déconnecter**, depuis n'importe quel outil, déconnecte de tous les outils sur cet appareil.
- Si tu changes le code modérateur, chaque appareil redemandera simplement le nouveau.

## 15. Les membres de l'équipe

Tu restes l'**administrateur principal** : ton code modérateur donne tous les droits. Chaque membre de l'équipe reçoit son **propre code**, que tu peux suspendre ou retirer à tout moment.

### Installation (une seule fois)

*SQL Editor* → *New query* → colle tout le fichier `supabase/membres.sql` → *Run*. Exécute-le **en dernier**, après les autres fichiers (et à nouveau si tu relances un jour un autre fichier SQL).

### Donner un accès

Espace équipe → case **L'équipe** (visible par toi seul) → prénom, *générer* un code, *Ajouter*. Touche *Copier le message* et envoie-le en privé au membre : il contient le lien et son code. Le membre se connecte sur l'espace équipe avec ce code.

### Ce que peut faire un membre

- **Oui** : écrire, modifier et programmer des actus ; créer et modifier des jeux, faire le tirage, publier les gagnants ; envoyer des alertes ; modérer les bons plans (valider, modifier, supprimer) ; gérer la messagerie (répondre, supprimer, masquer, bannir) ; voir les statistiques.
- **Non, réservé à toi** : supprimer un article, supprimer un jeu, effacer les coordonnées des participants, gérer les membres.

Les boutons interdits n'apparaissent pas chez les membres, et la base de données refuse de toute façon ces actions s'ils les tentaient.

- *Suspendre* : le membre ne peut plus se connecter, mais reste dans la liste (pratique pour une pause).
- *Nouveau code* : si un code a circulé, l'ancien cesse aussitôt de fonctionner.
- La liste indique quand chaque membre a utilisé son accès pour la dernière fois.

## Bon à savoir

- **Modération** : lien *Espace modérateur* en bas de la page des bons plans, avec le code choisi à la section 7.
- **Ajouter un bon plan** : bouton *Ajouter un bon plan* en haut de la page. Sur place, le bouton *Je suis sur place* du formulaire enregistre la position exacte, utilisée par le tri « Près de moi ».
- **Sauvegardes** : en plus de l'historique automatique, exporte de temps en temps la table `kv` (*Table Editor → Export*).
- **Sauvegarde automatique** : voir la section 7 pour revenir à une version précédente.
