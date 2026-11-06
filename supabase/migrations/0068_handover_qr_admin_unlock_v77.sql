-- HAITIKET V77 — QR côté vendeur (retrait en boutique), déblocage de code et remise forcée par l'administration.

-- 1. Retrait en boutique : le vendeur scanne le QR du client (format HKT1:<commande>:<code>) ; le serveur vérifie, journalise.
create or replace function public.confirm_handover_qr(p_order uuid, p_payload text) returns boolean
language plpgsql security definer set search_path = public as $$
declare parts text[]; v_order uuid; ok boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  parts := string_to_array(trim(coalesce(p_payload,'')), ':');
  if coalesce(array_length(parts,1),0) <> 3 or parts[1] <> 'HKT1' then raise exception 'QR HAITIKET invalide'; end if;
  begin v_order := parts[2]::uuid; exception when others then raise exception 'QR HAITIKET invalide'; end;
  if v_order <> p_order then
    update public.order_pins set failed = failed + 1 where order_id = p_order;
    insert into public.qr_scan_log(order_id, actor, kind, success) values (p_order, auth.uid(), 'handover', false);
    return false;
  end if;
  ok := public.confirm_handover(p_order, parts[3]);
  insert into public.qr_scan_log(order_id, actor, kind, success) values (p_order, auth.uid(), 'handover', coalesce(ok,false));
  return coalesce(ok,false);
end $$;
revoke all on function public.confirm_handover_qr(uuid,text) from public, anon;
grant execute on function public.confirm_handover_qr(uuid,text) to authenticated;

-- 2. Admin : remettre à zéro les tentatives d'une commande dont le code est bloqué (5 erreurs).
create or replace function public.admin_reset_order_code(p_order uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if char_length(btrim(coalesce(p_reason,''))) < 5 then raise exception 'Motif détaillé requis (5 caractères minimum)'; end if;
  if not exists(select 1 from public.orders where id = p_order) then raise exception 'Commande introuvable'; end if;
  update public.order_pins set failed = 0 where order_id = p_order;
  update public.delivery_jobs set failed = 0 where order_id = p_order;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'reset_order_code', 'order', p_order, left(p_reason,200));
end $$;
revoke all on function public.admin_reset_order_code(uuid,text) from public, anon;
grant execute on function public.admin_reset_order_code(uuid,text) to authenticated;

-- 3. Admin : remise forcée (client injoignable, téléphone du client en panne…). Déclenche le règlement comme une remise normale.
--    Refusée en cas de litige ouvert ou de remboursement en cours.
create or replace function public.admin_force_handover(p_order uuid, p_reason text) returns text
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if char_length(btrim(coalesce(p_reason,''))) < 10 then raise exception 'Motif détaillé requis (10 caractères minimum)'; end if;
  select * into o from public.orders where id = p_order for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if exists(select 1 from public.order_disputes d where d.order_id = o.id and d.status = 'open') then raise exception 'Litige ouvert : traitez-le d''abord'; end if;
  if exists(select 1 from public.refund_requests r where r.order_id = o.id and r.status in ('to_execute','executed')) then raise exception 'Remboursement en cours ou exécuté'; end if;
  if o.delivery_mode = 'delivery' and o.status = 'IN_TRANSIT' then
    update public.delivery_jobs set status = 'delivered', failed = 0 where order_id = o.id;
    perform public._set_order_status(o.id, 'DELIVERED', auth.uid(), 'admin_forced_handover');
    insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'force_handover', 'order', o.id, left(p_reason,200));
    return 'DELIVERED';
  elsif o.delivery_mode = 'pickup' and o.status = 'READY_FOR_PICKUP' then
    perform public._set_order_status(o.id, 'COMPLETED', auth.uid(), 'admin_forced_handover');
    insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'force_handover', 'order', o.id, left(p_reason,200));
    return 'COMPLETED';
  end if;
  raise exception 'Statut incompatible (livraison : « en livraison » ; retrait : « prête »)';
end $$;
revoke all on function public.admin_force_handover(uuid,text) from public, anon;
grant execute on function public.admin_force_handover(uuid,text) to authenticated;
