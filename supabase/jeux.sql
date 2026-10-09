-- =====================================================================
-- JEUX CONCOURS — L'Objectif Châlonnais
--
-- À coller EN ENTIER dans Supabase : SQL Editor → New query → Run.
-- Nécessite securite.sql (code modérateur). Peut être relancé sans risque.
--
--  - Le public voit les jeux publiés, le nombre de participants et les
--    gagnants (prénom + initiale). Jamais les coordonnées.
--  - Pour participer : être abonné aux alertes sur son appareil,
--    accepter le règlement, une seule participation par e-mail et par
--    téléphone. Anti-spam : 20 participations par connexion et par heure.
--  - L'équipe (code modérateur) crée les jeux, récupère la liste des
--    participants pour le tirage, publie les gagnants et efface les
--    coordonnées après le jeu.
-- =====================================================================

create table if not exists public.jeux (
  id bigserial primary key,
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 90),
  titre text not null check (char_length(btrim(titre)) between 3 and 120),
  lot text not null default '' check (char_length(lot) <= 200),
  description text not null default '' check (char_length(description) <= 3000),
  reglement text not null default '' check (char_length(reglement) <= 6000),
  photo text check (photo is null or (char_length(photo) <= 600000 and photo ~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/]+={0,2}$')),
  miniature text check (miniature is null or (char_length(miniature) <= 120000 and miniature ~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/]+={0,2}$')),
  date_fin timestamptz not null,
  nb_gagnants int not null default 1 check (nb_gagnants between 1 and 50),
  publie boolean not null default false,
  gagnants jsonb not null default '[]'::jsonb check (jsonb_typeof(gagnants) = 'array'),
  tire_le timestamptz,
  coordonnees_effacees boolean not null default false,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now()
);

create table if not exists public.participations (
  id bigserial primary key,
  jeu_id bigint not null references public.jeux(id) on delete cascade,
  prenom text not null check (char_length(btrim(prenom)) between 1 and 40),
  nom text not null check (char_length(btrim(nom)) between 1 and 60),
  email text not null check (char_length(email) <= 254 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  telephone text not null check (telephone ~ '^0[1-9][0-9]{8}$'),
  cree_le timestamptz not null default now(),
  unique (jeu_id, email),
  unique (jeu_id, telephone)
);
create index if not exists participations_jeu_idx on public.participations (jeu_id);

alter table public.jeux enable row level security;
alter table public.participations enable row level security;
drop policy if exists "jeux publies" on public.jeux;
create policy "jeux publies" on public.jeux for select using (publie);
-- participations : aucune règle = aucun accès direct pour le public

do $$ begin
  execute 'revoke all on public.jeux from anon, authenticated';
  execute 'revoke all on public.participations from anon, authenticated';
  execute 'grant select on public.jeux to anon, authenticated';
exception when undefined_object then null; end $$;

-- ---------- Contrôle du code modérateur (identique à actus.sql) ----------
create or replace function oc_private.controle_code(p_code text) returns text
language plpgsql volatile set search_path = '' as $$
declare v_ip text := oc_private.ip();
begin
  if (select count(*) from oc_private.ecritures
      where ip = v_ip and type = 'echec' and quand > now() - interval '15 minutes') >= 8 then
    return 'Trop d''essais ratés : patientez 15 minutes.';
  end if;
  if not oc_private.code_valide(p_code) then
    insert into oc_private.ecritures (ip, type) values (v_ip, 'echec');
    return 'Code modérateur incorrect.';
  end if;
  return null;
end $$;

-- ---------- Public : nombre de participants ----------
create or replace function public.oc_jeu_nb_participants(p_jeu_id bigint) returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.participations p
  join public.jeux j on j.id = p.jeu_id and j.publie
  where p.jeu_id = p_jeu_id
$$;

-- ---------- Public : participer ----------
create or replace function public.oc_jeu_participer(
  p_jeu_id bigint, p_prenom text, p_nom text, p_email text, p_telephone text,
  p_endpoint text, p_reglement boolean
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_ip text := oc_private.ip();
  j record; tel text; mail text;
begin
  -- anti-spam : 20 participations par connexion internet et par heure
  -- (sur mobile, plusieurs abonnés partagent parfois la même adresse IP)
  if (select count(*) from oc_private.ecritures
      where ip = v_ip and type = 'jeu' and quand > now() - interval '1 hour') >= 20 then
    return jsonb_build_object('erreur', 'Trop de participations depuis cette connexion. Réessayez dans une heure.');
  end if;

  select * into j from public.jeux where id = p_jeu_id and publie;
  if not found then return jsonb_build_object('erreur', 'Ce jeu n''existe pas.'); end if;
  if j.tire_le is not null or now() >= j.date_fin then
    return jsonb_build_object('erreur', 'Ce jeu est terminé : les participations sont closes.');
  end if;
  if not coalesce(p_reglement, false) then
    return jsonb_build_object('erreur', 'Vous devez accepter le règlement pour participer.');
  end if;
  if coalesce(p_endpoint, '') = '' or not exists (select 1 from public.push_subscriptions s where s.endpoint = p_endpoint) then
    return jsonb_build_object('erreur', 'Pour participer, activez d''abord les alertes de L''Objectif Châlonnais sur cet appareil.');
  end if;

  mail := lower(btrim(coalesce(p_email, '')));
  tel := regexp_replace(coalesce(p_telephone, ''), '[\s.\-()]', '', 'g');
  tel := regexp_replace(tel, '^(\+33|0033)', '0');
  if mail !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(mail) > 254 then
    return jsonb_build_object('erreur', 'Adresse e-mail invalide.');
  end if;
  if tel !~ '^0[1-9][0-9]{8}$' then
    return jsonb_build_object('erreur', 'Numéro de téléphone invalide (10 chiffres, par exemple 06 12 34 56 78).');
  end if;
  if char_length(btrim(coalesce(p_prenom, ''))) not between 1 and 40 or char_length(btrim(coalesce(p_nom, ''))) not between 1 and 60 then
    return jsonb_build_object('erreur', 'Indiquez votre prénom et votre nom.');
  end if;

  if exists (select 1 from public.participations where jeu_id = j.id and (email = mail or telephone = tel)) then
    return jsonb_build_object('erreur', 'Vous participez déjà à ce jeu avec cet e-mail ou ce numéro. Bonne chance !');
  end if;

  insert into public.participations (jeu_id, prenom, nom, email, telephone)
  values (j.id, btrim(p_prenom), btrim(p_nom), mail, tel);
  insert into oc_private.ecritures (ip, type) values (v_ip, 'jeu');

  return jsonb_build_object('ok', true, 'total', (select count(*) from public.participations where jeu_id = j.id));
exception when unique_violation then
  return jsonb_build_object('erreur', 'Vous participez déjà à ce jeu avec cet e-mail ou ce numéro. Bonne chance !');
end $$;

-- ---------- Équipe : liste des jeux (brouillons compris) ----------
create or replace function public.oc_jeux_equipe(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  perform oc_private.purger_jeux();
  return jsonb_build_object('jeux', coalesce((
    select jsonb_agg(to_jsonb(j) - 'photo' || jsonb_build_object(
      'participants', (select count(*) from public.participations p where p.jeu_id = j.id))
      order by j.date_fin desc)
    from public.jeux j), '[]'::jsonb));
end $$;

-- ---------- Équipe : lire un jeu complet ----------
create or replace function public.oc_jeu_lire(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); r jsonb;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  select to_jsonb(j) into r from public.jeux j where j.id = p_id;
  if r is null then return jsonb_build_object('erreur', 'Jeu introuvable.'); end if;
  return jsonb_build_object('jeu', r);
end $$;

-- ---------- Équipe : créer ou modifier un jeu ----------
create or replace function public.oc_jeu_enregistrer(p_code text, p_jeu jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  msg text := oc_private.controle_code(p_code);
  v_id bigint; base_slug text; v_slug text; n int := 1; v_fin timestamptz; garder boolean;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  v_id := nullif(p_jeu ->> 'id', '')::bigint;
  base_slug := left(btrim(regexp_replace(lower(coalesce(p_jeu ->> 'slug', '')), '[^a-z0-9]+', '-', 'g'), '-'), 80);
  base_slug := btrim(base_slug, '-');
  if base_slug = '' then base_slug := 'jeu'; end if;
  v_slug := base_slug;
  while exists (select 1 from public.jeux j where j.slug = v_slug and j.id is distinct from v_id) loop
    n := n + 1; v_slug := base_slug || '-' || n;
  end loop;
  begin
    v_fin := (p_jeu ->> 'date_fin')::timestamptz;
  exception when others then
    return jsonb_build_object('erreur', 'Date de fin invalide.');
  end;
  if v_fin is null then return jsonb_build_object('erreur', 'Indiquez la date de fin du jeu.'); end if;
  garder := coalesce((p_jeu ->> 'garder_photo')::boolean, false);

  begin
    if v_id is null then
      insert into public.jeux (slug, titre, lot, description, reglement, photo, miniature, date_fin, nb_gagnants, publie)
      values (v_slug, btrim(p_jeu ->> 'titre'), coalesce(p_jeu ->> 'lot', ''), coalesce(p_jeu ->> 'description', ''),
              coalesce(p_jeu ->> 'reglement', ''), nullif(p_jeu ->> 'photo', ''), nullif(p_jeu ->> 'miniature', ''),
              v_fin, coalesce((p_jeu ->> 'nb_gagnants')::int, 1), coalesce((p_jeu ->> 'publie')::boolean, false))
      returning id into v_id;
    else
      update public.jeux j set
        slug = v_slug, titre = btrim(p_jeu ->> 'titre'), lot = coalesce(p_jeu ->> 'lot', ''),
        description = coalesce(p_jeu ->> 'description', ''), reglement = coalesce(p_jeu ->> 'reglement', ''),
        photo = case when garder then j.photo else nullif(p_jeu ->> 'photo', '') end,
        miniature = case when garder then j.miniature else nullif(p_jeu ->> 'miniature', '') end,
        date_fin = v_fin, nb_gagnants = coalesce((p_jeu ->> 'nb_gagnants')::int, 1),
        publie = coalesce((p_jeu ->> 'publie')::boolean, false), modifie_le = now()
      where j.id = v_id;
      if not found then return jsonb_build_object('erreur', 'Jeu introuvable.'); end if;
    end if;
  exception
    when check_violation then
      return jsonb_build_object('erreur', 'Un champ ne respecte pas le format attendu (titre de 3 à 120 caractères, 1 à 50 gagnants, photo trop lourde…).');
    when not_null_violation then
      return jsonb_build_object('erreur', 'Le titre est obligatoire.');
    when invalid_text_representation then
      return jsonb_build_object('erreur', 'Nombre de gagnants invalide.');
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end $$;

-- ---------- Équipe : participants d'un jeu (pour le tirage) ----------
create or replace function public.oc_jeu_participants(p_code text, p_jeu_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  return jsonb_build_object('participants', coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'prenom', p.prenom, 'nom', p.nom,
                                        'email', p.email, 'telephone', p.telephone, 'cree_le', p.cree_le)
                     order by p.cree_le)
    from public.participations p where p.jeu_id = p_jeu_id), '[]'::jsonb));
end $$;

-- ---------- Équipe : publier les gagnants ----------
-- p_gagnants : liste des identifiants de participation tirés au sort.
-- Seuls « Prénom N. » sont publiés.
create or replace function public.oc_jeu_publier_gagnants(p_code text, p_jeu_id bigint, p_gagnants jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); liste jsonb;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if jsonb_typeof(p_gagnants) <> 'array' or jsonb_array_length(p_gagnants) = 0 then
    return jsonb_build_object('erreur', 'Aucun gagnant à publier.');
  end if;
  select coalesce(jsonb_agg(btrim(p.prenom) || ' ' || upper(left(btrim(p.nom), 1)) || '.' order by o), '[]'::jsonb)
    into liste
  from jsonb_array_elements_text(p_gagnants) with ordinality g(pid, o)
  join public.participations p on p.id = g.pid::bigint and p.jeu_id = p_jeu_id;
  if jsonb_array_length(liste) = 0 then return jsonb_build_object('erreur', 'Gagnants introuvables pour ce jeu.'); end if;
  update public.jeux set gagnants = liste, tire_le = now(), modifie_le = now() where id = p_jeu_id;
  return jsonb_build_object('gagnants', liste);
end $$;

-- ---------- Équipe : effacer les coordonnées (après remise des lots) ----------
create or replace function public.oc_jeu_effacer_participants(p_code text, p_jeu_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); n int;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  delete from public.participations where jeu_id = p_jeu_id;
  get diagnostics n = row_count;
  update public.jeux set coordonnees_effacees = true where id = p_jeu_id;
  return jsonb_build_object('effaces', n);
end $$;

-- ---------- Équipe : supprimer un jeu ----------
create or replace function public.oc_jeu_supprimer(p_code text, p_jeu_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  delete from public.jeux where id = p_jeu_id;
  return jsonb_build_object('supprime', found);
end $$;

-- Effacement automatique des coordonnées 3 mois après le tirage
create or replace function oc_private.purger_jeux() returns void
language sql volatile set search_path = '' as $$
  delete from public.participations p using public.jeux j
  where p.jeu_id = j.id and j.tire_le is not null and j.tire_le < now() - interval '3 months';
  update public.jeux set coordonnees_effacees = true
  where tire_le is not null and tire_le < now() - interval '3 months' and not coordonnees_effacees;
$$;

do $$ begin
  execute 'grant execute on function public.oc_jeu_nb_participants(bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_jeu_participer(bigint, text, text, text, text, text, boolean) to anon, authenticated';
  execute 'grant execute on function public.oc_jeux_equipe(text) to anon, authenticated';
  execute 'grant execute on function public.oc_jeu_lire(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_jeu_enregistrer(text, jsonb) to anon, authenticated';
  execute 'grant execute on function public.oc_jeu_participants(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_jeu_publier_gagnants(text, bigint, jsonb) to anon, authenticated';
  execute 'grant execute on function public.oc_jeu_effacer_participants(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_jeu_supprimer(text, bigint) to anon, authenticated';
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';
select 'Jeux concours installés.' as resultat;
