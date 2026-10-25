-- Diagnostic en lecture seule pour le refus de publication de la boutique officielle.
-- À exécuter dans Supabase SQL Editor. Ce script ne modifie aucune donnée.

-- 1) État des boutiques : la boutique officielle doit être active et is_official=true.
select id, name, owner_id, status, kind, is_official
from public.shops
order by created_at desc
limit 30;

-- 2) Rôles administrateur enregistrés.
select u.email, r.role, r.user_id
from public.user_roles r
join auth.users u on u.id = r.user_id
where r.role = 'admin'
order by u.email;

-- 3) État du déverrouillage administrateur (30 minutes après le code).
select u.email,
       s.unlocked_until,
       (s.unlocked_until > now()) as unlock_actif,
       s.locked_until,
       (s.locked_until > now()) as temporairement_bloque,
       s.failed
from public.admin_unlock_state s
join auth.users u on u.id = s.user_id
order by s.unlocked_until desc nulls last;

-- 4) Politique RLS réellement installée sur products.
select policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'products'
order by policyname;

-- 5) Migration V47 : présence de la fonction appelée par l'interface.
select to_regprocedure('public.admin_order_history_v47(integer,text)') as fonction_historique_v47,
       to_regclass('public.orders') as table_orders;

-- 6) Les trois objets du diagnostic initial sont optionnels tant qu'aucun flux du projet ne les appelle.
select to_regclass('public.manual_payments') as manual_payments,
       to_regclass('public.payout_requests') as payout_requests,
       to_regprocedure('public.courier_confirm_pickup(uuid,text)') as courier_confirm_pickup;
