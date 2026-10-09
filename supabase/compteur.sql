-- =====================================================================
-- Compteur de visites — L'Objectif Châlonnais
-- À exécuter dans Supabase (SQL Editor → New query → Run),
-- après securite.sql et actus.sql. Peut être relancé sans risque.
--
-- Mesure d'audience anonyme : ni cookie, ni adresse IP conservée,
-- ni identifiant de visiteur. On compte seulement, par jour et par page :
--   - vues    : nombre de pages affichées
--   - visites : nombre de visites (une visite = un onglet ouvert sur le site,
--               quel que soit le nombre de pages vues ensuite)
-- =====================================================================

create table if not exists public.visites (
  jour    date not null,
  page    text not null check (page ~ '^[a-z0-9-]{1,40}$'),
  vues    integer not null default 0,
  visites integer not null default 0,
  primary key (jour, page)
);
alter table public.visites enable row level security;
revoke all on public.visites from anon, authenticated;

-- Anti-gonflage : 600 pages par heure et par connexion au maximum.
-- Seule une empreinte de l'adresse IP est utilisée, effacée au bout d'un jour.
create table if not exists oc_private.vues_ip (
  ip    text not null,
  heure timestamptz not null,
  n     integer not null default 0,
  primary key (ip, heure)
);

-- ---------- Enregistrer une page vue (appelé par compteur.js) ----------
create or replace function public.oc_visite(p_page text, p_nouvelle boolean) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_ip text := oc_private.ip();
  v_heure timestamptz := date_trunc('hour', now());
  v_jour date := (now() at time zone 'Europe/Paris')::date;
  v_page text := lower(coalesce(p_page, ''));
  v_n integer;
begin
  if v_page not in ('accueil', 'actus', 'jeux', 'bons-plans', 'galerie', 'quiz', 'mentions-legales') then
    return;
  end if;

  insert into oc_private.vues_ip as v (ip, heure, n) values (v_ip, v_heure, 1)
  on conflict (ip, heure) do update set n = v.n + 1
  returning n into v_n;
  if v_n > 600 then return; end if;

  insert into public.visites as t (jour, page, vues, visites)
  values (v_jour, v_page, 1, case when coalesce(p_nouvelle, false) then 1 else 0 end)
  on conflict (jour, page) do update
    set vues = t.vues + 1, visites = t.visites + excluded.visites;

  -- ménage de temps en temps
  if random() < 0.02 then
    delete from oc_private.vues_ip where heure < now() - interval '1 day';
  end if;
end $$;

-- ---------- Total public (affiché sur l'accueil) ----------
create or replace function public.oc_compteur() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'visites', coalesce(sum(visites), 0),
    'vues', coalesce(sum(vues), 0),
    'depuis', min(jour))
  from public.visites;
$$;

-- ---------- Statistiques détaillées (équipe, avec le code modérateur) ----------
create or replace function public.oc_stats(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
  v_jour date := (now() at time zone 'Europe/Paris')::date;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  return jsonb_build_object(
    'aujourdhui', v_jour,
    'total', (select jsonb_build_object('visites', coalesce(sum(visites), 0), 'vues', coalesce(sum(vues), 0), 'depuis', min(jour)) from public.visites),
    'jours', coalesce((
      select jsonb_agg(jsonb_build_object('jour', d.jour, 'visites', d.visites, 'vues', d.vues) order by d.jour)
      from (
        select g.jour::date as jour,
               coalesce(sum(v.visites), 0) as visites,
               coalesce(sum(v.vues), 0) as vues
        from generate_series(v_jour - 59, v_jour, interval '1 day') as g(jour)
        left join public.visites v on v.jour = g.jour::date
        group by g.jour
      ) d), '[]'::jsonb),
    'pages', coalesce((
      select jsonb_agg(jsonb_build_object('page', p.page, 'vues', p.vues) order by p.vues desc)
      from (
        select page, sum(vues) as vues from public.visites
        where jour > v_jour - 30 group by page
      ) p), '[]'::jsonb)
  );
end $$;

do $$ begin
  execute 'grant execute on function public.oc_visite(text, boolean) to anon, authenticated';
  execute 'grant execute on function public.oc_compteur() to anon, authenticated';
  execute 'grant execute on function public.oc_stats(text) to anon, authenticated';
end $$;

notify pgrst, 'reload schema';
