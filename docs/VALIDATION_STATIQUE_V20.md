# Validation statique — HAITIKET V20

Vérifications locales réalisées sur les sources de cette archive :

- migration `0030_wallet_first_bazar_shop_delivery.sql` présente;
- RPC `pay_bazar_listing_from_wallet`, `pay_shop_plan_from_wallet`, `quote_wallet_fee_usd` et remplacement de `select_delivery_price_offer` présents;
- les écrans Bazar et abonnement appellent les RPC de portefeuille interne;
- l'écran de sélection d'offre de livraison n'appelle plus le paiement externe historique;
- aucun appel `Repo.startPayment` ou `bazik-pay` dans `lib/`;
- sources des Edge Functions Bazik retirées de cette archive; les fonctions déjà déployées doivent être désactivées séparément dans Supabase;
- aucune conversion implicite HTG/USD n'a été ajoutée aux frais internes.

Non effectués : compilation Flutter, analyse Dart, exécution PostgreSQL/Supabase, test de bout en bout, vérification réelle de Plop Plop.
