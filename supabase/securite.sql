-- =====================================================================
-- SÉCURITÉ DE LA CARTE DES BONS PLANS — L'Objectif Châlonnais
--
-- À coller EN ENTIER dans Supabase : SQL Editor → New query → Run.
-- Peut être relancé sans risque (par exemple après une mise à jour).
--
-- Ce que ça change :
--  - Plus personne ne peut écrire directement dans la table « kv ».
--    Tout passe par la fonction oc_enregistrer, qui contrôle chaque ajout :
--    un visiteur peut AJOUTER (bon plan, note, commentaire, photo,
--    signalement) mais ne peut ni effacer ni modifier ce qui existe.
--  - Seul le code modérateur, vérifié ici et non plus dans la page,
--    permet de supprimer, publier ou marquer un partenaire.
--  - Chaque enregistrement est gardé dans un historique : en cas de
--    problème, une ancienne version se restaure en une ligne.
--  - Limite de débit : 40 enregistrements par appareil en 10 minutes.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create schema if not exists oc_private;
revoke all on schema oc_private from public;
do $$ begin
  execute 'revoke all on schema oc_private from anon, authenticated';
exception when undefined_object then null; end $$;

-- ---------- Tables privées ----------
create table if not exists oc_private.reglages (
  id int primary key default 1 check (id = 1),
  code_moderateur text
);
insert into oc_private.reglages (id) values (1) on conflict do nothing;

create table if not exists oc_private.historique (
  id bigserial primary key,
  cle text not null,
  valeur text not null,
  enregistre_le timestamptz not null default now(),
  par_moderateur boolean not null default false,
  ip text
);
create index if not exists historique_cle_idx on oc_private.historique (cle, id desc);

create table if not exists oc_private.ecritures (
  ip text not null,
  type text not null default 'ecriture',
  quand timestamptz not null default now()
);
create index if not exists ecritures_idx on oc_private.ecritures (ip, type, quand);
create index if not exists ecritures_quand_idx on oc_private.ecritures (quand);

-- Éléments supprimés par un modérateur : empêche qu'une ancienne copie les fasse revenir
create table if not exists oc_private.supprimes (
  type text not null,
  element text not null,
  quand timestamptz not null default now(),
  primary key (type, element)
);

-- ---------- Outils ----------
create or replace function oc_private.ip() returns text
language plpgsql stable set search_path = '' as $$
declare h json; v text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then h := null;
  end;
  v := coalesce(
    nullif(h ->> 'cf-connecting-ip', ''),
    nullif(btrim(split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1)), ''),
    'inconnu');
  return md5(v);  -- on ne garde jamais l'adresse en clair
end $$;

create or replace function oc_private.libelle(k text) returns text
language sql immutable set search_path = '' as $$
  select case k
    when 'name' then 'nom' when 'desc' then 'description' when 'address' then 'adresse'
    when 'author' then 'prénom' when 'fb' then 'Facebook' when 'text' then 'commentaire'
    when 'reason' then 'raison' when 'label' then 'libellé' when 'eventDate' then 'date'
    else k end
$$;

create or replace function oc_private.chaine(o jsonb, k text, maxi int, requis boolean default false)
returns text language plpgsql immutable set search_path = '' as $$
declare v jsonb := o -> k; s text;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    s := '';
  elsif jsonb_typeof(v) <> 'string' then
    raise exception 'Donnée invalide (%).', oc_private.libelle(k) using errcode = 'P0001';
  else
    s := v #>> '{}';
  end if;
  if char_length(s) > maxi then
    raise exception 'Texte trop long (%).', oc_private.libelle(k) using errcode = 'P0001';
  end if;
  if requis and btrim(s) = '' then
    raise exception 'Champ obligatoire manquant (%).', oc_private.libelle(k) using errcode = 'P0001';
  end if;
  return s;
end $$;

