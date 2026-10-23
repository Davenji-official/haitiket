# HAITIKET V54 — Espace fournisseur et achats en gros

## Objectif
Permettre à une boutique professionnelle active de publier un prix de gros et à une autre boutique professionnelle d'envoyer une demande de réapprovisionnement. Cette première version organise la demande et la réservation de stock; elle ne déclenche aucun paiement ni livraison.

## Fonctionnalités
- Offre de gros par produit : activation, prix unitaire dans la devise du produit et quantité minimale (2 à 10 000).
- Catalogue consultable des produits publiés, en stock, dont l'offre de gros est activée.
- Demande d'achat associée à une boutique acheteuse active, avec quantité et note facultative.
- Instantané du produit, des boutiques, du prix et de la devise au moment de la demande.
- Actions serveur : accepter/refuser une demande en attente, annuler une demande en attente depuis la boutique acheteuse, confirmer la remise après acceptation.
- À l'acceptation, le serveur vérifie le stock disponible en tenant compte des autres demandes acceptées. À la confirmation de remise, le stock est décrémenté côté serveur.
- Contrôles d'accès fondés sur le propriétaire des boutiques; la table de demandes n'autorise pas les écritures directes du client.
- Les montants HTG/USD restent dans la devise d'origine du produit. Aucune conversion ni opération de portefeuille n'est exécutée.

## Migration
Appliquer `supabase/migrations/0045_wholesale_supplier_workflow_v54.sql` après les migrations précédentes, d'abord sur une base de staging. Vérifier que les rôles SQL, RLS et schéma `products`/`shops` correspondent au dépôt déployé.

## Limites connues
- V54 est un flux de demande fournisseur, pas une commande payée. Le paiement, la facture commerciale, la livraison, les retours et les litiges fournisseur ne sont pas inclus.
- Les offres affichent le prix de gros et la devise du produit; les nouveaux produits créés par le formulaire actuel sont généralement en HTG. Les produits USD doivent être validés en staging.
- Le stock n'est réservé qu'à l'acceptation; la quantité acceptée est considérée réservée jusqu'à l'annulation future (pas encore proposée) ou la confirmation de remise. Une gestion des expirations et de la libération des réservations sera une étape suivante.
- Les liens universels mobiles, la compilation Flutter et les tests d'intégration Supabase n'ont pas été exécutés dans cet environnement.

## Recette staging requise
1. Un vendeur actif peut activer une offre sur un produit publié ayant suffisamment de stock.
2. Un visiteur non authentifié ne peut ni créer une demande ni changer son statut.
3. Une boutique ne peut pas demander son propre produit.
4. Quantité minimale, stock disponible, prix positif et devise HTG/USD sont contrôlés côté serveur.
5. Le propriétaire vendeur peut accepter/refuser; le propriétaire acheteur peut annuler seulement une demande en attente.
6. Deux demandes concurrentes ne peuvent pas réserver plus que le stock disponible.
7. La confirmation de remise décompte le stock une seule fois; toute répétition doit échouer par transition de statut invalide.
8. Vérifier l'absence de débit de portefeuille, de conversion et de création de commande retail automatique.
