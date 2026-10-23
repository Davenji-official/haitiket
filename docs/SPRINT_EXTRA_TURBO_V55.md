# HAITIKET V55 — Expiration des réservations fournisseurs

## Objectif

Fiabiliser le cycle de demandes de gros introduit en V54 en évitant qu'une demande acceptée mais abandonnée immobilise indéfiniment le stock. Cette évolution ne déclenche aucun paiement fournisseur.

## Changements

- Ajout de `expires_at` sur `wholesale_requests`.
- Une acceptation crée une réservation de sept jours.
- Les demandes acceptées héritées reçoivent une échéance de sept jours calculée depuis leur dernière mise à jour.
- Le fournisseur ne peut confirmer la remise après l'expiration; la demande passe alors à `expired` et la réservation est libérée.
- L'acheteur peut annuler une demande `pending` ou `accepted`; l'annulation d'une demande acceptée libère le stock réservé.
- RPC idempotente `expire_wholesale_reservations_v55()` pour un job planifié ou une exécution opérateur avec `service_role`.
- L'espace fournisseur affiche l'échéance de réservation et offre l'annulation à l'acheteur lorsque la demande est acceptée.

## Déploiement et exploitation

1. Appliquer `supabase/migrations/0046_wholesale_reservation_expiry_v55.sql` en staging après sauvegarde et contrôle du schéma.
2. Configurer un job planifié de confiance pour appeler `public.expire_wholesale_reservations_v55()` régulièrement, par exemple toutes les heures. Ne jamais exposer le rôle `service_role` au client.
3. Tester les cas acceptation, annulation acheteur, remise avant échéance, remise après échéance, deux demandes concurrentes et exécution répétée du job.
4. Confirmer que la réservation n'est pas considérée comme un paiement ou une créance réglée : ce flux ne fait aucun mouvement de portefeuille.

## Limites de validation

Le validateur V55 est statique. La compilation Flutter, l'application réelle de la migration et les tests de concurrence sur Supabase de staging restent obligatoires avant production. Vérifier en staging la compatibilité du nom de contrainte `wholesale_requests_status_check` avec le schéma réellement déployé.
