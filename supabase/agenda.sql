-- =====================================================================
-- AGENDA « CE WEEK-END À CHÂLONS » — L'Objectif Châlonnais
-- À exécuter dans Supabase (SQL Editor → New query → Run), après
-- securite.sql (et membres.sql). Puis relancer alertes-code.sql pour
-- l'alerte automatique du vendredi. Peut être relancé sans risque.
--
--  - L'équipe ajoute les sorties (date, heure, lieu, prix, lien, photo).
--  - Le public voit les sorties publiées à venir (page Agenda, accueil).
--  - Chaque vendredi (11 h par défaut), une alerte « Ce week-end à
--    Châlons » part vers les abonnés s'il y a au moins une sortie.
--  - Membres : ajouter, modifier, masquer. Supprimer : administrateur.
-- =====================================================================

create table if not exists public.agenda (
  id          bigint generated always as identity primary key,
  titre       text not null check (char_length(btrim(titre)) between 3 and 120),
  categorie   text not null default 'autre' check (categorie in ('concert','spectacle','sport','marche','famille','expo','fete','autre')),
  jour        date not null,
  heure       time,
  jour_fin    date,
  heure_fin   time,
  lieu        text not null default '' check (char_length(lieu) <= 120),
  description text not null default '' check (char_length(description) <= 600),
  prix        text not null default '' check (char_length(prix) <= 40),
  lien        text check (lien is null or (lien ~ '^https://' and char_length(lien) <= 500)),
  photo       text check (photo is null or (char_length(photo) <= 120000 and photo ~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/]+={0,2}$')),
  publie      boolean not null default true,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now(),
  check (jour_fin is null or jour_fin >= jour)
);
create index if not exists agenda_jour_idx on public.agenda (jour);

alter table public.agenda enable row level security;
drop policy if exists "agenda public" on public.agenda;
create policy "agenda public" on public.agenda for select using (publie);
do $$ begin
  execute 'revoke all on public.agenda from anon, authenticated';
  execute 'grant select on public.agenda to anon, authenticated';
exception when undefined_object then null; end $$;

-- Réglages de l'alerte du vendredi, et week-ends déjà annoncés
create table if not exists oc_private.agenda_reglages (
  id int primary key default 1 check (id = 1),
  alerte_vendredi boolean not null default true,
  heure int not null default 11 check (heure between 6 and 22)
);
insert into oc_private.agenda_reglages (id) values (1) on conflict (id) do nothing;
create table if not exists oc_private.agenda_alertes (
  vendredi date primary key,
  envoye_le timestamptz not null default now()
);

-- Vendredi du week-end « en cours » (du lundi au jeudi : le prochain ; du vendredi au dimanche : celui-ci)
create or replace function oc_private.vendredi(d date) returns date
language sql immutable set search_path = '' as $$
  select case when extract(isodow from d) <= 4 then d + (5 - extract(isodow from d))::int
              else d - (extract(isodow from d) - 5)::int end
$$;
create or replace function oc_private.maintenant_paris() returns timestamp
language sql stable set search_path = '' as $$ select now() at time zone 'Europe/Paris' $$;
create or replace function oc_private.aujourdhui() returns date
language sql stable set search_path = '' as $$ select oc_private.maintenant_paris()::date $$;

-- ---------- Public : sorties à venir (sans les sorties passées) ----------
create or replace function public.oc_agenda_public(p_jours int default 60) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(a) - 'publie' - 'cree_le' - 'modifie_le' order by a.jour, a.heure nulls first, a.titre), '[]'::jsonb)
  from public.agenda a
  where a.publie
    and coalesce(a.jour_fin, a.jour) >= oc_private.aujourdhui()
    and a.jour <= oc_private.aujourdhui() + least(greatest(coalesce(p_jours, 60), 1), 180)
$$;

