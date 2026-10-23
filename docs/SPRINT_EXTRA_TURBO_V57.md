# HAITIKET V57 — Rapports fournisseurs et export CSV

## Portée
- Ajoute des filtres de période (7, 30 ou 90 jours) et de type d'événement au journal fournisseurs.
- Affiche le nombre d'événements retenus et des totaux indicatifs des montants d'événements, en gardant HTG et USD séparés.
- Ajoute un export CSV du jeu d'événements filtré, copié dans le presse-papiers avec BOM UTF-8.
- Échappe les guillemets et neutralise les préfixes de formule de tableur (`=`, `+`, `-`, `@`).

## Limites importantes
- Le dépôt ne charge que les 200 événements les plus récents accessibles; le filtre de période est appliqué à ce jeu chargé et ne garantit donc pas une couverture exhaustive sur 90 jours.
- Le total additionne les montants enregistrés dans les événements filtrés. Un même achat peut apparaître dans plusieurs événements : ces totaux ne sont ni un chiffre d'affaires, ni un total d'achats uniques, ni une preuve de paiement.
- L'export contient les identifiants de demande, de boutiques et d'acteurs visibles à l'utilisateur. Ne le partagez qu'avec les personnes autorisées.
- Aucun paiement ni écriture métier n'est déclenché par cette fonctionnalité.

## Validation
Lancer `./scripts_validate_v57.sh`. Ce contrôle statique enchaîne les validations V25–V56 puis vérifie les filtres, la séparation des devises, l'export et son échappement. La compilation Flutter, `flutter test` et la recette Supabase de staging restent nécessaires.
