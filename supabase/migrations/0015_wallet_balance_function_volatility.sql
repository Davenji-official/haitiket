-- my_wallet_v2 creates the caller's currency accounts if they do not yet exist,
-- so PostgreSQL must treat it as VOLATILE rather than STABLE.
alter function public.my_wallet_v2() volatile;
