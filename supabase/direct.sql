-- =====================================================================
-- LES DIRECTS (YouTube + Facebook) — version 2 — L'Objectif Châlonnais
-- À exécuter dans Supabase (SQL Editor → New query → Run), après
-- securite.sql. Peut être relancé sans risque.
--
--  - Le public voit si un direct est en cours (bandeau sur l'accueil,
--    page Direct) et la date du prochain direct annoncé.
--  - Le direct peut venir de YouTube ou de Facebook (lien collé dans la
--    régie) ; dans les deux cas il se regarde sur le site.
--  - L'équipe (administrateur ou membre) lance et termine le direct
--    depuis l'Espace équipe. Au lancement, une alerte part vers les
--    abonnés (voir alertes-code.sql) — une seule par direct.
-- =====================================================================

create table if not exists public.direct (
  id             int primary key default 1 check (id = 1),
  en_direct      boolean not null default false,
  titre          text not null default '' check (char_length(titre) <= 120),
  video_id       text check (video_id is null or video_id ~ '^[A-Za-z0-9_-]{11}$'),
  debut          timestamptz,
  alerte_auto    boolean not null default true,
  alerte_le      timestamptz,
  prochain_titre text not null default '' check (char_length(prochain_titre) <= 120),
  prochain_le    timestamptz,
  maj            timestamptz not null default now()
);
insert into public.direct (id) values (1) on conflict (id) do nothing;
-- Direct Facebook : lien de la vidéo en direct sur la page Facebook
alter table public.direct add column if not exists lien_fb text
  check (lien_fb is null or (char_length(lien_fb) <= 500 and lien_fb ~ '^https://([a-z]+\.)?(facebook\.com|fb\.watch)/'));

alter table public.direct enable row level security;
drop policy if exists "direct public" on public.direct;
create policy "direct public" on public.direct for select using (true);
do $$ begin
  execute 'revoke all on public.direct from anon, authenticated';
  execute 'grant select on public.direct to anon, authenticated';
exception when undefined_object then null; end $$;

-- ---------- Lancer le direct (ou mettre à jour le titre / le lien pendant le direct) ----------
create or replace function public.oc_direct_lancer(p_code text, p_titre text, p_video text, p_alerte boolean)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code); v_video text := nullif(btrim(coalesce(p_video, '')), ''); v_fb text;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  -- p_video : identifiant YouTube (11 caractères) ou lien Facebook complet
  if v_video ~ '^https://([a-z]+\.)?(facebook\.com|fb\.watch)/' then
    if char_length(v_video) > 500 then return jsonb_build_object('erreur', 'Lien Facebook trop long.'); end if;
    v_fb := v_video; v_video := null;
  elsif v_video is not null and v_video !~ '^[A-Za-z0-9_-]{11}$' then
    return jsonb_build_object('erreur', 'Lien non reconnu. Copiez le lien du direct YouTube (youtube.com/live/…) ou Facebook (facebook.com/…/videos/…).');
  end if;
  update public.direct d set
    titre = left(btrim(coalesce(p_titre, '')), 120),
    video_id = v_video,
    lien_fb = v_fb,
    alerte_auto = coalesce(p_alerte, true),
    -- un direct déjà en cours garde son heure de début et son alerte
    debut = case when d.en_direct and d.debut > now() - interval '8 hours' then d.debut else now() end,
    -- relancé moins de 30 min après le précédent (coupure réseau…) : pas de nouvelle alerte
    alerte_le = case when d.alerte_le > now() - interval '30 minutes' then d.alerte_le else null end,
    en_direct = true,
    -- le direct annoncé a lieu : on retire l'annonce
    prochain_titre = case when d.prochain_le < now() + interval '3 hours' then '' else d.prochain_titre end,
    prochain_le    = case when d.prochain_le < now() + interval '3 hours' then null else d.prochain_le end,
    maj = now()
  where d.id = 1;
  return (select to_jsonb(d) from public.direct d where d.id = 1);
end $$;

-- ---------- Terminer le direct ----------
create or replace function public.oc_direct_arreter(p_code text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  update public.direct set en_direct = false, maj = now() where id = 1;
  return (select to_jsonb(d) from public.direct d where d.id = 1);
end $$;

-- ---------- Annoncer le prochain direct (p_le vide = retirer l'annonce) ----------
create or replace function public.oc_direct_prochain(p_code text, p_titre text, p_le timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if p_le is not null and p_le < now() - interval '1 hour' then
    return jsonb_build_object('erreur', 'Cette date est déjà passée.');
  end if;
  update public.direct set
    prochain_titre = case when p_le is null then '' else left(btrim(coalesce(p_titre, '')), 120) end,
    prochain_le = p_le, maj = now()
  where id = 1;
  return (select to_jsonb(d) from public.direct d where d.id = 1);
end $$;

do $$ begin
  execute 'grant execute on function public.oc_direct_lancer(text, text, text, boolean) to anon, authenticated';
  execute 'grant execute on function public.oc_direct_arreter(text) to anon, authenticated';
  execute 'grant execute on function public.oc_direct_prochain(text, text, timestamptz) to anon, authenticated';
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';
-- Vérification : la version installée accepte bien YouTube ET Facebook
select case
  when position('facebook' in pg_get_functiondef('public.oc_direct_lancer(text,text,text,boolean)'::regprocedure)) > 0
  then 'Directs installés : YouTube + Facebook ✓ (relancez alertes-code.sql si ce n''est pas déjà fait)'
  else 'ATTENTION : ancienne version encore active, relancez ce fichier en entier'
end as resultat;
