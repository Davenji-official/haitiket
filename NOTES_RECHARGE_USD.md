# Recharge du portefeuille USD via paiement en HTG

## Comportement ajouté
- Le client choisit le portefeuille à créditer : HTG ou USD.
- Pour une recharge USD, le serveur lit `usd_htg_rate` dans `platform_settings`.
- Le fournisseur Plop Plop reçoit un montant en HTG calculé côté serveur.
- La transaction interne garde le montant cible en USD et l'équivalent attendu en HTG dans ses métadonnées.
- Le portefeuille n'est crédité qu'après vérification serveur du montant réellement confirmé par Plop Plop.
- Le taux utilisé est conservé avec la transaction; changer le taux admin n'altère pas les demandes déjà créées.

## Déploiement requis
1. Faire une sauvegarde et vérifier d'abord sur un environnement Supabase de test.
2. Exécuter `supabase/migrations/0016_wallet_usd_topup_fx.sql` après les migrations précédentes.
3. Vérifier dans `platform_settings` qu'une valeur positive `usd_htg_rate` existe. Le panel admin peut la modifier.
4. Redéployer la fonction Edge `plopplop-wallet`.
5. Reconstruire/déployer l'application Flutter.
6. Tester avec un compte et un fournisseur de paiement de test, si le fournisseur le permet, les cas succès, échec, montant différent, taux absent et webhook doublé.

## Limites importantes
- Cette modification ne permet pas encore de convertir un solde USD déjà présent en solde HTG. Elle concerne la conversion du montant à payer en gourdes pour créditer le portefeuille USD.
- Les retraits restent en HTG.
- Le projet n'a pas été connecté à Supabase ni déployé par cette modification. Aucun paiement réel n'a été exécuté. Vérifier la compatibilité exacte avec les réponses Plop Plop avant la production.


## Minimums recharge/retrait
- Recharge portefeuille USD : minimum 1 USD. Recharge HTG : minimum 20 HTG.
- Retrait portefeuille USD : minimum 1 USD, converti en HTG au taux d'administration avant l'appel Plop Plop. Retrait HTG : minimum 50 HTG.
- Appliquer la migration `0017_wallet_usd_withdrawal_minimum.sql`, redéployer `plopplop-wallet` et `plopplop-withdraw`, puis reconstruire l'application. Ce code n'a pas été testé avec une transaction réelle.
