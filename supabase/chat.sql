-- =====================================================================
-- Chat — L'Objectif Châlonnais
-- À exécuter dans Supabase (SQL Editor → New query → Run),
-- après securite.sql et actus.sql. Peut être relancé sans risque.
--
-- Deux espaces :
--   1. « Écrire à l'équipe » : conversation privée entre un visiteur et l'équipe.
--      Le visiteur est reconnu par une clé secrète gardée sur son appareil.
--   2. « La discussion » : salon public où les abonnés aux alertes discutent.
--      Tout le monde peut lire ; seuls les abonnés aux alertes peuvent écrire.
-- Aucune table n'est lisible directement : tout passe par les fonctions ci-dessous.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Écrire à l'équipe
-- ---------------------------------------------------------------------
create table if not exists public.conversations (
  id          bigint generated always as identity primary key,
  jeton_hash  text not null unique,                 -- empreinte de la clé du visiteur
  nom         text not null default '' check (char_length(nom) <= 40),
  email       text not null default '' check (char_length(email) <= 254),
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now(),
  non_lu_equipe   boolean not null default true,
  non_lu_visiteur boolean not null default false,
  fermee      boolean not null default false
);
create table if not exists public.conv_messages (
  id       bigint generated always as identity primary key,
  conv_id  bigint not null references public.conversations(id) on delete cascade,
  auteur   text not null check (auteur in ('visiteur', 'equipe')),
  texte    text not null check (char_length(btrim(texte)) between 1 and 1500),
  cree_le  timestamptz not null default now()
);
create index if not exists conv_messages_conv_idx on public.conv_messages (conv_id, id);
alter table public.conversations enable row level security;
alter table public.conv_messages enable row level security;
revoke all on public.conversations, public.conv_messages from anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. La discussion (salon public)
-- ---------------------------------------------------------------------
create table if not exists public.salon (
  id          bigint generated always as identity primary key,
  pseudo      text not null check (char_length(btrim(pseudo)) between 2 and 30),
  texte       text not null check (char_length(btrim(texte)) between 1 and 500),
  cree_le     timestamptz not null default now(),
  auteur_hash text not null,                         -- empreinte de l'abonnement aux alertes
  masque      boolean not null default false,
  signalements integer not null default 0
);
create index if not exists salon_idx on public.salon (id desc);
alter table public.salon enable row level security;
revoke all on public.salon from anon, authenticated;

create table if not exists oc_private.salon_signalements (
  message_id bigint not null references public.salon(id) on delete cascade,
  ip         text not null,
  primary key (message_id, ip)
);
create table if not exists oc_private.salon_bannis (
  auteur_hash text primary key,
  le          timestamptz not null default now()
);

-- Mots refusés dans le salon (à compléter dans Supabase : Table Editor → oc_private → salon_mots)
create table if not exists oc_private.salon_mots (mot text primary key);
insert into oc_private.salon_mots (mot) values
  ('connard'), ('connasse'), ('salope'), ('enculé'), ('encule'), ('pute'), ('fdp'), ('ntm'),
  ('nique ta'), ('pédé'), ('pede'), ('négro'), ('negro'), ('bougnoule'), ('youpin'), ('bicot')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------
create or replace function oc_private.limite(p_type text, p_max integer, p_minutes integer) returns boolean
language plpgsql volatile set search_path = '' as $$
declare v_ip text := oc_private.ip();
begin
  if (select count(*) from oc_private.ecritures
      where ip = v_ip and type = p_type and quand > now() - make_interval(mins => p_minutes)) >= p_max then
    return false;
  end if;
  insert into oc_private.ecritures (ip, type) values (v_ip, p_type);
  return true;
end $$;

create or replace function oc_private.texte_propre(t text) returns text
language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(coalesce(t, ''), '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]', '', 'g'));
$$;

-- Ménage : salon 90 jours, conversations 6 mois après le dernier message
create or replace function oc_private.purger_chat() returns void
language sql volatile set search_path = '' as $$
  delete from public.salon where cree_le < now() - interval '90 days';
  delete from public.conversations where maj_le < now() - interval '6 months';
