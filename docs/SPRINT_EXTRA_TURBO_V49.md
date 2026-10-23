# HAITIKET V49 — Merchandising de la boutique officielle

## Changements
- Ajout de `products.is_featured`, désactivé par défaut.
- Le catalogue charge les produits mis en avant avant les autres, puis applique le tri choisi.
- Le panneau de la boutique officielle propose une étoile pour mettre un produit à la une ou le retirer.
- Les produits mis en avant reçoivent le badge « À la une » dans les cartes produit, en plus du badge officiel.
- Une RPC serveur exige une session authentifiée et une console administrateur déverrouillée, et limite l'action à un produit d'une boutique officielle active de type `platform`.
- Les actions de mise en avant sont consignées dans le journal d'audit.

## Migration
Appliquer `supabase/migrations/0043_official_shop_merchandising_v49.sql` en staging, puis tester avec un compte admin et un compte non-admin.

## Limites de validation
Les contrôles statiques et l'intégrité ZIP ne remplacent pas les tests Flutter, l'exécution SQL réelle, les tests RLS ni une validation sur les clients Web/Android. Ces derniers doivent être exécutés dans CI/staging avant production.
