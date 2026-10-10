-- =====================================================================
-- RUBRIQUE ACTUALITÉS — L'Objectif Châlonnais
--
-- À coller EN ENTIER dans Supabase : SQL Editor → New query → Run.
-- Nécessite d'avoir installé securite.sql avant (code modérateur).
-- Peut être relancé sans risque.
--
--  - Tout le monde peut LIRE les articles publiés (et seulement ceux-là :
--    les brouillons et les articles programmés restent invisibles).
--  - Écrire, modifier ou supprimer un article demande le code modérateur,
--    vérifié ici (8 essais ratés = blocage 15 minutes).
-- =====================================================================

create table if not exists public.actus (
  id bigserial primary key,
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 90),
  titre text not null check (char_length(btrim(titre)) between 3 and 120),
  chapo text not null default '' check (char_length(chapo) <= 300),
  contenu text not null default '' check (char_length(contenu) <= 20000),
  categorie text not null default 'actu' check (categorie in ('actu','sport','culture','evenement','asso')),
  auteur text not null default '' check (char_length(auteur) <= 60),
  photo text check (photo is null or (char_length(photo) <= 600000 and photo ~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/]+={0,2}$')),
  miniature text check (miniature is null or (char_length(miniature) <= 120000 and miniature ~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/]+={0,2}$')),
  legende text not null default '' check (char_length(legende) <= 150),
  lien text check (lien is null or (lien ~ '^https://' and char_length(lien) <= 500)),
  lien_libelle text not null default '' check (char_length(lien_libelle) <= 60),
  publie boolean not null default false,
  publie_le timestamptz,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now()
);
create index if not exists actus_publie_idx on public.actus (publie, publie_le desc);

alter table public.actus enable row level security;
drop policy if exists "actus publiees" on public.actus;
create policy "actus publiees" on public.actus for select
  using (publie and publie_le is not null and publie_le <= now());

do $$ begin
  execute 'revoke all on public.actus from anon, authenticated';
  execute 'grant select on public.actus to anon, authenticated';
exception when undefined_object then null; end $$;

-- ---------- Contrôle du code (échecs comptés, blocage après 8 essais) ----------
create or replace function oc_private.controle_code(p_code text) returns text
language plpgsql volatile set search_path = '' as $$
declare v_ip text := oc_private.ip(); v_membre bigint;
begin
  if (select count(*) from oc_private.ecritures
      where ip = v_ip and type = 'echec' and quand > now() - interval '15 minutes') >= 8 then
    return 'Trop d''essais ratés : patientez 15 minutes.';
  end if;
  if oc_private.est_admin(p_code) then return null; end if;
  v_membre := oc_private.membre_de(p_code);
  if v_membre is null then
    insert into oc_private.ecritures (ip, type) values (v_ip, 'echec');
    return 'Code modérateur incorrect.';
  end if;
  update oc_private.membres set derniere_activite = now()
  where id = v_membre and (derniere_activite is null or derniere_activite < now() - interval '5 minutes');
  return null;
end $$;

create or replace function oc_private.controle_admin(p_code text) returns text
language plpgsql volatile set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return msg; end if;
  if not oc_private.est_admin(p_code) then
    return 'Seul l''administrateur principal peut faire cette suppression.';
  end if;
  return null;
end $$;

-- ---------- Liste pour la rédaction (brouillons compris, sans les images) ----------
create or replace function public.oc_actus_redaction(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  return jsonb_build_object('actus', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id, 'slug', a.slug, 'titre', a.titre, 'categorie', a.categorie,
      'publie', a.publie, 'publie_le', a.publie_le, 'modifie_le', a.modifie_le,
      'miniature', a.miniature) order by coalesce(a.publie_le, a.modifie_le) desc)
    from public.actus a), '[]'::jsonb));
end $$;

-- ---------- Lire un article complet pour le modifier ----------
create or replace function public.oc_actu_lire(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); r jsonb;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  select to_jsonb(a) into r from public.actus a where a.id = p_id;
  if r is null then return jsonb_build_object('erreur', 'Article introuvable.'); end if;
  return jsonb_build_object('actu', r);
end $$;

