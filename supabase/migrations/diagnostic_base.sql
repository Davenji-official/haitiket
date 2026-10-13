-- À coller dans Supabase > SQL Editor > Run. Montre quelles migrations ont déjà été appliquées.
select 'user_roles (0003)' as element, to_regclass('public.user_roles') is not null as present
union all select 'admin_secret (0004)', to_regclass('public.admin_secret') is not null
union all select 'conversations (0005)', to_regclass('public.conversations') is not null
union all select 'support_tickets (0006)', to_regclass('public.support_tickets') is not null
union all select 'coupons (0007)', to_regclass('public.coupons') is not null
union all select 'order_pins (0007)', to_regclass('public.order_pins') is not null
union all select 'payment_attempts (0008)', to_regclass('public.payment_attempts') is not null
union all select 'product_media (0009)', to_regclass('public.product_media') is not null
union all select 'ma chaîne : fonction confirm_pickup', to_regprocedure('public.confirm_pickup(uuid,text)') is not null
union all select 'AUTRE chaîne : table manual_payments', to_regclass('public.manual_payments') is not null
union all select 'AUTRE chaîne : table payout_requests', to_regclass('public.payout_requests') is not null
union all select 'AUTRE chaîne : fonction courier_confirm_pickup', to_regprocedure('public.courier_confirm_pickup(uuid,text)') is not null;
