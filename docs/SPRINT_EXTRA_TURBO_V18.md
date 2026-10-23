# HAITIKET V18 — Paiement du supplément de livraison

## Ce qui change
- Ajoute le type de paiement `delivery_fee` au registre `payment_attempts`.
- Le supplément calculé est `max(0, prix_offre - frais_de_livraison_déjà_payés)`, pour éviter une double facturation.
- Le client peut choisir une offre; l'application lance le paiement Bazik seulement si un supplément est dû.
- La fonction de collecte refuse la prise en charge tant que le supplément exigible n'a pas été confirmé par le webhook / la vérification Bazik.
- Le paiement confirmé ajoute des entrées au registre `payment_received` et `courier_payable`. Cela enregistre une dette due au coursier; ce n'est pas un versement automatique ni une garde réglementée des fonds.

## Installation
1. Sauvegarder la base et le projet.
2. Vérifier que les migrations 0001–0027 ont été appliquées et qu'aucune migration n'est en erreur.
3. Appliquer uniquement `supabase/migrations/0028_delivery_fee_payment.sql`.
4. Déployer les Edge Functions `bazik-pay` et `bazik-webhook` avec les secrets Bazik configurés.
5. Tester en environnement de test : offre égale aux frais déjà payés, supplément positif, paiement échoué, paiement confirmé, tentative de collecte avant confirmation, tentative de doublon.

## Limites importantes
- Le paiement du supplément est actuellement HTG uniquement, car le flux Bazik est facturé en gourdes.
- Aucune compilation Flutter ni exécution contre une base Supabase réelle n'a été effectuée dans cet environnement.
- Les entrées `courier_payable` sont un registre de dette; les décaissements réels et le séquestre nécessitent un workflow financier distinct, réconciliation et validation juridique/réglementaire.