$$;

-- =====================================================================
-- Fonctions publiques — Écrire à l'équipe
-- =====================================================================
create or replace function public.oc_conv_envoyer(p_jeton text, p_nom text, p_email text, p_texte text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_hash text; v_id bigint; v_texte text := oc_private.texte_propre(p_texte);
  v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if coalesce(char_length(p_jeton), 0) < 20 or char_length(p_jeton) > 100 then
    return jsonb_build_object('erreur', 'Clé de conversation invalide. Rechargez la page.');
  end if;
  if char_length(v_texte) < 1 then return jsonb_build_object('erreur', 'Écrivez votre message.'); end if;
  if char_length(v_texte) > 1500 then return jsonb_build_object('erreur', 'Message trop long (1 500 caractères au plus).'); end if;
  if v_email <> '' and v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('erreur', 'Cette adresse e-mail ne semble pas valide.');
  end if;
  if not oc_private.limite('conv', 15, 60) then
    return jsonb_build_object('erreur', 'Beaucoup de messages en peu de temps : réessayez dans un moment.');
  end if;

  v_hash := encode(extensions.digest(p_jeton, 'sha256'), 'hex');
  select id into v_id from public.conversations where jeton_hash = v_hash;
  if v_id is null then
    insert into public.conversations (jeton_hash, nom, email)
    values (v_hash, left(btrim(coalesce(p_nom, '')), 40), left(v_email, 254))
    returning id into v_id;
  else
    update public.conversations set
      nom = case when btrim(coalesce(p_nom, '')) <> '' then left(btrim(p_nom), 40) else nom end,
      email = case when v_email <> '' then v_email else email end,
      maj_le = now(), non_lu_equipe = true, fermee = false
    where id = v_id;
  end if;
  insert into public.conv_messages (conv_id, auteur, texte) values (v_id, 'visiteur', v_texte);
  if random() < 0.05 then perform oc_private.purger_chat(); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.oc_conv_lire(p_jeton text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint; v_hash text;
begin
  if coalesce(char_length(p_jeton), 0) < 20 then return jsonb_build_object('messages', '[]'::jsonb); end if;
  v_hash := encode(extensions.digest(p_jeton, 'sha256'), 'hex');
  select id into v_id from public.conversations where jeton_hash = v_hash;
  if v_id is null then return jsonb_build_object('messages', '[]'::jsonb); end if;
  update public.conversations set non_lu_visiteur = false where id = v_id and non_lu_visiteur;
  return jsonb_build_object('messages', coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'auteur', m.auteur, 'texte', m.texte, 'le', m.cree_le) order by m.id)
    from public.conv_messages m where m.conv_id = v_id), '[]'::jsonb));
end $$;

-- Y a-t-il une réponse non lue ? (pastille sur la bulle, sans marquer comme lu)
create or replace function public.oc_conv_nouveau(p_jeton text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select non_lu_visiteur from public.conversations
    where jeton_hash = encode(extensions.digest(coalesce(p_jeton, ''), 'sha256'), 'hex')), false);
$$;

-- =====================================================================
-- Fonctions publiques — La discussion
-- =====================================================================
create or replace function public.oc_salon_lire(p_apres bigint default 0) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'pseudo', pseudo, 'texte', texte, 'le', cree_le) order by id), '[]'::jsonb)
  from (
    select id, pseudo, texte, cree_le from public.salon
    where not masque and id > coalesce(p_apres, 0)
    order by id desc limit 80
  ) d;
$$;