create or replace function oc_private.nombre(o jsonb, k text, mini numeric, maxi numeric, defaut numeric)
returns numeric language plpgsql immutable set search_path = '' as $$
declare v jsonb := o -> k; n numeric;
begin
  if v is null or jsonb_typeof(v) = 'null' then return defaut; end if;
  if jsonb_typeof(v) <> 'number' then
    raise exception 'Donnée invalide (%).', oc_private.libelle(k) using errcode = 'P0001';
  end if;
  n := (v #>> '{}')::numeric;
  if n < mini or n > maxi then
    raise exception 'Valeur hors limites (%).', oc_private.libelle(k) using errcode = 'P0001';
  end if;
  return n;
end $$;

create or replace function oc_private.booleen(o jsonb, k text) returns boolean
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(o -> k) = 'boolean' then (o ->> k)::boolean else false end
$$;

create or replace function oc_private.ident(o jsonb, prefixes text) returns text
language plpgsql immutable set search_path = '' as $$
declare v text;
begin
  if jsonb_typeof(o -> 'id') <> 'string' then
    raise exception 'Identifiant invalide.' using errcode = 'P0001';
  end if;
  v := o ->> 'id';
  if v !~ ('^(' || prefixes || ')-[A-Za-z0-9_-]{1,48}$') then
    raise exception 'Identifiant invalide.' using errcode = 'P0001';
  end if;
  return v;
end $$;

create or replace function oc_private.date_sure(t text) returns date
language plpgsql immutable set search_path = '' as $$
begin
  if t is null or t !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return t::date;
exception when others then return null;
end $$;

create or replace function oc_private.maintenant_ms() returns numeric
language sql stable set search_path = '' as $$
  select floor(extract(epoch from now()) * 1000)
$$;

create or replace function oc_private.liste_textes(j jsonb) returns text[]
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(j) = 'array'
    then coalesce(array(select x from jsonb_array_elements_text(j) x where char_length(x) <= 80), '{}')
    else '{}'::text[] end
$$;

create or replace function oc_private.cle_note(r jsonb) returns text
language sql immutable set search_path = '' as $$
  select coalesce(r ->> 'ts', '') || '|' || coalesce(r ->> 'value', '') || '|' || coalesce(r ->> 'author', '')
$$;

create or replace function oc_private.est_supprime(t text, e text) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from oc_private.supprimes s where s.type = t and s.element = e)
$$;

-- Un événement daté est-il passé ? (règle du site, avec un jour de marge)
create or replace function oc_private.expire(p jsonb) returns boolean
language sql stable set search_path = '' as $$
  select case
    when oc_private.date_sure(p ->> 'eventDate') is null then false
    when p ->> 'cat' = 'weekend' then oc_private.date_sure(p ->> 'eventDate') + 1 <= current_date
    when p ->> 'cat' = 'month' then (date_trunc('month', oc_private.date_sure(p ->> 'eventDate')) + interval '1 month 4 days')::date <= current_date
    else false end
$$;

