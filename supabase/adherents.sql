-- =====================================================================
-- Adhérents de l'association et cartes de membre numériques
-- L'Objectif Châlonnais
--
-- À exécuter dans Supabase (SQL Editor → New query → Run), APRÈS
-- membres.sql (il réutilise la connexion de l'équipe).
-- Peut être relancé sans risque : rien n'est effacé.
--
-- Deux niveaux, bien séparés :
--   • Adhérent : une personne à jour (ou non) de sa cotisation. Il a une
--     carte numérique avec un QR code. Aucun accès à l'espace équipe.
--   • Contributeur : un membre de l'équipe (membres.sql), avec son code
--     personnel, qui peut publier. Être adhérent ne donne pas ce droit.
--
-- Deux secrets par adhérent, tirés au hasard (impossibles à deviner) :
--   • cle_carte : dans le lien personnel « Ma carte » envoyé à l'adhérent.
--     Ouvre sa carte complète.
--   • jeton : dans le QR code. Celui qui scanne voit seulement le prénom,
--     l'initiale du nom, le numéro et la validité. Un membre de l'équipe
--     connecté voit le nom complet. Le téléphone n'est jamais montré.
-- « Nouveau QR » dans la page de gestion remplace les deux : l'ancienne
-- carte cesse aussitôt de fonctionner (téléphone perdu, carte partagée…).
-- =====================================================================

create or replace function oc_private.secret() returns text
language sql volatile set search_path = '' as $$
  select rtrim(translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_'), '=')
$$;

create table if not exists oc_private.adherents (
  id         bigint generated always as identity primary key,
  prenom     text not null check (char_length(btrim(prenom)) between 1 and 40),
  nom        text not null check (char_length(btrim(nom)) between 1 and 60),
  telephone  text check (telephone is null or char_length(telephone) <= 25),
  debut      date not null,
  fin        date not null,
  actif      boolean not null default true,
  jeton      text not null unique default oc_private.secret(),
  cle_carte  text not null unique default oc_private.secret(),
  cree_le    timestamptz not null default now(),
  constraint adherents_dates check (fin >= debut)
);

-- Entrées aux événements réservés aux adhérents
create table if not exists oc_private.passages (
  id           bigint generated always as identity primary key,
  adherent_id  bigint not null references oc_private.adherents(id) on delete cascade,
  evenement    text not null,
  quand        timestamptz not null default now(),
  par          text
);
create index if not exists passages_evt_idx on oc_private.passages (evenement, adherent_id);

-- ---------- Outils ----------
create or replace function oc_private.aujourdhui() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'Europe/Paris')::date
$$;

create or replace function oc_private.statut_adherent(a oc_private.adherents) returns text
language sql stable set search_path = '' as $$
  select case
    when not a.actif then 'suspendu'
    when oc_private.aujourdhui() < a.debut then 'a_venir'
    when oc_private.aujourdhui() > a.fin then 'expire'
    else 'valide' end
$$;

create or replace function oc_private.numero_adherent(p_id bigint) returns text
language sql immutable set search_path = '' as $$
  select 'OC-' || lpad(p_id::text, 4, '0')
$$;

create or replace function oc_private.nom_equipe(p_code text) returns text
language sql stable set search_path = '' as $$
  select case when oc_private.est_admin(p_code) then 'Administrateur'
              else (select m.nom from oc_private.membres m where m.id = oc_private.membre_de(p_code)) end
$$;

-- ---------- Gestion (administrateur principal) ----------
create or replace function public.oc_adherents_liste(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if not oc_private.est_admin(p_code) then return jsonb_build_object('erreur', 'Réservé à l''administrateur principal.'); end if;
  return jsonb_build_object('adherents', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id, 'numero', oc_private.numero_adherent(a.id),
      'prenom', a.prenom, 'nom', a.nom, 'telephone', a.telephone,
      'debut', a.debut, 'fin', a.fin, 'actif', a.actif,
      'statut', oc_private.statut_adherent(a),
      'jeton', a.jeton, 'cle_carte', a.cle_carte, 'cree_le', a.cree_le,
      'passages', (select count(*) from oc_private.passages p where p.adherent_id = a.id)
    ) order by a.nom, a.prenom)
    from oc_private.adherents a), '[]'::jsonb));
end $$;

