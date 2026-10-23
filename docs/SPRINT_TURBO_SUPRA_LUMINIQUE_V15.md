# HAITIKET — Sprint Turbo Supra Luminique V15

## Correctif SQL : erreur 42P13 sur `get_active_courier_location(uuid)`

PostgreSQL ne permet pas à `CREATE OR REPLACE FUNCTION` de modifier le type de retour d'une fonction existante, notamment les colonnes `OUT` d'un `RETURNS TABLE`. La migration `0025_repair_courier_location_return_type.sql` supprime puis recrée explicitement cette fonction avec le contrat étendu attendu par l'application : position du coursier, précision et horodatage GPS, coordonnées de destination et horodatage de destination. Les droits `EXECUTE` sont rétablis pour `authenticated` seulement.

**Procédure :** sauvegarder le schéma, vérifier que `0020` et les colonnes de `0019` existent, puis exécuter `0025` une seule fois dans Supabase SQL Editor. Ne pas exécuter de DROP manuel supplémentaire. Vérifier ensuite `select pg_get_function_result('public.get_active_courier_location(uuid)'::regprocedure);` et tester les accès avec un compte client autorisé et un compte non autorisé.

La migration `0021_tracking_destination_timestamp.sql` a aussi été corrigée pour les installations où elle n'a pas encore été appliquée. Les environnements ayant déjà enregistré `0021` doivent appliquer la migration de réparation `0025`.

## Paramètres d'administration ajoutés à l'interface

- Abonnement boutique mensuel : clé `shop_fee_usd` (valeur commerciale cible 20 USD).
- Abonnement boutique annuel : `shop_fee_yearly_usd` (valeur cible 200 USD).
- Frais Bazar : `bazar_fee_usd` (valeur cible 2 USD / 14 jours).
- Prestataire sélectionné : `payment_provider` (`plopplop` ou `bazik`).
- Objectif livraison immédiate : `delivery_immediate_sla_minutes` (45 minutes).
- Extensions de trafic : `delivery_traffic_extension_options` (120 et 240 minutes).
- Durée des offres de livreurs : `delivery_offer_expiry_minutes`.

Ces champs exposent les réglages dans l'administration; ils ne prouvent pas que les Edge Functions, webhooks, la facturation annuelle ou les parcours de paiement concernés sont déjà raccordés. Le changement de fournisseur doit être implémenté et validé côté serveur avant d'être annoncé comme actif.

## État de réalité — points qui restent à terminer et tester

- Les coordonnées GPS de destination sont structurées; la boucle continue de partage GPS en arrière-plan et la diffusion Realtime de tous les rôles ne sont pas certifiées de bout en bout.
- Le socle SQL des offres de livraison existe, mais les écrans de proposition côté livreur et de comparaison/sélection côté client restent à raccorder.
- Le paiement de commande, l'achat d'abonnements et les frais Bazar via portefeuille interne ne doivent pas être considérés comme opérationnels sans RPC comptables atomiques, rapprochement prestataire et tests réels.
- Le basculement du fournisseur de paiement nécessite une interface serveur commune et des webhooks distincts validés; la valeur de configuration ne suffit pas.
- Aucun test Flutter n'a été exécuté dans cet environnement si `flutter` n'est pas installé. Ne pas marquer le build comme validé avant CI.

## Critères avant production

1. Appliquer les migrations dans l'ordre sur une base de staging et contrôler le schéma.
2. Tester RLS et les RPC avec des comptes de rôles différents.
3. Tester les doubles webhooks, paiements retardés, remboursements et annulations.
4. Vérifier que les positions GPS expirées ne sont pas présentées comme actuelles.
5. Valider les flux de bout en bout avec le compte marchand Plop Plop et les webhooks de production.
