# Site de L'Objectif Châlonnais

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `index.html` | Accueil : présentation, réseaux, inscription à la lettre, contact |
| `bons-plans.html` | Le guide des bons plans, avec la carte OpenStreetMap |
| `quiz.html` | Le quiz « Connais-tu Châlons ? » |
| `config.js` | **Le seul fichier à modifier** : liens des réseaux, contact, dons, base de données |
| `storage.js` | Enregistrement des données (ne pas modifier) |
| `site.css` | Barre de navigation commune |
| `logo.png` | Logo de l'association |

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

## Bon à savoir

- **Modération** : le code d'accès reste celui du guide d'origine. Pour le changer, demande un nouveau code chiffré à Claude et remplace `ADMIN_PASSWORD_HASH` dans `bons-plans.html`.
- **Ajouter un lieu depuis la carte** : un clic (ou un appui) sur la carte propose « Ajouter un bon plan ici », avec le quartier présélectionné.
- **Sauvegardes** : pense à exporter de temps en temps la table `kv` depuis Supabase (*Table Editor → Export*).
- **Sécurité** : comme dans la version d'origine, l'ensemble des bons plans est enregistré d'un bloc et la clé publique permet d'écrire dans la table. C'est suffisant pour démarrer ; si le site devient une cible de vandalisme, il faudra passer à des comptes contributeurs.