-- ---------- Validation des éléments ajoutés ----------
create or replace function oc_private.valider_note(r jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare v numeric;
begin
  if jsonb_typeof(r) <> 'object' then raise exception 'Note invalide.' using errcode = 'P0001'; end if;
  v := oc_private.nombre(r, 'value', 1, 5, null);
  if v is null or v <> trunc(v) then raise exception 'Note invalide.' using errcode = 'P0001'; end if;
  return jsonb_build_object(
    'value', v::int,
    'author', oc_private.chaine(r, 'author', 30),
    'ts', oc_private.nombre(r, 'ts', 1e12, 1e14, oc_private.maintenant_ms()));
end $$;

create or replace function oc_private.valider_commentaire(c jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
begin
  if jsonb_typeof(c) <> 'object' then raise exception 'Commentaire invalide.' using errcode = 'P0001'; end if;
  return jsonb_build_object(
    'id', oc_private.ident(c, 'c'),
    'author', oc_private.chaine(c, 'author', 30),
    'fb', oc_private.chaine(c, 'fb', 80),
    'text', oc_private.chaine(c, 'text', 240, true),
    'ts', oc_private.nombre(c, 'ts', 1e12, 1e14, oc_private.maintenant_ms()));
end $$;

create or replace function oc_private.valider_participant(a jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
begin
  if jsonb_typeof(a) <> 'object' then raise exception 'Participation invalide.' using errcode = 'P0001'; end if;
  return jsonb_build_object(
    'id', oc_private.ident(a, 'att'),
    'author', oc_private.chaine(a, 'author', 30),
    'fb', oc_private.chaine(a, 'fb', 80),
    'ts', oc_private.nombre(a, 'ts', 1e12, 1e14, oc_private.maintenant_ms()));
end $$;

create or replace function oc_private.valider_pin_nouveau(p jsonb, admin boolean) returns jsonb
language plpgsql stable set search_path = '' as $$
declare cat text; q text; ed text; st text; lat numeric; lng numeric;
begin
  if jsonb_typeof(p) <> 'object' then raise exception 'Bon plan invalide.' using errcode = 'P0001'; end if;
  cat := oc_private.chaine(p, 'cat', 20, true);
  if cat not in ('resto','champagne','nature','culture','insolite','event','weekend','month') then
    raise exception 'Catégorie inconnue.' using errcode = 'P0001';
  end if;
  q := nullif(oc_private.chaine(p, 'quartier', 20), '');
  if q is not null and q not in ('centre','venise','jard','gare','faubourg','autre') then
    raise exception 'Quartier inconnu.' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p -> 'lat') <> 'number' or jsonb_typeof(p -> 'lng') <> 'number' then
    raise exception 'Position manquante.' using errcode = 'P0001';
  end if;
  lat := (p ->> 'lat')::numeric; lng := (p ->> 'lng')::numeric;
  if lat < 48 or lat > 50 or lng < 3 or lng > 6 then
    raise exception 'Ce lieu est trop loin de Châlons pour figurer sur la carte.' using errcode = 'P0001';
  end if;
  ed := nullif(oc_private.chaine(p, 'eventDate', 10), '');
  if cat in ('weekend','month') then
    if oc_private.date_sure(ed) is null then
      raise exception 'Date de l''événement invalide.' using errcode = 'P0001';
    end if;
  else
    ed := null;
  end if;
  if admin then
    st := coalesce(nullif(oc_private.chaine(p, 'status', 12), ''), 'published');
    if st not in ('published','pending','archived') then st := 'published'; end if;
  else
    st := case when cat in ('weekend','month') then 'pending' else 'published' end;
  end if;
  return jsonb_build_object(
    'id', oc_private.ident(p, 'pin|seed'),
    'name', oc_private.chaine(p, 'name', 60, true),
    'cat', cat,
    'quartier', q,
    'desc', oc_private.chaine(p, 'desc', 220),
    'address', oc_private.chaine(p, 'address', 100),
    'author', oc_private.chaine(p, 'author', 30),
    'fb', oc_private.chaine(p, 'fb', 80),
    'lat', lat,
    'lng', lng,
    'preciseLocation', oc_private.booleen(p, 'preciseLocation'),
    'ts', oc_private.nombre(p, 'ts', 1e12, 1e14, oc_private.maintenant_ms()),
    'isPartner', admin and oc_private.booleen(p, 'isPartner'),
    'keepPublished', admin and oc_private.booleen(p, 'keepPublished'),
    'hasCoverPhoto', false,
    'photoCount', 0,
    'status', st,
    'eventDate', ed,
    'seeded', oc_private.booleen(p, 'seeded'),
    'ratings', '[]'::jsonb,
    'comments', '[]'::jsonb,
    'attendees', '[]'::jsonb);
end $$;

create or replace function oc_private.valider_signalement(r jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare t text; raison text;
begin
  if jsonb_typeof(r) <> 'object' then raise exception 'Signalement invalide.' using errcode = 'P0001'; end if;
  t := oc_private.chaine(r, 'type', 10, true);
  if t not in ('pin','comment','photo') then raise exception 'Signalement invalide.' using errcode = 'P0001'; end if;
  raison := oc_private.chaine(r, 'reason', 200, true);
  if char_length(btrim(raison)) < 3 then raise exception 'Précisez la raison du signalement.' using errcode = 'P0001'; end if;
  return jsonb_build_object(
    'id', oc_private.ident(r, 'r'),
    'type', t,
    'pinId', oc_private.chaine(r, 'pinId', 60, true),
    'commentId', nullif(oc_private.chaine(r, 'commentId', 60), ''),
    'photoId', nullif(oc_private.chaine(r, 'photoId', 60), ''),
    'label', oc_private.chaine(r, 'label', 150),
    'reason', raison,
    'ts', oc_private.nombre(r, 'ts', 1e12, 1e14, oc_private.maintenant_ms()),
    'status', 'pending');
end $$;

create or replace function oc_private.valider_photo(ph jsonb, admin boolean) returns jsonb
language plpgsql stable set search_path = '' as $$
declare d text;
begin
  if jsonb_typeof(ph) <> 'object' then raise exception 'Photo invalide.' using errcode = 'P0001'; end if;
  d := oc_private.chaine(ph, 'dataUrl', 700000, true);
  if d !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$' then
    raise exception 'Photo invalide.' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'id', oc_private.ident(ph, 'ph'),
    'dataUrl', d,
    'author', oc_private.chaine(ph, 'author', 30),
    'fb', oc_private.chaine(ph, 'fb', 80),
    'ts', oc_private.nombre(ph, 'ts', 1e12, 1e14, oc_private.maintenant_ms()),
    'official', admin and oc_private.booleen(ph, 'official'));
end $$;

-- ---------- Fusion : bons plans ----------
-- La version envoyée par la page est une PROPOSITION : on repart toujours de
-- la version en base et on n'y applique que les changements autorisés.
create or replace function oc_private.fusion_pins(ancien jsonb, nouveau jsonb, admin boolean, ops jsonb)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  res jsonb[] := '{}';
  client jsonb;
  base jsonb; p jsonb; el jsonb; liste jsonb;
  ident text; st_new text;
  ids_anciens text[] := '{}';
  cles text[];
  sup_pins text[]; sup_com text[]; mod_pins text[]; ann_part text[];
  n_pins int := 0; n_com int := 0; n_notes int := 0; n_part int := 0; n_annul int := 0; k int;
  lim_pins int;
begin
  if nouveau is null or jsonb_typeof(nouveau) <> 'array' then
    raise exception 'Données invalides.' using errcode = 'P0001';
  end if;
  if jsonb_array_length(nouveau) > 3000 then
    raise exception 'Trop de bons plans.' using errcode = 'P0001';
  end if;
  if exists (select 1 from jsonb_array_elements(nouveau) e
             where jsonb_typeof(e) <> 'object' or jsonb_typeof(e -> 'id') <> 'string') then
    raise exception 'Bon plan invalide.' using errcode = 'P0001';
  end if;
  if ancien is not null and jsonb_typeof(ancien) <> 'array' then ancien := null; end if;

  ops := coalesce(ops, '{}'::jsonb);
  sup_pins := case when admin then oc_private.liste_textes(ops -> 'supprimer_pins') else '{}' end;
  sup_com  := case when admin then oc_private.liste_textes(ops -> 'supprimer_commentaires') else '{}' end;
  mod_pins := case when admin then oc_private.liste_textes(ops -> 'modifier_pins') else '{}' end;
  ann_part := oc_private.liste_textes(ops -> 'annuler_participations');

  select coalesce(jsonb_object_agg(e ->> 'id', e), '{}'::jsonb) into client
  from jsonb_array_elements(nouveau) e;

  for base in select value from jsonb_array_elements(coalesce(ancien, '[]'::jsonb)) loop
    ident := base ->> 'id';
    ids_anciens := ids_anciens || ident;

    if ident = any(sup_pins) then
      insert into oc_private.supprimes (type, element) values ('pin', ident) on conflict do nothing;
      continue;
    end if;

    if cardinality(sup_com) > 0 and jsonb_typeof(base -> 'comments') = 'array' then
      base := jsonb_set(base, '{comments}', coalesce((
        select jsonb_agg(x order by o) from jsonb_array_elements(base -> 'comments') with ordinality t(x, o)
        where not (coalesce(x ->> 'id', '') = any(sup_com))), '[]'::jsonb));
    end if;

    if cardinality(ann_part) > 0 and jsonb_typeof(base -> 'attendees') = 'array' then
      select count(*) into k from jsonb_array_elements(base -> 'attendees') x where x ->> 'id' = any(ann_part);
      if k > 0 then
        n_annul := n_annul + k;
        base := jsonb_set(base, '{attendees}', coalesce((
          select jsonb_agg(x order by o) from jsonb_array_elements(base -> 'attendees') with ordinality t(x, o)
          where not (coalesce(x ->> 'id', '') = any(ann_part))), '[]'::jsonb));
      end if;
    end if;

    p := client -> ident;
    if p is not null then
      -- Notes : seulement des ajouts
      if jsonb_typeof(p -> 'ratings') = 'array' then
        liste := case when jsonb_typeof(base -> 'ratings') = 'array' then base -> 'ratings' else '[]'::jsonb end;
        select coalesce(array_agg(oc_private.cle_note(x)), '{}') into cles from jsonb_array_elements(liste) x;
        for el in select value from jsonb_array_elements(p -> 'ratings') loop
          if oc_private.cle_note(el) = any(cles) then continue; end if;
          el := oc_private.valider_note(el);
          liste := liste || jsonb_build_array(el);
          cles := cles || oc_private.cle_note(el);
          n_notes := n_notes + 1;
        end loop;
        base := jsonb_set(base, '{ratings}', liste);
      end if;

      -- Commentaires : seulement des ajouts
      if jsonb_typeof(p -> 'comments') = 'array' then
        liste := case when jsonb_typeof(base -> 'comments') = 'array' then base -> 'comments' else '[]'::jsonb end;
        select coalesce(array_agg(x ->> 'id'), '{}') into cles from jsonb_array_elements(liste) x;
        for el in select value from jsonb_array_elements(p -> 'comments') loop
          if (el ->> 'id') = any(cles) or (el ->> 'id') = any(sup_com) then continue; end if;
          if oc_private.est_supprime('commentaire', coalesce(el ->> 'id', '')) then continue; end if;
          el := oc_private.valider_commentaire(el);
          liste := liste || jsonb_build_array(el);
          cles := cles || (el ->> 'id');
          n_com := n_com + 1;
        end loop;
        if jsonb_array_length(liste) > 500 then
          raise exception 'Trop de commentaires sur ce bon plan.' using errcode = 'P0001';
        end if;
        base := jsonb_set(base, '{comments}', liste);
      end if;

      -- Participations : ajouts (les annulations passent par une demande explicite)
      if jsonb_typeof(p -> 'attendees') = 'array' then
        liste := case when jsonb_typeof(base -> 'attendees') = 'array' then base -> 'attendees' else '[]'::jsonb end;
        select coalesce(array_agg(x ->> 'id'), '{}') into cles from jsonb_array_elements(liste) x;
        for el in select value from jsonb_array_elements(p -> 'attendees') loop
          if (el ->> 'id') = any(cles) or (el ->> 'id') = any(ann_part) then continue; end if;
          if oc_private.est_supprime('participant', coalesce(el ->> 'id', '')) then continue; end if;
          el := oc_private.valider_participant(el);
          liste := liste || jsonb_build_array(el);
          cles := cles || (el ->> 'id');
          n_part := n_part + 1;
        end loop;
        base := jsonb_set(base, '{attendees}', liste);
      end if;

      -- Statut et réglages : modérateur uniquement, et seulement sur les fiches qu'il a modifiées
      if admin and ident = any(mod_pins) then
        st_new := p ->> 'status';
        if st_new in ('published','pending','archived') then
          base := jsonb_set(base, '{status}', to_jsonb(st_new));
        end if;
        base := jsonb_set(base, '{isPartner}', to_jsonb(oc_private.booleen(p, 'isPartner')));
        base := jsonb_set(base, '{keepPublished}', to_jsonb(oc_private.booleen(p, 'keepPublished')));
      elsif p ->> 'status' = 'archived' and base ->> 'status' = 'published'
            and not oc_private.booleen(base, 'keepPublished') and oc_private.expire(base) then
        -- archivage automatique des événements passés : autorisé pour tous
        base := jsonb_set(base, '{status}', '"archived"');
      end if;
    end if;

    res := res || base;
  end loop;

  -- Nouveaux bons plans
  lim_pins := case when ancien is null or jsonb_array_length(ancien) = 0 then 10 else 2 end;
  for p in select value from jsonb_array_elements(nouveau) loop
    ident := p ->> 'id';
    if ident = any(ids_anciens) then continue; end if;
    if oc_private.est_supprime('pin', ident) then continue; end if;
    n_pins := n_pins + 1;
    res := res || oc_private.valider_pin_nouveau(p, admin);
    ids_anciens := ids_anciens || ident;
  end loop;

  if not admin and (n_pins > lim_pins or n_com > 3 or n_notes > 3 or n_part > 3 or n_annul > 1) then
    raise exception 'Trop de modifications à la fois. Rechargez la page et réessayez.' using errcode = 'P0001';
  end if;

  insert into oc_private.supprimes (type, element) select 'commentaire', x from unnest(sup_com) x on conflict do nothing;
  insert into oc_private.supprimes (type, element) select 'participant', x from unnest(ann_part) x on conflict do nothing;

  return to_jsonb(res);
end $$;

-- ---------- Fusion : signalements ----------
create or replace function oc_private.fusion_signalements(ancien jsonb, nouveau jsonb, admin boolean)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  res jsonb[] := '{}'; client jsonb; base jsonb; r jsonb; ids text[] := '{}'; n int := 0;
begin
  if nouveau is null or jsonb_typeof(nouveau) <> 'array' then
    raise exception 'Données invalides.' using errcode = 'P0001';
  end if;
  if ancien is not null and jsonb_typeof(ancien) <> 'array' then ancien := null; end if;
  select coalesce(jsonb_object_agg(e ->> 'id', e), '{}'::jsonb) into client
  from jsonb_array_elements(nouveau) e where jsonb_typeof(e -> 'id') = 'string';

  for base in select value from jsonb_array_elements(coalesce(ancien, '[]'::jsonb)) loop
    ids := ids || (base ->> 'id');
    r := client -> (base ->> 'id');
    if admin and r is not null and r ->> 'status' = 'resolved' and base ->> 'status' = 'pending' then
      base := jsonb_set(base, '{status}', '"resolved"');
    end if;
    res := res || base;
  end loop;

  for r in select value from jsonb_array_elements(nouveau) loop
    if jsonb_typeof(r -> 'id') = 'string' and (r ->> 'id') = any(ids) then continue; end if;
    n := n + 1;
    res := res || oc_private.valider_signalement(r);
    ids := ids || (r ->> 'id');
  end loop;

  if not admin and n > 2 then
    raise exception 'Trop de signalements à la fois.' using errcode = 'P0001';
  end if;
  if cardinality(res) > 3000 then
    raise exception 'Trop de signalements enregistrés.' using errcode = 'P0001';
  end if;
  return to_jsonb(res);
end $$;

-- ---------- Fusion : photos d'un bon plan ----------
create or replace function oc_private.fusion_photos(ancien jsonb, nouveau jsonb, admin boolean)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  res jsonb[] := '{}'; anciens jsonb; base jsonb; ph jsonb; ids text[] := '{}'; ids_anciens text[];
  n int := 0; nb_vis int;
begin
  if nouveau is null or jsonb_typeof(nouveau) <> 'array' or jsonb_array_length(nouveau) > 10 then
    raise exception 'Données invalides.' using errcode = 'P0001';
  end if;
  if ancien is null or jsonb_typeof(ancien) <> 'array' then ancien := '[]'::jsonb; end if;
  select coalesce(jsonb_object_agg(x ->> 'id', x), '{}'::jsonb), coalesce(array_agg(x ->> 'id'), '{}')
    into anciens, ids_anciens from jsonb_array_elements(ancien) x;

  if admin then
    -- le modérateur envoie la liste complète voulue (suppressions et photo officielle permises)
    for ph in select value from jsonb_array_elements(nouveau) loop
      if (ph ->> 'id') = any(ids) then continue; end if;
      if (ph ->> 'id') = any(ids_anciens) then
        res := res || (anciens -> (ph ->> 'id'));
      else
        res := res || oc_private.valider_photo(ph, true);
      end if;
      ids := ids || (ph ->> 'id');
    end loop;
    insert into oc_private.supprimes (type, element)
      select 'photo', x from unnest(ids_anciens) x where not (x = any(ids)) on conflict do nothing;
  else
    for base in select value from jsonb_array_elements(ancien) loop
      res := res || base; ids := ids || (base ->> 'id');
    end loop;
    for ph in select value from jsonb_array_elements(nouveau) loop
      if (ph ->> 'id') = any(ids) then continue; end if;
      if oc_private.est_supprime('photo', coalesce(ph ->> 'id', '')) then continue; end if;
      n := n + 1;
      res := res || oc_private.valider_photo(ph, false);
      ids := ids || (ph ->> 'id');
    end loop;
    if n > 1 then raise exception 'Une seule photo à la fois.' using errcode = 'P0001'; end if;
    select count(*) into nb_vis from unnest(res) x where not oc_private.booleen(x, 'official');
    if nb_vis > 3 then raise exception 'Maximum de 3 photos atteint pour ce bon plan.' using errcode = 'P0001'; end if;
  end if;
  return to_jsonb(res);
end $$;

-- ---------- Code modérateur ----------
-- Membres de l'équipe (voir membres.sql) : codes personnels créés par l'administrateur
create table if not exists oc_private.membres (
  id                bigint generated always as identity primary key,
  nom               text not null check (char_length(btrim(nom)) between 2 and 40),
  code_hash         text not null,
  actif             boolean not null default true,
  cree_le           timestamptz not null default now(),
  derniere_activite timestamptz
);

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

create or replace function oc_private.code_valide(p_code text) returns boolean
language sql stable set search_path = '' as $$
  select oc_private.est_admin(p_code) or oc_private.membre_de(p_code) is not null
$$;

create or replace function public.oc_verifier_code(p_code text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_ip text := oc_private.ip(); ok boolean;
begin
  if (select count(*) from oc_private.ecritures
      where ip = v_ip and type = 'echec' and quand > now() - interval '15 minutes') >= 8 then
    return false;  -- trop d'essais : on ne vérifie même plus pendant 15 minutes
  end if;
  ok := oc_private.code_valide(p_code);
  if not ok then insert into oc_private.ecritures (ip, type) values (v_ip, 'echec'); end if;
  return ok;
end $$;

-- ---------- Point d'entrée unique pour enregistrer ----------
create or replace function public.oc_enregistrer(p_cle text, p_valeur text, p_code text default null, p_operations jsonb default null)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  admin boolean := false;
  v_ip text := oc_private.ip();
  ancien_txt text; ancien jsonb; nouveau jsonb; resultat jsonb;
  existe boolean; pin_id text; garder int; nb_vis int; nb_offi int;
begin
  if p_cle is null or p_valeur is null then
    raise exception 'Données manquantes.' using errcode = 'P0001';
  end if;
  if char_length(p_valeur) > 6000000 then
    raise exception 'Données trop volumineuses.' using errcode = 'P0001';
  end if;
  admin := coalesce(p_code, '') <> '' and oc_private.code_valide(p_code);

  if not admin then
    if (select count(*) from oc_private.ecritures
        where ip = v_ip and type = 'ecriture' and quand > now() - interval '10 minutes') >= 40 then
      raise exception 'Beaucoup de contributions en peu de temps : patientez quelques minutes avant de continuer.' using errcode = 'P0001';
    end if;
    if (select count(*) from oc_private.ecritures
        where type = 'ecriture' and quand > now() - interval '1 minute') >= 300 then
      raise exception 'Le site est très sollicité : réessayez dans une minute.' using errcode = 'P0001';
    end if;
  end if;
  insert into oc_private.ecritures (ip, type) values (v_ip, 'ecriture');
  delete from oc_private.ecritures where quand < now() - interval '2 days';

  begin
    nouveau := p_valeur::jsonb;
  exception when others then
    raise exception 'Données illisibles.' using errcode = 'P0001';
  end;

  select value into ancien_txt from public.kv where key = p_cle for update;
  existe := found;
  begin
    ancien := ancien_txt::jsonb;
  exception when others then
    ancien := null;
  end;

  if p_cle = 'chalons-bons-plans' then
    resultat := oc_private.fusion_pins(ancien, nouveau, admin, p_operations);
    garder := 100;
  elsif p_cle = 'chalons-reports' then
    resultat := oc_private.fusion_signalements(ancien, nouveau, admin);
    garder := 50;
  elsif p_cle ~ '^chalons-photos-(pin|seed)-[A-Za-z0-9_-]{1,48}$' then
    pin_id := substr(p_cle, 16);
    if not exists (select 1 from public.kv k, jsonb_array_elements(k.value::jsonb) e
                   where k.key = 'chalons-bons-plans' and e ->> 'id' = pin_id) then
      raise exception 'Ce bon plan n''existe plus.' using errcode = 'P0001';
    end if;
    resultat := oc_private.fusion_photos(ancien, nouveau, admin);
    garder := 2;
  else
    raise exception 'Enregistrement non autorisé.' using errcode = 'P0001';
  end if;

  if existe then
    update public.kv set value = resultat::text, updated_at = now() where key = p_cle;
  else
    insert into public.kv (key, value, updated_at) values (p_cle, resultat::text, now());
  end if;

  -- Le nombre de photos de la fiche est tenu à jour ici, pas par la page
  if pin_id is not null then
    select count(*) filter (where not oc_private.booleen(e, 'official')),
           count(*) filter (where oc_private.booleen(e, 'official'))
      into nb_vis, nb_offi from jsonb_array_elements(resultat) e;
    update public.kv k set value = (
        select jsonb_agg(case when e ->> 'id' = pin_id
                         then e || jsonb_build_object('photoCount', nb_vis, 'hasCoverPhoto', nb_offi > 0)
                         else e end order by o)::text
        from jsonb_array_elements(k.value::jsonb) with ordinality t(e, o)),
      updated_at = now()
    where k.key = 'chalons-bons-plans';
  end if;

  insert into oc_private.historique (cle, valeur, par_moderateur, ip) values (p_cle, resultat::text, admin, v_ip);
  delete from oc_private.historique h
  where h.cle = p_cle
    and h.id <= (select id from oc_private.historique where cle = p_cle order by id desc offset garder limit 1);

  return resultat::text;
end $$;

-- ---------- Restauration d'une ancienne version (depuis le SQL Editor uniquement) ----------
create or replace function oc_private.restaurer(p_id bigint) returns text
language plpgsql volatile set search_path = '' as $$
declare h record;
begin
  select * into h from oc_private.historique where id = p_id;
  if not found then raise exception 'Version introuvable.'; end if;
  update public.kv set value = h.valeur, updated_at = now() where key = h.cle;
  if not found then insert into public.kv (key, value, updated_at) values (h.cle, h.valeur, now()); end if;
  insert into oc_private.historique (cle, valeur, par_moderateur, ip) values (h.cle, h.valeur, true, 'restauration');
  return 'Version du ' || to_char(h.enregistre_le at time zone 'Europe/Paris', 'DD/MM/YYYY à HH24:MI') || ' restaurée.';
end $$;

-- ---------- Limite anti-spam sur la lettre et les alertes ----------
create or replace function oc_private.limiter_inscriptions() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_ip text := oc_private.ip();
begin
  if (select count(*) from oc_private.ecritures
      where ip = v_ip and type = tg_table_name and quand > now() - interval '1 hour') >= 10 then
    raise exception 'Trop de tentatives : réessayez plus tard.' using errcode = 'P0001';
  end if;
  insert into oc_private.ecritures (ip, type) values (v_ip, tg_table_name);
  return new;
end $$;

do $$ begin
  if to_regclass('public.newsletter') is not null then
    execute 'drop trigger if exists oc_limiter on public.newsletter';
    execute 'create trigger oc_limiter before insert on public.newsletter for each row execute function oc_private.limiter_inscriptions()';
    execute 'alter table public.newsletter drop constraint if exists newsletter_email_ok';
    execute $c$alter table public.newsletter add constraint newsletter_email_ok
             check (char_length(email) <= 254 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$') not valid$c$;
  end if;
  if to_regclass('public.push_subscriptions') is not null then
    execute 'drop trigger if exists oc_limiter on public.push_subscriptions';
    execute 'create trigger oc_limiter before insert on public.push_subscriptions for each row execute function oc_private.limiter_inscriptions()';
    execute 'alter table public.push_subscriptions drop constraint if exists push_ok';
    execute $c$alter table public.push_subscriptions add constraint push_ok
             check (endpoint ~ '^https://' and char_length(endpoint) <= 1000
                    and char_length(p256dh) <= 200 and char_length(auth) <= 100) not valid$c$;
  end if;
end $$;

-- ---------- Verrouillage de la table kv ----------
-- Sauvegarde de l'état actuel avant tout changement
insert into oc_private.historique (cle, valeur, par_moderateur, ip)
select k.key, k.value, true, 'sauvegarde initiale' from public.kv k
where not exists (select 1 from oc_private.historique h where h.cle = k.key);

alter table public.kv enable row level security;
drop policy if exists "ajout public" on public.kv;
drop policy if exists "mise a jour" on public.kv;
drop policy if exists "lecture publique" on public.kv;
create policy "lecture publique" on public.kv for select using (true);
do $$ begin
  execute 'revoke insert, update, delete, truncate on public.kv from anon, authenticated';
  execute 'grant select on public.kv to anon, authenticated';
  execute 'grant execute on function public.oc_enregistrer(text, text, text, jsonb) to anon, authenticated';
  execute 'grant execute on function public.oc_verifier_code(text) to anon, authenticated';
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';

select 'Sécurité installée. Étape suivante : choisir le code modérateur.' as resultat;