-- ---------- Équipe : liste (15 derniers jours compris) + réglages ----------
create or replace function public.oc_agenda_equipe(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  -- ménage : sorties terminées depuis plus de 6 mois
  delete from public.agenda where coalesce(jour_fin, jour) < oc_private.aujourdhui() - 180;
  delete from oc_private.agenda_alertes where vendredi < oc_private.aujourdhui() - 60;
  return jsonb_build_object(
    'evenements', coalesce((select jsonb_agg(to_jsonb(a) order by a.jour, a.heure nulls first)
                            from public.agenda a where coalesce(a.jour_fin, a.jour) >= oc_private.aujourdhui() - 15), '[]'::jsonb),
    'reglages', (select jsonb_build_object('alerte_vendredi', r.alerte_vendredi, 'heure', r.heure) from oc_private.agenda_reglages r where r.id = 1),
    'deja_annonce', exists (select 1 from oc_private.agenda_alertes where vendredi = oc_private.vendredi(oc_private.aujourdhui())),
    'vendredi', oc_private.vendredi(oc_private.aujourdhui()));
end $$;

-- ---------- Équipe : ajouter ou modifier une sortie ----------
create or replace function public.oc_agenda_enregistrer(p_code text, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  msg text := oc_private.controle_code(p_code);
  v_id bigint; v_jour date; v_fin date; v_h time; v_hf time; v_lien text; v_photo text;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if jsonb_typeof(p) <> 'object' then return jsonb_build_object('erreur', 'Sortie illisible.'); end if;
  begin
    v_jour := (p ->> 'jour')::date;
    v_fin := nullif(p ->> 'jour_fin', '')::date;
    v_h := nullif(p ->> 'heure', '')::time;
    v_hf := nullif(p ->> 'heure_fin', '')::time;
  exception when others then
    return jsonb_build_object('erreur', 'Date ou heure invalide.');
  end;
  if v_jour is null then return jsonb_build_object('erreur', 'Indiquez la date de la sortie.'); end if;
  if v_fin is not null and v_fin < v_jour then return jsonb_build_object('erreur', 'La date de fin est avant la date de début.'); end if;
  if v_fin = v_jour then v_fin := null; end if;
  v_lien := nullif(btrim(coalesce(p ->> 'lien', '')), '');
  v_photo := nullif(p ->> 'photo', '');
  v_id := nullif(p ->> 'id', '')::bigint;
  begin
    if v_id is null then
      insert into public.agenda (titre, categorie, jour, heure, jour_fin, heure_fin, lieu, description, prix, lien, photo, publie)
      values (btrim(p ->> 'titre'), coalesce(nullif(p ->> 'categorie', ''), 'autre'), v_jour, v_h, v_fin, v_hf,
              btrim(coalesce(p ->> 'lieu', '')), btrim(coalesce(p ->> 'description', '')), btrim(coalesce(p ->> 'prix', '')),
              v_lien, v_photo, coalesce((p ->> 'publie')::boolean, true))
      returning id into v_id;
    else
      update public.agenda a set
        titre = btrim(p ->> 'titre'), categorie = coalesce(nullif(p ->> 'categorie', ''), 'autre'),
        jour = v_jour, heure = v_h, jour_fin = v_fin, heure_fin = v_hf,
        lieu = btrim(coalesce(p ->> 'lieu', '')), description = btrim(coalesce(p ->> 'description', '')),
        prix = btrim(coalesce(p ->> 'prix', '')), lien = v_lien,
        photo = case when coalesce((p ->> 'garder_photo')::boolean, false) then a.photo else v_photo end,
        publie = coalesce((p ->> 'publie')::boolean, true), modifie_le = now()
      where a.id = v_id;
      if not found then return jsonb_build_object('erreur', 'Sortie introuvable.'); end if;
    end if;
  exception
    when check_violation then
      return jsonb_build_object('erreur', 'Un champ ne respecte pas le format attendu (titre de 3 à 120 caractères, lien en https://, photo trop lourde…).');
    when not_null_violation then
      return jsonb_build_object('erreur', 'Le titre est obligatoire.');
  end;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ---------- Supprimer : réservé à l'administrateur (les membres peuvent masquer) ----------
create or replace function public.oc_agenda_supprimer(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_admin(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  delete from public.agenda where id = p_id;
  return jsonb_build_object('supprime', found);
end $$;

-- ---------- Réglages de l'alerte du vendredi ----------
create or replace function public.oc_agenda_reglages(p_code text, p_alerte boolean, p_heure int) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  update oc_private.agenda_reglages set
    alerte_vendredi = coalesce(p_alerte, alerte_vendredi),
    heure = case when p_heure between 6 and 22 then p_heure else heure end
  where id = 1;
  return jsonb_build_object('ok', true);
end $$;

do $$ begin
  execute 'grant execute on function public.oc_agenda_public(int) to anon, authenticated';
  execute 'grant execute on function public.oc_agenda_equipe(text) to anon, authenticated';
  execute 'grant execute on function public.oc_agenda_enregistrer(text, jsonb) to anon, authenticated';
  execute 'grant execute on function public.oc_agenda_supprimer(text, bigint) to anon, authenticated';
  execute 'grant execute on function public.oc_agenda_reglages(text, boolean, int) to anon, authenticated';
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';
select 'Agenda installé. Relancez alertes-code.sql pour l''alerte du vendredi.' as resultat;
