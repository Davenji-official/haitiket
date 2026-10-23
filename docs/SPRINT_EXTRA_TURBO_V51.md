# HAITIKET V51 — Centre de suivi des promotions

## Livré dans le code
- Ajout d'un résumé des coupons de la boutique : coupons valides, coupons affichés sur les produits, coupons expirés et coupons ayant atteint leur quota d'utilisation.
- Calcul local du statut effectif en tenant compte de `active`, `expires_at` et `used_count` / `max_uses`.
- Chaque coupon affiche son statut effectif et indique s'il est visible publiquement, tout en conservant le commutateur d'activation existant.
- Les dates sont analysées de manière tolérante; une date absente ou illisible n'est pas déclarée expirée par le résumé.
- Aucun changement de schéma ni de logique de paiement n'est introduit. Le contrôle effectif des coupons lors du paiement doit toujours être garanti côté serveur.

## Limites et vérifications requises
- Le résumé est calculé sur les coupons renvoyés par `Repo.shopCoupons` pour la boutique actuellement ouverte.
- Le résumé UI ne remplace pas les règles serveur et ne prouve pas qu'un coupon sera accepté au paiement.
- Flutter analyze/test/build, contrôle de la compatibilité Dart, permissions/RLS et parcours de réduction réel doivent être exécutés en CI et sur Supabase de staging.
- Les validations locales sont statiques et ne constituent pas une validation de production.

## Vérification locale
Lancer `./scripts_validate_v51.sh`. Le script enchaîne les vérifications statiques précédentes et contrôle les nouveaux indicateurs de cycle de vie des coupons.
