-- =====================================================================
-- ALERTES : UN SEUL CODE — L'Objectif Châlonnais
-- Permet à la fonction d'envoi des alertes de vérifier le code modérateur.
-- À coller dans Supabase : SQL Editor → New query → Run.
-- Nécessite securite.sql. Peut être relancé sans risque.
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

notify pgrst, 'reload schema';
select 'Alertes : le code modérateur est maintenant accepté.' as resultat;