create or replace function public.oc_salon_ecrire(p_pseudo text, p_texte text, p_endpoint text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_pseudo text := oc_private.texte_propre(p_pseudo);
  v_texte text := oc_private.texte_propre(p_texte);
  v_auteur text; v_bas text; v_id bigint;
begin
  if coalesce(p_endpoint, '') = '' or not exists (select 1 from public.push_subscriptions s where s.endpoint = p_endpoint) then
    return jsonb_build_object('erreur', 'Pour écrire dans la discussion, activez d''abord les alertes de L''Objectif Châlonnais sur cet appareil.');
  end if;
  v_auteur := md5(p_endpoint);
  if exists (select 1 from oc_private.salon_bannis b where b.auteur_hash = v_auteur) then
    return jsonb_build_object('erreur', 'Vous ne pouvez plus écrire dans la discussion.');
  end if;
  if char_length(v_pseudo) not between 2 and 30 then return jsonb_build_object('erreur', 'Choisissez un pseudo de 2 à 30 caractères.'); end if;
  if lower(v_pseudo) ~ '(objectif|admin|mod[ée]rat|[ée]quipe|staff)' then
    return jsonb_build_object('erreur', 'Ce pseudo est réservé : choisissez-en un autre.');
  end if;
  if char_length(v_texte) < 1 then return jsonb_build_object('erreur', 'Écrivez votre message.'); end if;
  if char_length(v_texte) > 500 then return jsonb_build_object('erreur', 'Message trop long (500 caractères au plus).'); end if;
  if regexp_replace(v_texte, '(https?://)?(www\.)?lobjectifchalonnais\.fr\S*', '', 'gi') ~* '(https?://|www\.|\.(com|fr|net|org|io|ly|me)\M)' then
    return jsonb_build_object('erreur', 'Les liens vers d''autres sites ne sont pas autorisés dans la discussion.');
  end if;
  v_bas := lower(v_pseudo || ' ' || v_texte);
  if exists (select 1 from oc_private.salon_mots w where v_bas ~ ('(^|[^[:alnum:]])' || regexp_replace(w.mot, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '($|[^[:alnum:]])')) then
    return jsonb_build_object('erreur', 'Votre message contient un mot qui n''est pas accepté ici. Restons cordiaux !');
  end if;
  -- anti-spam : 1 message toutes les 8 secondes, 30 par heure
  if exists (select 1 from public.salon s where s.auteur_hash = v_auteur and s.cree_le > now() - interval '8 seconds') then
    return jsonb_build_object('erreur', 'Doucement : attendez quelques secondes entre deux messages.');
  end if;
  if (select count(*) from public.salon s where s.auteur_hash = v_auteur and s.cree_le > now() - interval '1 hour') >= 30 then
    return jsonb_build_object('erreur', 'Beaucoup de messages en peu de temps : faites une petite pause.');
  end if;
  if not oc_private.limite('salon', 60, 60) then
    return jsonb_build_object('erreur', 'Beaucoup de messages depuis cette connexion : réessayez plus tard.');
  end if;

  insert into public.salon (pseudo, texte, auteur_hash) values (v_pseudo, v_texte, v_auteur) returning id into v_id;
  if random() < 0.05 then perform oc_private.purger_chat(); end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Signaler un message : masqué automatiquement au 3e signalement
create or replace function public.oc_salon_signaler(p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_n integer;
begin
  if not oc_private.limite('signal', 20, 60) then return jsonb_build_object('erreur', 'Trop de signalements : réessayez plus tard.'); end if;
  insert into oc_private.salon_signalements (message_id, ip) values (p_id, oc_private.ip()) on conflict do nothing;
  if not found then return jsonb_build_object('ok', true); end if;
  update public.salon set signalements = signalements + 1,
    masque = masque or signalements + 1 >= 3
  where id = p_id returning signalements into v_n;
  return jsonb_build_object('ok', true);
exception when foreign_key_violation then
  return jsonb_build_object('ok', true);
end $$;

-- =====================================================================
-- Fonctions de l'équipe (code modérateur)
-- =====================================================================
create or replace function public.oc_conv_liste(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  perform oc_private.purger_chat();
  return jsonb_build_object('conversations', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'nom', c.nom, 'email', c.email, 'maj_le', c.maj_le, 'non_lu', c.non_lu_equipe, 'fermee', c.fermee,
      'dernier', (select left(m.texte, 140) from public.conv_messages m where m.conv_id = c.id order by m.id desc limit 1),
      'nb', (select count(*) from public.conv_messages m where m.conv_id = c.id))
      order by c.fermee, c.maj_le desc)
    from public.conversations c), '[]'::jsonb),
    'salon_signales', (select count(*) from public.salon where signalements > 0 or masque));
