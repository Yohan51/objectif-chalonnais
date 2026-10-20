-- =====================================================================
-- Jeu « Photo mystère » — L'Objectif Châlonnais
-- À exécuter dans Supabase : SQL Editor → coller ce fichier → Run.
--
--  - photo_mystere : une entrée par jour (photo-indice + vrai lieu).
--  - La RÉPONSE (lieu, coordonnées) n'est jamais envoyée au navigateur
--    avant que le joueur valide : elle est gardée côté serveur et révélée
--    seulement par oc_photo_mystere_repondre (anti-triche de base).
--  - Chaque réponse est enregistrée dans photo_mystere_parties (utile
--    pour un futur tirage au sort).
-- =====================================================================

-- ---------- Distance en mètres (haversine) ----------
create or replace function oc_private.dist_m(lat1 float8, lon1 float8, lat2 float8, lon2 float8)
returns float8 language sql immutable set search_path = '' as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)
  ));
$$;

-- ---------- Tables ----------
create table if not exists public.photo_mystere (
  jour         date primary key,
  lieu         text,
  lat          float8,
  lon          float8,
  photo        text,          -- URL publique de la photo-indice (détail zoomé)
  photo_pleine text,          -- URL publique de la photo complète (facultatif)
  cree_le      timestamptz default now()
);
alter table public.photo_mystere enable row level security;

create table if not exists public.photo_mystere_parties (
  id         bigint generated always as identity primary key,
  jour       date not null,
  joueur     text,            -- identifiant anonyme (localStorage)
  pseudo     text,
  distance_m int,
  score      int,
  le         timestamptz default now()
);
alter table public.photo_mystere_parties enable row level security;
create index if not exists idx_pm_parties_jour on public.photo_mystere_parties (jour);

-- ---------- La photo-indice du jour (PUBLIC, sans la réponse) ----------
create or replace function public.oc_photo_mystere_du_jour() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r record;
begin
  select * into r from public.photo_mystere where jour = (now() at time zone 'Europe/Paris')::date;
  if not found then return jsonb_build_object('existe', false); end if;
  return jsonb_build_object('existe', true, 'jour', r.jour, 'photo', r.photo, 'a_pleine', (r.photo_pleine is not null));
end $$;
grant execute on function public.oc_photo_mystere_du_jour() to anon, authenticated;

-- ---------- Répondre : enregistre la partie et révèle la réponse ----------
create or replace function public.oc_photo_mystere_repondre(p_lat float8, p_lon float8, p_joueur text, p_pseudo text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare r record; d int; sc int;
begin
  select * into r from public.photo_mystere where jour = (now() at time zone 'Europe/Paris')::date;
  if not found then return jsonb_build_object('erreur', 'Pas de photo mystère aujourd''hui.'); end if;
  if p_lat is null or p_lon is null then return jsonb_build_object('erreur', 'Réponse manquante.'); end if;
  d  := round(oc_private.dist_m(p_lat, p_lon, r.lat, r.lon));
  sc := greatest(0, round(1000 * exp(-d::float8 / 800)));
  insert into public.photo_mystere_parties (jour, joueur, pseudo, distance_m, score)
    values (r.jour, left(coalesce(p_joueur, ''), 64), left(btrim(coalesce(p_pseudo, '')), 40), d, sc);
  return jsonb_build_object('distance_m', d, 'score', sc, 'lieu', r.lieu, 'lat', r.lat, 'lon', r.lon, 'photo_pleine', r.photo_pleine);
end $$;
grant execute on function public.oc_photo_mystere_repondre(float8, float8, text, text) to anon, authenticated;

-- ---------- Définir / modifier la photo mystère d'une date (code équipe) ----------
create or replace function public.oc_photo_mystere_definir(
  p_code text, p_jour date, p_lieu text, p_lat float8, p_lon float8, p_photo text, p_photo_pleine text
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if p_jour is null then return jsonb_build_object('erreur', 'Date manquante.'); end if;
  if p_lat is null or p_lon is null then return jsonb_build_object('erreur', 'Placez le lieu sur la carte.'); end if;
  insert into public.photo_mystere (jour, lieu, lat, lon, photo, photo_pleine)
    values (p_jour, left(btrim(coalesce(p_lieu, '')), 100), p_lat, p_lon,
            left(coalesce(p_photo, ''), 300), nullif(left(coalesce(p_photo_pleine, ''), 300), ''))
  on conflict (jour) do update set
    lieu = excluded.lieu, lat = excluded.lat, lon = excluded.lon,
    photo = excluded.photo, photo_pleine = coalesce(excluded.photo_pleine, public.photo_mystere.photo_pleine);
  return jsonb_build_object('ok', true, 'jour', p_jour);
end $$;
grant execute on function public.oc_photo_mystere_definir(text, date, text, float8, float8, text, text) to anon, authenticated;

-- ---------- Lister les photos mystère (code équipe) — pour l'aperçu dans l'admin ----------
create or replace function public.oc_photo_mystere_liste(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  return coalesce((select jsonb_agg(jsonb_build_object('jour', jour, 'lieu', lieu, 'photo', photo) order by jour desc)
                   from public.photo_mystere), '[]'::jsonb);
end $$;
grant execute on function public.oc_photo_mystere_liste(text) to anon, authenticated;

do $$ begin
  if to_regclass('public.photo_mystere') is not null then raise notice 'photo mystère ✓'; end if;
end $$;
