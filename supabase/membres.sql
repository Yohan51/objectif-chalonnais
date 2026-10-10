-- =====================================================================
-- Membres de l'équipe — L'Objectif Châlonnais
-- À exécuter dans Supabase (SQL Editor → New query → Run), APRÈS tous
-- les autres fichiers (securite, actus, jeux, compteur, chat).
-- Peut être relancé sans risque.
--
-- Deux niveaux d'accès :
--   • Administrateur principal : le code modérateur (oc_private.reglages).
--     Tous les droits, et la gestion des membres.
--   • Membre de l'équipe : un code personnel, créé par l'administrateur.
--     Peut écrire et modifier (actus, jeux, tirages, alertes, réponses),
--     modérer les bons plans et la messagerie (y compris supprimer),
--     mais ne peut PAS supprimer un article, un jeu ou les participants d'un jeu.
-- =====================================================================

create table if not exists oc_private.membres (
  id                bigint generated always as identity primary key,
  nom               text not null check (char_length(btrim(nom)) between 2 and 40),
  code_hash         text not null,
  actif             boolean not null default true,
  cree_le           timestamptz not null default now(),
  derniere_activite timestamptz
);

-- ---------- Qui est-ce ? ----------
create or replace function oc_private.est_admin(p_code text) returns boolean
language sql stable set search_path = '' as $$
  select coalesce((
    select r.code_moderateur is not null
       and coalesce(p_code, '') <> ''
       and extensions.crypt(p_code, r.code_moderateur) = r.code_moderateur
    from oc_private.reglages r where r.id = 1), false)
$$;

create or replace function oc_private.membre_de(p_code text) returns bigint
language sql stable set search_path = '' as $$
  select m.id from oc_private.membres m
  where m.actif and coalesce(p_code, '') <> '' and extensions.crypt(p_code, m.code_hash) = m.code_hash
  limit 1
$$;

-- Code accepté : administrateur OU membre actif (utilisé par toutes les fonctions de l'équipe)
create or replace function oc_private.code_valide(p_code text) returns boolean
language sql stable set search_path = '' as $$
  select oc_private.est_admin(p_code) or oc_private.membre_de(p_code) is not null
$$;

-- Contrôle du code (échecs comptés, blocage après 8 essais) + date de dernière activité du membre
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

-- Réservé à l'administrateur principal
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

-- ---------- Suppressions réservées à l'administrateur ----------
create or replace function public.oc_actu_supprimer(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_admin(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  delete from public.actus where id = p_id;
  return jsonb_build_object('supprime', found);
end $$;

do $$ begin
  if to_regclass('public.jeux') is not null then
    execute $f$
      create or replace function public.oc_jeu_supprimer(p_code text, p_jeu_id bigint) returns jsonb
      language plpgsql volatile security definer set search_path = '' as $b$
      declare msg text := oc_private.controle_admin(p_code);
      begin
        if msg is not null then return jsonb_build_object('erreur', msg); end if;
        delete from public.jeux where id = p_jeu_id;
        return jsonb_build_object('supprime', found);
      end $b$;
    $f$;
    execute $f$
      create or replace function public.oc_jeu_effacer_participants(p_code text, p_jeu_id bigint) returns jsonb
      language plpgsql volatile security definer set search_path = '' as $b$
      declare msg text := oc_private.controle_admin(p_code); n int;
      begin
        if msg is not null then return jsonb_build_object('erreur', msg); end if;
        delete from public.participations where jeu_id = p_jeu_id;
        get diagnostics n = row_count;
        update public.jeux set coordonnees_effacees = true where id = p_jeu_id;
        return jsonb_build_object('effaces', n);
      end $b$;
    $f$;
  end if;
end $$;

-- ---------- Qui suis-je ? (pour adapter les pages) ----------
create or replace function public.oc_qui_suis_je(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); v_id bigint;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if oc_private.est_admin(p_code) then return jsonb_build_object('role', 'admin', 'nom', 'Administrateur'); end if;
  v_id := oc_private.membre_de(p_code);
  return jsonb_build_object('role', 'membre', 'nom', (select nom from oc_private.membres where id = v_id));
end $$;

-- ---------- Gestion des membres (administrateur) ----------
create or replace function public.oc_membres_liste(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if not oc_private.est_admin(p_code) then return jsonb_build_object('erreur', 'Réservé à l''administrateur principal.'); end if;
  return jsonb_build_object('membres', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'nom', nom, 'actif', actif, 'cree_le', cree_le, 'derniere_activite', derniere_activite) order by actif desc, nom)
    from oc_private.membres), '[]'::jsonb));
end $$;

create or replace function oc_private.code_libre(p_nouveau text, p_sauf bigint) returns text
language plpgsql stable set search_path = '' as $$
begin
  if char_length(coalesce(p_nouveau, '')) < 8 then return 'Le code doit faire au moins 8 caractères.'; end if;
  if oc_private.est_admin(p_nouveau) then return 'Ce code est déjà utilisé.'; end if;
  if exists (select 1 from oc_private.membres m where m.id is distinct from p_sauf
             and extensions.crypt(p_nouveau, m.code_hash) = m.code_hash) then
    return 'Ce code est déjà utilisé.';
  end if;
  return null;
end $$;

create or replace function public.oc_membre_ajouter(p_code text, p_nom text, p_code_membre text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); v_id bigint;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if not oc_private.est_admin(p_code) then return jsonb_build_object('erreur', 'Réservé à l''administrateur principal.'); end if;
  if char_length(btrim(coalesce(p_nom, ''))) not between 2 and 40 then return jsonb_build_object('erreur', 'Indiquez le prénom du membre (2 à 40 caractères).'); end if;
  msg := oc_private.code_libre(p_code_membre, null);
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  insert into oc_private.membres (nom, code_hash) values (btrim(p_nom), extensions.crypt(p_code_membre, extensions.gen_salt('bf')))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.oc_membre_modifier(p_code text, p_id bigint, p_actif boolean, p_nouveau_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if not oc_private.est_admin(p_code) then return jsonb_build_object('erreur', 'Réservé à l''administrateur principal.'); end if;
  if not exists (select 1 from oc_private.membres where id = p_id) then return jsonb_build_object('erreur', 'Membre introuvable.'); end if;
  if coalesce(p_nouveau_code, '') <> '' then
    msg := oc_private.code_libre(p_nouveau_code, p_id);
    if msg is not null then return jsonb_build_object('erreur', msg); end if;
    update oc_private.membres set code_hash = extensions.crypt(p_nouveau_code, extensions.gen_salt('bf')) where id = p_id;
  end if;
  if p_actif is not null then update oc_private.membres set actif = p_actif where id = p_id; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.oc_membre_supprimer(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if not oc_private.est_admin(p_code) then return jsonb_build_object('erreur', 'Réservé à l''administrateur principal.'); end if;
  delete from oc_private.membres where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

do $$ begin
  execute 'grant execute on function public.oc_qui_suis_je(text) to anon, authenticated';
  execute 'grant execute on function public.oc_membres_liste(text) to anon, authenticated';
  execute 'grant execute on function public.oc_membre_ajouter(text, text, text) to anon, authenticated';
  execute 'grant execute on function public.oc_membre_modifier(text, bigint, boolean, text) to anon, authenticated';
  execute 'grant execute on function public.oc_membre_supprimer(text, bigint) to anon, authenticated';
end $$;

notify pgrst, 'reload schema';
select 'Membres de l''équipe installés.' as resultat;
