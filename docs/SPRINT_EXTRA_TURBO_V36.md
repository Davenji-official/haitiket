# HAITIKET V36 — Parcours financiers et commandes : plan de recette staging

## Objectif

V36 n'ajoute aucune migration et ne modifie aucun solde. Elle documente un plan de recette reproductible des parcours qui doivent être vérifiés sur une instance Supabase de staging, et ajoute des contrôles statiques pour empêcher qu'on confonde code présent et flux réellement validé.

## État connu depuis le dépôt source

- Le schéma prévoit des comptes de portefeuille séparés par utilisateur et devise (`HTG`, `USD`) et des transactions internes avec référence unique.
- Le dépôt contient les fonctions/RPC de recharge, confirmation de recharge, préparation/fin de retrait, paiement de commande depuis le portefeuille, frais Bazar/abonnement boutique, remboursement interne, collecte et livraison avec PIN.
- Le code client contient `payOrderFromWallet`, `payBazarListingFromWallet`, `payShopPlanFromWallet`, `confirmPickup` et `confirmDelivery`.
- Les anciens appels de paiement externes côté client `startPayment`/`checkPayment` sont explicitement bloqués dans `lib/data/repo.dart` pour éviter d'initier un flux historique non migré.
- Les Edge Functions source Plop Plop existent : `plopplop-wallet`, `plopplop-webhook`, `plopplop-withdraw`.
- Les migrations de sécurité et d'audit existent dans le dépôt, mais leur présence ne prouve pas qu'elles ont été appliquées à la base distante.

## Préparation staging

1. Créer des utilisateurs de test distincts : client, vendeur, coursier et administrateur.
2. Utiliser une base et des identifiants Plop Plop de test, sans argent réel. Ne jamais coller d'URL de base ou de secret dans un ticket ou un chat.
3. Appliquer les migrations sur staging avec la procédure habituelle du projet, puis exécuter `scripts_run_staging_financial_gates_v35.sh`.
4. Vérifier dans le tableau de bord Supabase que les Edge Functions attendues sont déployées et que leurs secrets existent.
5. Pour chaque scénario, sauvegarder les références de transaction, les statuts avant/après et les journaux expurgés de toute donnée secrète.

## Matrice de scénarios

| ID | Scénario | Résultat attendu | Preuve à recueillir |
|---|---|---|---|
| W01 | Recharger un portefeuille HTG avec confirmation fournisseur valide | Une seule transaction réussie, montant et devise conformes | Référence interne + identifiant fournisseur |
| W02 | Envoyer deux fois le même webhook | Aucun second crédit | Solde et journal avant/après |
| W03 | Confirmer un montant fournisseur différent | Transaction mise en revue/refusée, aucun crédit indu | Statut et raison de revue |
| W04 | Recharger en USD | Crédit USD seulement, sans conversion HTG implicite | Deux soldes avant/après |
| W05 | Retrait supérieur au solde disponible | Refus sûr, aucune dette/solde négatif | Réponse RPC et transactions |
| W06 | Rejouer la finalisation d'un retrait | Aucun second débit/crédit | Référence et solde |
| O01 | Payer une commande avec le bon portefeuille/devise | Un débit atomique et commande payée | Référence `ORDER:<id>`, statut |
| O02 | Réessayer le paiement de la même commande | Réponse idempotente, aucun second débit | Nombre de transactions et solde |
| O03 | Payer avec solde insuffisant | Commande non payée, aucun débit | Statut commande et transactions |
| O04 | Tenter une devise incompatible | Refus, aucun change automatique | Devise commande/portefeuille |
| O05 | Expiration de réservation avant paiement | Paiement refusé et réservation expirée traitée | Statut et historique |
| C01 | Vendeur fait passer une commande payée à préparer/prête | Transition autorisée selon les règles serveur | Historique des statuts |
| C02 | Client tente une transition réservée au vendeur/coursier | Refus côté serveur | Réponse RPC et statut inchangé |
| D01 | Coursier collecte avec bon PIN, commande prête et paiement vérifié | Mission `picked_up`, commande `IN_TRANSIT` | Événement de statut |
| D02 | Mauvais PIN répété | Pas de collecte; limite de tentatives appliquée | Compteur d'échecs |
| D03 | Livraison avec bon PIN client | Mission `delivered`, commande `DELIVERED` | Événement de statut et horodatage |
| D04 | Litige ouvert avant collecte/livraison | Étape bloquée et gains retenus | Statut litige + ledger |
| E01 | Livraison confirmée sans litige | Gains éligibles libérés une fois selon règles serveur | Écritures vendeur/coursier |
| E02 | Tentative de libération pendant litige/remboursement actif | Aucun gain libéré | Audit financier |
| R01 | Remboursement d'un achat interne éligible | Crédit wallet idempotent et relié à la commande | Demande + transaction refund |
| R02 | Remboursement externe Plop Plop | Aucun crédit interne prétendant rembourser l'externe avant confirmation fournisseur | Référence externe et statut |
| F01 | Frais Bazar et abonnement boutique | Débit dans le portefeuille choisi et devise attendue | Transaction et expiration/plan |
| F02 | Frais de livraison | Paiement interne avant collecte, montant/devise alignés sur l'offre choisie | Offre, commande, transaction |

## Critères de réussite

- Aucun solde négatif non autorisé.
- Aucun double crédit/débit lors des reprises et webhooks dupliqués.
- HTG et USD restent séparés; toute conversion doit être explicite et au taux serveur configuré.
- Les statuts de commande/livraison ne sont pas modifiables en contournant les RPC autorisées.
- Les gains vendeur/coursier restent bloqués en cas de litige ou remboursement actif.
- Chaque mouvement est traçable par référence unique, acteur, devise, montant, statut et horodatage.
- Les remboursements externes ne sont pas marqués réussis sans preuve fournisseur.

## Hors de portée / limites

Ce document est une recette à exécuter. Il ne prétend pas que ces scénarios ont déjà été exécutés. Aucun scénario transactionnel ne doit être lancé sur production. Le dépôt seul ne confirme ni le déploiement réel des Edge Functions, ni les secrets Plop Plop, ni la réussite d'un build Flutter. Avant d'ouvrir les paiements en production, il faut joindre les résultats réels de staging et faire vérifier les politiques RLS/grants.
