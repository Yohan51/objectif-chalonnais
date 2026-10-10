-- =====================================================================
-- ALERTES : UN SEUL CODE — L'Objectif Châlonnais
-- Permet à la fonction d'envoi des alertes de vérifier le code modérateur.
-- À coller dans Supabase : SQL Editor → New query → Run.
-- Nécessite securite.sql (et actus.sql / jeux.sql pour les alertes
-- automatiques). Peut être relancé sans risque.
-- =====================================================================
create or replace function public.oc_verifier_code_serveur(p_code text, p_ip text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_ip text := md5(coalesce(nullif(btrim(p_ip), ''), 'inconnu')); ok boolean;
begin
  if (select count(*) from oc_private.ecritures
      where ip = v_ip and type = 'echec' and quand > now() - interval '15 minutes') >= 8 then
    return false;
  end if;
  ok := oc_private.code_valide(p_code);
  if not ok then insert into oc_private.ecritures (ip, type) values (v_ip, 'echec'); end if;
  return ok;
end $$;

-- Réservée à la fonction d'envoi (clé de service) : le public ne peut pas l'appeler
revoke execute on function public.oc_verifier_code_serveur(text, text) from public;
do $$ begin
  execute 'revoke execute on function public.oc_verifier_code_serveur(text, text) from anon, authenticated';
  execute 'grant execute on function public.oc_verifier_code_serveur(text, text) to service_role';
exception when undefined_object then null; end $$;

-- =====================================================================
-- ALERTES AUTOMATIQUES À LA PUBLICATION
-- La fonction d'envoi appelle oc_alertes_a_envoyer() juste après chaque
-- publication (et le robot GitHub toutes les 15 minutes, pour les articles
-- programmés). Chaque alerte n'est remise qu'UNE fois : l'article ou le jeu
-- est marqué « alerte envoyée » au moment où il est pris en charge.
-- =====================================================================
create or replace function oc_private.date_fr(d timestamptz) returns text
language sql immutable set search_path = '' as $$
  select (array['dimanche','lundi','mardi','mercredi','jeudi','vendredi','samedi'])[extract(dow from l)::int + 1]
         || ' ' || case when extract(day from l) = 1 then '1er' else extract(day from l)::int::text end
         || ' ' || (array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'])[extract(month from l)::int]
         || ' à ' || to_char(l, 'HH24"h"MI')
  from (select d at time zone 'Europe/Paris' as l) x
$$;

create or replace function oc_private.resume(p_texte text, p_max int) returns text
language sql immutable set search_path = '' as $$
  select case when char_length(t) <= p_max then t
              else rtrim(left(t, p_max - 1), ' ,;:.-') || '…' end
  from (select btrim(regexp_replace(regexp_replace(coalesce(p_texte, ''),
          '(\*\*|__|^#+\s*|^[-•]\s+)', '', 'gn'), '\s+', ' ', 'g')) as t) x
$$;

create or replace function public.oc_alertes_a_envoyer() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare res jsonb := '[]'::jsonb; r record;
begin
  -- Articles : publiés (maintenant ou à l'heure programmée) depuis moins de 24 h
  if to_regclass('public.actus') is not null then
    for r in
      update public.actus a set alerte_le = now()
      where a.publie and a.alerte_auto and a.alerte_le is null
        and a.publie_le is not null and a.publie_le <= now() and a.publie_le > now() - interval '1 day'
      returning a.slug, a.titre, a.chapo, a.contenu
    loop
      res := res || jsonb_build_object(
        'type', 'actu', 'titre', left(r.titre, 80),
        'message', oc_private.resume(coalesce(nullif(btrim(r.chapo), ''), r.contenu), 180),
        'lien', './actus.html#' || r.slug);
    end loop;
  end if;

  if to_regclass('public.jeux') is not null then
    -- Nouveau jeu publié et encore ouvert
    for r in
      update public.jeux j set alerte_jeu_le = now()
      where j.publie and j.alerte_auto and j.alerte_jeu_le is null and j.date_fin > now()
      returning j.slug, j.titre, j.lot, j.date_fin
    loop
      res := res || jsonb_build_object(
        'type', 'jeu', 'titre', 'Nouveau jeu concours 🎁',
        'message', oc_private.resume(r.titre || ' — ' || case when btrim(r.lot) <> '' then 'À gagner : ' || btrim(r.lot) || '. ' else '' end
                                      || 'Participez avant le ' || oc_private.date_fr(r.date_fin) || ' !', 200),
        'lien', './jeux.html#jeu-' || r.slug);
    end loop;
    -- Gagnants publiés depuis moins de 2 jours
    for r in
      update public.jeux j set alerte_gagnants_le = now()
      where j.publie and j.alerte_auto and j.alerte_gagnants_le is null
        and jsonb_array_length(j.gagnants) > 0 and j.tire_le > now() - interval '2 days'
      returning j.slug, j.titre, j.lot, j.gagnants
    loop
      res := res || jsonb_build_object(
        'type', 'gagnants', 'titre', 'Résultat du jeu concours 🏆',
        'message', oc_private.resume(r.titre || ' : félicitations à '
                                      || (select string_agg(g, ', ') from jsonb_array_elements_text(r.gagnants) g)
                                      || ' ! Merci à tous pour votre participation.', 200),
        'lien', './jeux.html#jeu-' || r.slug);
    end loop;
  end if;
  return res;
end $$;

revoke execute on function public.oc_alertes_a_envoyer() from public;
do $$ begin
  execute 'revoke execute on function public.oc_alertes_a_envoyer() from anon, authenticated';
  execute 'grant execute on function public.oc_alertes_a_envoyer() to service_role';
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';
select 'Alertes : code de l''équipe accepté et alertes automatiques installées.' as resultat;