-- ---------- Créer ou modifier un article ----------
create or replace function public.oc_actu_enregistrer(p_code text, p_actu jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  msg text := oc_private.controle_code(p_code);
  v_id bigint; v_slug text; base_slug text; n int := 1;
  v_publie boolean; v_date timestamptz; v_lien text;
  garder_photo boolean;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if jsonb_typeof(p_actu) <> 'object' then return jsonb_build_object('erreur', 'Article illisible.'); end if;

  v_id := nullif(p_actu ->> 'id', '')::bigint;
  base_slug := lower(coalesce(p_actu ->> 'slug', ''));
  base_slug := btrim(regexp_replace(base_slug, '[^a-z0-9]+', '-', 'g'), '-');
  base_slug := left(base_slug, 80);
  if base_slug = '' then base_slug := 'actu'; end if;
  base_slug := btrim(base_slug, '-');
  v_slug := base_slug;
  while exists (select 1 from public.actus a where a.slug = v_slug and a.id is distinct from v_id) loop
    n := n + 1; v_slug := base_slug || '-' || n;
  end loop;

  v_publie := coalesce((p_actu ->> 'publie')::boolean, false);
  begin
    v_date := nullif(p_actu ->> 'publie_le', '')::timestamptz;
  exception when others then
    return jsonb_build_object('erreur', 'Date de publication invalide.');
  end;
  if v_publie and v_date is null then v_date := now(); end if;
  v_lien := nullif(btrim(coalesce(p_actu ->> 'lien', '')), '');
  -- photo : "garder" = ne pas renvoyer l'image à chaque modification
  garder_photo := coalesce((p_actu ->> 'garder_photo')::boolean, false);

  begin
    if v_id is null then
      insert into public.actus (slug, titre, chapo, contenu, categorie, auteur, photo, miniature, legende,
                                lien, lien_libelle, publie, publie_le)
      values (v_slug, btrim(p_actu ->> 'titre'), coalesce(p_actu ->> 'chapo', ''), coalesce(p_actu ->> 'contenu', ''),
              coalesce(nullif(p_actu ->> 'categorie', ''), 'actu'), coalesce(p_actu ->> 'auteur', ''),
              nullif(p_actu ->> 'photo', ''), nullif(p_actu ->> 'miniature', ''), coalesce(p_actu ->> 'legende', ''),
              v_lien, coalesce(p_actu ->> 'lien_libelle', ''), v_publie, v_date)
      returning id into v_id;
    else
      update public.actus a set
        slug = v_slug,
        titre = btrim(p_actu ->> 'titre'),
        chapo = coalesce(p_actu ->> 'chapo', ''),
        contenu = coalesce(p_actu ->> 'contenu', ''),
        categorie = coalesce(nullif(p_actu ->> 'categorie', ''), 'actu'),
        auteur = coalesce(p_actu ->> 'auteur', ''),
        photo = case when garder_photo then a.photo else nullif(p_actu ->> 'photo', '') end,
        miniature = case when garder_photo then a.miniature else nullif(p_actu ->> 'miniature', '') end,
        legende = coalesce(p_actu ->> 'legende', ''),
        lien = v_lien,
        lien_libelle = coalesce(p_actu ->> 'lien_libelle', ''),
        publie = v_publie,
        publie_le = v_date,
        modifie_le = now()
      where a.id = v_id;
      if not found then return jsonb_build_object('erreur', 'Article introuvable.'); end if;
    end if;
  exception
    when check_violation then
      return jsonb_build_object('erreur', 'Un champ ne respecte pas le format attendu (titre de 3 à 120 caractères, lien en https://, photo trop lourde…).');
    when not_null_violation then
      return jsonb_build_object('erreur', 'Le titre est obligatoire.');
  end;

  return jsonb_build_object('id', v_id, 'slug', v_slug, 'publie', v_publie, 'publie_le', v_date);
end $$;

-- ---------- Supprimer un article ----------
create or replace function public.oc_actu_supprimer(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_admin(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  delete from public.actus where id = p_id;
  return jsonb_build_object('supprime', found);
end $$;

do $$ begin
  execute 'grant execute on function public.oc_actus_redaction(text) to anon, authenticated';
  execute 'grant execute on function public.oc_actu_lire(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_actu_enregistrer(text, jsonb) to anon, authenticated';
  execute 'grant execute on function public.oc_actu_supprimer(text, bigint) to anon, authenticated';
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';

select 'Rubrique Actualités installée.' as resultat;
