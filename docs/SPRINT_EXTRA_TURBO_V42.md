# HAITIKET V42 — Intégrité des ressources avant publication

## Objectif

Empêcher les workflows de publier une application avec un logo transparent de 1×1 pixel ou des icônes/mascottes manquantes ou corrompues.

## Changements réalisés

- Ajout de `scripts_validate_release_assets.sh` : vérifie les deux logos PNG (signature et dimensions minimales) et les 14 mascottes WebP attendues (signature RIFF/WEBP et taille minimale).
- Le workflow Web et le workflow Android exécutent ce contrôle après la préparation des ressources et avant la résolution des dépendances.
- Suppression du remplacement silencieux d'un logo absent par une image transparente de 1×1 pixel. En cas de ressource manquante ou invalide, le build s'arrête.
- La génération des icônes (`dart run flutter_launcher_icons`) est désormais bloquante : une erreur n'est plus masquée par `|| echo`.
- Ajout de `scripts_validate_v42.sh` dans la gate qualité GitHub Actions.

## Validation effectuée dans cet environnement

- `./scripts_validate_v42.sh` : réussi; les validateurs statiques V25–V42 passent.
- Ressources source contrôlées : 2 logos PNG et 14 mascottes WebP reconnus.

## Ce qui n'est pas encore prouvé

- Les builds Flutter Web et Android n'ont pas été exécutés localement dans cet environnement.
- Le succès du workflow GitHub Actions distant n'a pas été observé.
- Cette vérification contrôle les signatures de fichiers et des dimensions minimales; elle ne garantit pas à elle seule la qualité visuelle des images sur chaque écran.
- Les tests Supabase de staging, les parcours de paiement Plop Plop, les webhooks et les parcours réels de commande/livraison restent à exécuter séparément.

## Contrôle à faire après mise à jour du dépôt

1. Pousser cette version sur une branche de test.
2. Vérifier que `HAITIKET quality gates` passe.
3. Vérifier que les jobs Web et Android passent jusqu'au build.
4. Ouvrir les artefacts publiés et contrôler les logos/icônes sur appareils réels.
5. N'autoriser la production qu'après la recette staging financière et fonctionnelle documentée dans les gates précédentes.
