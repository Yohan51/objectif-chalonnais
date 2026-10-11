-- =====================================================================
-- « ENVOYEZ-NOUS VOTRE INFO » — L'Objectif Châlonnais
-- À exécuter dans Supabase (SQL Editor → New query → Run), après
-- securite.sql. Peut être relancé sans risque.
--
--  - Le public propose une info, un événement ou des photos (3 au plus),
--    avec un contact facultatif. Rien n'est publié automatiquement.
--  - Les propositions sont privées : seule l'équipe (administrateur et
--    membres) peut les lire, les classer et les supprimer.
--  - Anti-abus : 4 propositions par heure et 12 par jour par connexion.
--  - Effacement automatique 6 mois après l'envoi.
-- =====================================================================

create table if not exists oc_private.propositions (
  id          bigint generated always as identity primary key,
  type        text not null default 'info' check (type in ('info', 'evenement', 'photo')),
  titre       text not null check (char_length(titre) between 3 and 120),
  texte       text not null default '' check (char_length(texte) <= 4000),
  lieu        text not null default '' check (char_length(lieu) <= 120),
  date_evenement date,
  nom         text not null default '' check (char_length(nom) <= 60),
  contact     text not null default '' check (char_length(contact) <= 120),
  photos      jsonb not null default '[]'::jsonb check (jsonb_typeof(photos) = 'array' and jsonb_array_length(photos) <= 3),
  statut      text not null default 'nouvelle' check (statut in ('nouvelle', 'vue', 'traitee')),
  note        text not null default '' check (char_length(note) <= 500),
  cree_le     timestamptz not null default now()
);
create index if not exists propositions_cree_idx on oc_private.propositions (cree_le desc);

-- ---------- Outils (identiques à chat.sql) ----------
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

create or replace function oc_private.purger_propositions() returns void
language sql volatile set search_path = '' as $$
  delete from oc_private.propositions where cree_le < now() - interval '6 months';
$$;

-- ---------- Public : envoyer une proposition ----------
create or replace function public.oc_proposer(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_titre text := oc_private.texte_propre(p ->> 'titre');
  v_texte text := oc_private.texte_propre(p ->> 'texte');
  v_photos jsonb := coalesce(p -> 'photos', '[]'::jsonb);
  v_date date;
  ph jsonb;
begin
  if jsonb_typeof(p) <> 'object' then return jsonb_build_object('erreur', 'Envoi illisible.'); end if;
  -- champ piège invisible : rempli seulement par les robots
  if coalesce(p ->> 'site', '') <> '' then return jsonb_build_object('ok', true); end if;
  if coalesce((p ->> 'accord')::boolean, false) is not true then
    return jsonb_build_object('erreur', 'Merci de cocher la case d''accord avant d''envoyer.');
  end if;
  if char_length(v_titre) < 3 then return jsonb_build_object('erreur', 'Donnez un titre à votre info (3 caractères au moins).'); end if;
  if char_length(v_titre) > 120 or char_length(v_texte) > 4000 then return jsonb_build_object('erreur', 'Texte trop long.'); end if;
  if char_length(v_texte) < 10 and jsonb_array_length(case when jsonb_typeof(v_photos) = 'array' then v_photos else '[]'::jsonb end) = 0 then
    return jsonb_build_object('erreur', 'Racontez-nous en quelques mots, ou joignez une photo.');
  end if;
  if jsonb_typeof(v_photos) <> 'array' or jsonb_array_length(v_photos) > 3 then
    return jsonb_build_object('erreur', '3 photos au maximum.');
  end if;
  for ph in select * from jsonb_array_elements(v_photos) loop
    if jsonb_typeof(ph) <> 'string' or char_length(ph #>> '{}') > 450000
       or (ph #>> '{}') !~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/]+={0,2}$' then
      return jsonb_build_object('erreur', 'Une photo n''a pas pu être préparée : réessayez avec une autre photo.');
    end if;
  end loop;
  begin
    v_date := nullif(p ->> 'date_evenement', '')::date;
  exception when others then
    return jsonb_build_object('erreur', 'Date de l''événement invalide.');
  end;
  if not oc_private.limite('proposition_h', 4, 60) or not oc_private.limite('proposition_j', 12, 1440) then
    return jsonb_build_object('erreur', 'Vous nous avez déjà envoyé plusieurs infos : merci ! Réessayez un peu plus tard.');
  end if;
  insert into oc_private.propositions (type, titre, texte, lieu, date_evenement, nom, contact, photos)
  values (
    case when p ->> 'type' in ('info', 'evenement', 'photo') then p ->> 'type' else 'info' end,
    v_titre, v_texte,
    left(oc_private.texte_propre(p ->> 'lieu'), 120),
    v_date,
    left(oc_private.texte_propre(p ->> 'nom'), 60),
    left(oc_private.texte_propre(p ->> 'contact'), 120),
    v_photos
  );
  perform oc_private.purger_propositions();
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Équipe : liste (sans les photos) ----------
create or replace function public.oc_propositions_liste(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  perform oc_private.purger_propositions();
  return jsonb_build_object(
    'nouvelles', (select count(*) from oc_private.propositions where statut = 'nouvelle'),
    'propositions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'type', type, 'titre', titre, 'extrait', left(texte, 160), 'lieu', lieu,
        'date_evenement', date_evenement, 'nom', nom, 'statut', statut, 'cree_le', cree_le,
        'nb_photos', jsonb_array_length(photos)) order by cree_le desc)
      from oc_private.propositions), '[]'::jsonb));
end $$;

-- ---------- Équipe : lire une proposition (la marque « vue ») ----------
create or replace function public.oc_proposition_lire(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); r jsonb;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  update oc_private.propositions set statut = 'vue' where id = p_id and statut = 'nouvelle';
  select to_jsonb(x) into r from oc_private.propositions x where x.id = p_id;
  if r is null then return jsonb_build_object('erreur', 'Proposition introuvable (déjà supprimée ?).'); end if;
  return jsonb_build_object('proposition', r);
end $$;

-- ---------- Équipe : classer (statut et note interne) ----------
create or replace function public.oc_proposition_classer(p_code text, p_id bigint, p_statut text, p_note text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if p_statut is not null and p_statut not in ('nouvelle', 'vue', 'traitee') then return jsonb_build_object('erreur', 'Statut inconnu.'); end if;
  update oc_private.propositions set
    statut = coalesce(p_statut, statut),
    note = coalesce(left(oc_private.texte_propre(p_note), 500), note)
  where id = p_id;
  if not found then return jsonb_build_object('erreur', 'Proposition introuvable.'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Équipe : supprimer (membres compris, comme la messagerie) ----------
create or replace function public.oc_proposition_supprimer(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  delete from oc_private.propositions where id = p_id;
  return jsonb_build_object('supprime', found);
end $$;

do $$ begin
  execute 'grant execute on function public.oc_proposer(jsonb) to anon, authenticated';
  execute 'grant execute on function public.oc_propositions_liste(text) to anon, authenticated';
  execute 'grant execute on function public.oc_proposition_lire(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_proposition_classer(text, bigint, text, text) to anon, authenticated';
  execute 'grant execute on function public.oc_proposition_supprimer(text, bigint) to anon, authenticated';
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';
select '« Envoyez-nous votre info » installé.' as resultat;
