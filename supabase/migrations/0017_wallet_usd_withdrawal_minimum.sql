-- Permet les retraits depuis les portefeuilles HTG et USD.
-- Le montant réservé reste dans la devise du portefeuille ; l'Edge Function
-- convertit un retrait USD en HTG avant l'appel au fournisseur.
create or replace function public.prepare_wallet_withdrawal(
  p_amount_minor bigint, p_currency text, p_phone text, p_reference text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); aid uuid; bal bigint; tid uuid;
begin
 if uid is null then raise exception 'Connexion requise'; end if;
 if p_currency not in ('HTG','USD') then raise exception 'Devise de retrait invalide'; end if;
 if p_phone !~ '^509[0-9]{8}$' then raise exception 'Numéro haïtien invalide'; end if;
 if (p_currency='USD' and (p_amount_minor < 100 or p_amount_minor > 50000000))
    or (p_currency='HTG' and (p_amount_minor < 5000 or p_amount_minor > 50000000)) then
   raise exception 'Montant de retrait hors limites';
 end if;
 select id into aid from public.wallet_accounts where user_id=uid and currency=p_currency for update;
 if aid is null then raise exception 'Portefeuille introuvable'; end if;
 select coalesce(sum(case when status='successful' then case when kind in ('withdrawal','purchase','subscription_fee') then -amount_minor-fee_minor else amount_minor-fee_minor end else 0 end),0)
 into bal from public.wallet_transactions where account_id=aid;
 if bal < p_amount_minor then raise exception 'Solde insuffisant'; end if;
 if exists(select 1 from public.wallet_transactions where user_id=uid and kind='withdrawal' and status in ('pending','processing')) then raise exception 'Un retrait est déjà en cours'; end if;
 insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,recipient_phone,metadata)
 values(aid,uid,p_reference,'withdrawal','processing',p_amount_minor,p_currency,'plopplop',p_phone,jsonb_build_object('wallet_currency',p_currency)) returning id into tid;
 return jsonb_build_object('id',tid,'reference',p_reference,'amount_minor',p_amount_minor,'currency',p_currency,'phone',p_phone);
end $$;
grant execute on function public.prepare_wallet_withdrawal(bigint,text,text,text) to authenticated;
