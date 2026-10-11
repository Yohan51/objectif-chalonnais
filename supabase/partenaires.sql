-- =====================================================================
-- NOS PARTENAIRES — L'Objectif Châlonnais
-- À exécuter dans Supabase (SQL Editor → New query → Run), après
-- securite.sql et membres.sql. Peut être relancé sans risque.
--
--  - Le public voit les partenaires actifs (page Partenaires, accueil).
--  - L'équipe ajoute, modifie et masque les partenaires ;
--    supprimer est réservé à l'administrateur.
-- =====================================================================

create table if not exists public.partenaires (
  id          bigint generated always as identity primary key,
  nom         text not null check (char_length(btrim(nom)) between 2 and 80),
  activite    text not null default '' check (char_length(activite) <= 60),
  description text not null default '' check (char_length(description) <= 500),
  offre       text not null default '' check (char_length(offre) <= 160),
  logo        text check (logo is null or (char_length(logo) <= 160000 and logo ~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/]+={0,2}$')),
  adresse     text not null default '' check (char_length(adresse) <= 140),
  telephone   text not null default '' check (char_length(telephone) <= 30),
  site        text check (site is null or (site ~ '^https://' and char_length(site) <= 300)),
  facebook    text check (facebook is null or (facebook ~ '^https://' and char_length(facebook) <= 300)),
  instagram   text check (instagram is null or (instagram ~ '^https://' and char_length(instagram) <= 300)),
  niveau      text not null default 'partenaire' check (niveau in ('principal', 'partenaire', 'soutien')),
  ordre       int not null default 100,
  actif       boolean not null default true,
  depuis      date,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);

alter table public.partenaires enable row level security;
drop policy if exists "partenaires publics" on public.partenaires;
create policy "partenaires publics" on public.partenaires for select using (actif);
do $$ begin
  execute 'revoke all on public.partenaires from anon, authenticated';
  execute 'grant select on public.partenaires to anon, authenticated';
exception when undefined_object then null; end $$;

-- ---------- Public ----------
create or replace function public.oc_partenaires_public() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(p) - 'actif' - 'cree_le' - 'modifie_le' - 'ordre'
           order by case p.niveau when 'principal' then 0 when 'partenaire' then 1 else 2 end, p.ordre, p.nom), '[]'::jsonb)
  from public.partenaires p where p.actif
$$;

-- ---------- Équipe : liste complète ----------
create or replace function public.oc_partenaires_equipe(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_code(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  return jsonb_build_object('partenaires', coalesce((
    select jsonb_agg(to_jsonb(p) order by p.actif desc, case p.niveau when 'principal' then 0 when 'partenaire' then 1 else 2 end, p.ordre, p.nom)
    from public.partenaires p), '[]'::jsonb));
end $$;

-- ---------- Équipe : ajouter ou modifier ----------
create or replace function public.oc_partenaire_enregistrer(p_code text, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  msg text := oc_private.controle_code(p_code);
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_depuis date;
  lien text;
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  if jsonb_typeof(p) <> 'object' then return jsonb_build_object('erreur', 'Fiche illisible.'); end if;
  begin v_depuis := nullif(p ->> 'depuis', '')::date;
  exception when others then return jsonb_build_object('erreur', 'Date invalide.'); end;
  foreach lien in array array['site', 'facebook', 'instagram'] loop
    if nullif(btrim(coalesce(p ->> lien, '')), '') is not null and (p ->> lien) !~ '^https://' then
      return jsonb_build_object('erreur', 'Les liens doivent commencer par https://');
    end if;
  end loop;
  begin
    if v_id is null then
      insert into public.partenaires (nom, activite, description, offre, logo, adresse, telephone, site, facebook, instagram, niveau, ordre, actif, depuis)
      values (btrim(p ->> 'nom'), btrim(coalesce(p ->> 'activite', '')), btrim(coalesce(p ->> 'description', '')), btrim(coalesce(p ->> 'offre', '')),
              nullif(p ->> 'logo', ''), btrim(coalesce(p ->> 'adresse', '')), btrim(coalesce(p ->> 'telephone', '')),
              nullif(btrim(coalesce(p ->> 'site', '')), ''), nullif(btrim(coalesce(p ->> 'facebook', '')), ''), nullif(btrim(coalesce(p ->> 'instagram', '')), ''),
              coalesce(nullif(p ->> 'niveau', ''), 'partenaire'), coalesce(nullif(p ->> 'ordre', '')::int, 100),
              coalesce((p ->> 'actif')::boolean, true), v_depuis)
      returning id into v_id;
    else
      update public.partenaires x set
        nom = btrim(p ->> 'nom'), activite = btrim(coalesce(p ->> 'activite', '')),
        description = btrim(coalesce(p ->> 'description', '')), offre = btrim(coalesce(p ->> 'offre', '')),
        logo = case when coalesce((p ->> 'garder_logo')::boolean, false) then x.logo else nullif(p ->> 'logo', '') end,
        adresse = btrim(coalesce(p ->> 'adresse', '')), telephone = btrim(coalesce(p ->> 'telephone', '')),
        site = nullif(btrim(coalesce(p ->> 'site', '')), ''), facebook = nullif(btrim(coalesce(p ->> 'facebook', '')), ''),
        instagram = nullif(btrim(coalesce(p ->> 'instagram', '')), ''),
        niveau = coalesce(nullif(p ->> 'niveau', ''), 'partenaire'), ordre = coalesce(nullif(p ->> 'ordre', '')::int, 100),
        actif = coalesce((p ->> 'actif')::boolean, true), depuis = v_depuis, modifie_le = now()
      where x.id = v_id;
      if not found then return jsonb_build_object('erreur', 'Partenaire introuvable.'); end if;
    end if;
  exception
    when check_violation then
      return jsonb_build_object('erreur', 'Un champ ne respecte pas le format attendu (nom de 2 à 80 caractères, logo trop lourd…).');
    when not_null_violation then
      return jsonb_build_object('erreur', 'Le nom est obligatoire.');
    when invalid_text_representation then
      return jsonb_build_object('erreur', 'Ordre d''affichage invalide.');
  end;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ---------- Supprimer : administrateur (les membres peuvent masquer) ----------
create or replace function public.oc_partenaire_supprimer(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare msg text := oc_private.controle_admin(p_code);
begin
  if msg is not null then return jsonb_build_object('erreur', msg); end if;
  delete from public.partenaires where id = p_id;
  return jsonb_build_object('supprime', found);
end $$;

do $$ begin
  execute 'grant execute on function public.oc_partenaires_public() to anon, authenticated';
  execute 'grant execute on function public.oc_partenaires_equipe(text) to anon, authenticated';
  execute 'grant execute on function public.oc_partenaire_enregistrer(text, jsonb) to anon, authenticated';
  execute 'grant execute on function public.oc_partenaire_supprimer(text, bigint) to anon, authenticated';
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';
select 'Partenaires installés.' as resultat;