-- Ajoute (p_id vide) ou modifie un adhérent
create or replace function public.oc_adherent_enregistrer(
  p_code text, p_id bigint, p_prenom text, p_nom text, p_telephone text,
  p_debut date, p_fin date, p_actif boolean
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); v_id bigint;
        v_tel text := nullif(btrim(coalesce(p_telephone, '')), '');
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if not oc_private.est_admin(p_code) then return jsonb_build_object('erreur', 'Réservé à l''administrateur principal.'); end if;
  if char_length(btrim(coalesce(p_prenom, ''))) not between 1 and 40 then return jsonb_build_object('erreur', 'Indiquez le prénom.'); end if;
  if char_length(btrim(coalesce(p_nom, ''))) not between 1 and 60 then return jsonb_build_object('erreur', 'Indiquez le nom.'); end if;
  if v_tel is not null and char_length(v_tel) > 25 then return jsonb_build_object('erreur', 'Numéro de téléphone trop long.'); end if;
  if p_debut is null or p_fin is null then return jsonb_build_object('erreur', 'Indiquez les deux dates de la cotisation.'); end if;
  if p_fin < p_debut then return jsonb_build_object('erreur', 'La date de fin est avant la date de début.'); end if;

  if p_id is null then
    insert into oc_private.adherents (prenom, nom, telephone, debut, fin, actif)
    values (btrim(p_prenom), btrim(p_nom), v_tel, p_debut, p_fin, coalesce(p_actif, true))
    returning id into v_id;
  else
    update oc_private.adherents set prenom = btrim(p_prenom), nom = btrim(p_nom), telephone = v_tel,
      debut = p_debut, fin = p_fin, actif = coalesce(p_actif, actif)
    where id = p_id returning id into v_id;
    if v_id is null then return jsonb_build_object('erreur', 'Adhérent introuvable.'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Nouveau QR et nouveau lien de carte : les anciens ne fonctionnent plus
create or replace function public.oc_adherent_nouveau_qr(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if not oc_private.est_admin(p_code) then return jsonb_build_object('erreur', 'Réservé à l''administrateur principal.'); end if;
  update oc_private.adherents set jeton = oc_private.secret(), cle_carte = oc_private.secret() where id = p_id;
  if not found then return jsonb_build_object('erreur', 'Adhérent introuvable.'); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.oc_adherent_supprimer(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if not oc_private.est_admin(p_code) then return jsonb_build_object('erreur', 'Réservé à l''administrateur principal.'); end if;
  delete from oc_private.adherents where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- La carte de l'adhérent (lien personnel) ----------
create or replace function public.oc_ma_carte(p_cle text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a oc_private.adherents;
begin
  select * into a from oc_private.adherents where cle_carte = p_cle and coalesce(p_cle, '') <> '';
  if a.id is null then return jsonb_build_object('erreur', 'Cette carte n''existe pas ou a été remplacée. Demandez votre nouveau lien à l''association.'); end if;
  return jsonb_build_object(
    'prenom', a.prenom, 'nom', a.nom, 'numero', oc_private.numero_adherent(a.id),
    'debut', a.debut, 'fin', a.fin, 'statut', oc_private.statut_adherent(a), 'jeton', a.jeton);
end $$;

-- ---------- Ce que voit la personne qui scanne le QR ----------
-- p_code facultatif : un membre de l'équipe connecté voit le nom complet.
create or replace function public.oc_verifier_carte(p_jeton text, p_code text default '') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a oc_private.adherents; equipe boolean := oc_private.code_valide(p_code);
begin
  select * into a from oc_private.adherents where jeton = p_jeton and coalesce(p_jeton, '') <> '';
  if a.id is null then return jsonb_build_object('statut', 'inconnu'); end if;
  return jsonb_build_object(
    'prenom', a.prenom,
    'nom', case when equipe then a.nom else upper(left(a.nom, 1)) || '.' end,
    'numero', oc_private.numero_adherent(a.id),
    'debut', a.debut, 'fin', a.fin, 'statut', oc_private.statut_adherent(a), 'equipe', equipe);
end $$;

-- ---------- Contrôle à l'entrée d'un événement (équipe) ----------
-- Enregistre l'entrée si la cotisation est valable ; signale une 2e entrée.
create or replace function public.oc_pointer_entree(p_code text, p_jeton text, p_evenement text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); a oc_private.adherents;
        v_evt text := btrim(coalesce(p_evenement, '')); v_statut text; v_deja timestamptz;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if char_length(v_evt) not between 2 and 80 then return jsonb_build_object('erreur', 'Indiquez le nom de l''événement.'); end if;
  select * into a from oc_private.adherents where jeton = p_jeton and coalesce(p_jeton, '') <> '';
  if a.id is null then
    return jsonb_build_object('statut', 'inconnu', 'entrees', (select count(*) from oc_private.passages where evenement = v_evt));
  end if;
  v_statut := oc_private.statut_adherent(a);
  if v_statut = 'valide' then
    select min(quand) into v_deja from oc_private.passages where adherent_id = a.id and evenement = v_evt;
    if v_deja is null then
      insert into oc_private.passages (adherent_id, evenement, par) values (a.id, v_evt, oc_private.nom_equipe(p_code));
    end if;
  end if;
  return jsonb_build_object(
    'statut', v_statut, 'prenom', a.prenom, 'nom', a.nom, 'numero', oc_private.numero_adherent(a.id),
    'debut', a.debut, 'fin', a.fin, 'deja_entre', v_deja,
    'entrees', (select count(*) from oc_private.passages where evenement = v_evt));
end $$;

create or replace function public.oc_entrees(p_code text, p_evenement text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  return jsonb_build_object('entrees', (select count(*) from oc_private.passages where evenement = btrim(coalesce(p_evenement, ''))));
end $$;

do $$ begin
  execute 'grant execute on function public.oc_adherents_liste(text) to anon, authenticated';
  execute 'grant execute on function public.oc_adherent_enregistrer(text, bigint, text, text, text, date, date, boolean) to anon, authenticated';
  execute 'grant execute on function public.oc_adherent_nouveau_qr(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_adherent_supprimer(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_ma_carte(text) to anon, authenticated';
  execute 'grant execute on function public.oc_verifier_carte(text, text) to anon, authenticated';
  execute 'grant execute on function public.oc_pointer_entree(text, text, text) to anon, authenticated';
  execute 'grant execute on function public.oc_entrees(text, text) to anon, authenticated';
end $$;

notify pgrst, 'reload schema';
select 'Adhérents et cartes de membre installés.' as resultat;
