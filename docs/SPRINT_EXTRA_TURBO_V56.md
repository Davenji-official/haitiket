# HAITIKET V56 — Historique commercial des achats fournisseurs

## Objectif

V56 ajoute un journal d'événements en base de données pour le cycle des demandes d'achat en gros. Les événements sont capturés par un trigger SQL afin que la trace ne dépende pas uniquement de l'interface Flutter.

## Événements enregistrés

- Création d'une demande (y compris les demandes existantes au moment du déploiement, avec une entrée de référence qui ne prétend pas reconstituer leur historique passé).
- Acceptation, refus et annulation.
- Expiration de réservation.
- Confirmation de remise des marchandises.
- Modification de l'échéance de réservation et changements significatifs des données commerciales.

Chaque entrée conserve l'identifiant de la demande, les boutiques concernées, l'état avant/après lorsque connu, la quantité, le prix unitaire, le total, la devise, l'échéance, l'identifiant de l'acteur lorsque fourni par Supabase et l'horodatage.

## Sécurité

- RLS activée sur le journal.
- Lecture accordée aux utilisateurs authentifiés qui possèdent la boutique acheteuse ou vendeuse concernée.
- Pas d'écriture directe accordée aux utilisateurs authentifiés; les entrées sont ajoutées par le trigger serveur.
- Suppression des événements empêchée par la référence `ON DELETE RESTRICT` depuis le journal vers la demande.
- Aucun paiement, débit de portefeuille ou conversion de devise n'est déclenché par V56.

## Interface

L'écran « Fournisseurs et achats en gros » affiche un historique récent, les changements de statut, la quantité, le total avec la devise d'origine et l'identifiant de demande. La requête est limitée aux 200 événements les plus récents visibles pour l'utilisateur.

## Déploiement et limites

1. Appliquer `supabase/migrations/0047_wholesale_request_history_v56.sql` uniquement sur une base de staging après revue de `0045` et `0046` et vérification des permissions existantes.
2. Tester que l'acheteur et le vendeur voient les événements de leur demande, mais qu'un tiers ne voit rien.
3. Tester création, acceptation, refus, annulation, expiration, remise et nettoyage programmé.
4. Tester que les clients authentifiés ne peuvent ni insérer, ni modifier, ni supprimer des événements.
5. Exécuter `flutter analyze` et `flutter test`.

Les contrôles statiques ne prouvent pas le comportement d'une base réelle. Le backfill produit uniquement une entrée de référence par demande existante; les transitions antérieures à V56 ne peuvent pas être reconstituées à partir des seules données courantes.