end $$;

create or replace function public.oc_conv_messages(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  update public.conversations set non_lu_equipe = false where id = p_id;
  return jsonb_build_object('messages', coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'auteur', m.auteur, 'texte', m.texte, 'le', m.cree_le) order by m.id)
    from public.conv_messages m where m.conv_id = p_id), '[]'::jsonb));
end $$;

create or replace function public.oc_conv_repondre(p_code text, p_id bigint, p_texte text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); v_texte text := oc_private.texte_propre(p_texte);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if char_length(v_texte) not between 1 and 1500 then return jsonb_build_object('erreur', 'Réponse vide ou trop longue.'); end if;
  if not exists (select 1 from public.conversations where id = p_id) then return jsonb_build_object('erreur', 'Conversation introuvable.'); end if;
  insert into public.conv_messages (conv_id, auteur, texte) values (p_id, 'equipe', v_texte);
  update public.conversations set maj_le = now(), non_lu_visiteur = true, non_lu_equipe = false where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.oc_conv_fermer(p_code text, p_id bigint, p_fermee boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  update public.conversations set fermee = coalesce(p_fermee, true), non_lu_equipe = false where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.oc_conv_supprimer(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  delete from public.conversations where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.oc_salon_moderation(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  return jsonb_build_object('messages', coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'pseudo', s.pseudo, 'texte', s.texte, 'le', s.cree_le,
      'masque', s.masque, 'signalements', s.signalements,
      'banni', exists (select 1 from oc_private.salon_bannis b where b.auteur_hash = s.auteur_hash)) order by s.id desc)
    from (select * from public.salon order by id desc limit 150) s), '[]'::jsonb));
end $$;

create or replace function public.oc_salon_masquer(p_code text, p_id bigint, p_masque boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  update public.salon set masque = coalesce(p_masque, true),
    signalements = case when coalesce(p_masque, true) then signalements else 0 end
  where id = p_id;
  if not coalesce(p_masque, true) then delete from oc_private.salon_signalements where message_id = p_id; end if;
  return jsonb_build_object('ok', true);
end $$;

-- Bannir l'auteur d'un message (il ne pourra plus écrire) et masquer tous ses messages
create or replace function public.oc_salon_bannir(p_code text, p_id bigint, p_bannir boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); v_auteur text;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  select auteur_hash into v_auteur from public.salon where id = p_id;
  if v_auteur is null then return jsonb_build_object('erreur', 'Message introuvable.'); end if;
  if coalesce(p_bannir, true) then
    insert into oc_private.salon_bannis (auteur_hash) values (v_auteur) on conflict do nothing;
    update public.salon set masque = true where auteur_hash = v_auteur;
  else
    delete from oc_private.salon_bannis where auteur_hash = v_auteur;
  end if;
  return jsonb_build_object('ok', true);
end $$;

do $$ begin
  execute 'grant execute on function public.oc_conv_envoyer(text, text, text, text) to anon, authenticated';
  execute 'grant execute on function public.oc_conv_lire(text) to anon, authenticated';
  execute 'grant execute on function public.oc_conv_nouveau(text) to anon, authenticated';
  execute 'grant execute on function public.oc_salon_lire(bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_salon_ecrire(text, text, text) to anon, authenticated';
  execute 'grant execute on function public.oc_salon_signaler(bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_conv_liste(text) to anon, authenticated';
  execute 'grant execute on function public.oc_conv_messages(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_conv_repondre(text, bigint, text) to anon, authenticated';
  execute 'grant execute on function public.oc_conv_fermer(text, bigint, boolean) to anon, authenticated';
  execute 'grant execute on function public.oc_conv_supprimer(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_salon_moderation(text) to anon, authenticated';
  execute 'grant execute on function public.oc_salon_masquer(text, bigint, boolean) to anon, authenticated';
  execute 'grant execute on function public.oc_salon_bannir(text, bigint, boolean) to anon, authenticated';
end $$;

notify pgrst, 'reload schema';
