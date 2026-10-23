# État de développement HAITIKET — V39

Date du dossier : 2026-10-23.

## Présent dans le dépôt
- Application Flutter et tests unitaires existants pour certains paramètres/localisations.
- Migrations SQL couvrant le modèle portefeuille HTG/USD, transactions, commandes, frais commerciaux, litiges, remboursements, suivi et confirmation de livraison.
- Fonctions/Edge Functions liées au flux Plop Plop présentes dans le code.
- Scripts d'audit structurel et validateurs statiques V25–V38.
- Pipeline GitHub Actions prévoyant l'installation Flutter, `flutter analyze` et `flutter test`.

## Non démontré par les seuls fichiers
- Que toutes les migrations ont été appliquées avec succès à la base Supabase distante.
- Que les Edge Functions actuelles sont déployées et configurées avec les bons secrets/webhooks.
- Que Plop Plop a confirmé une recharge/retrait dans un environnement de test réel.
- Que les parcours commande → paiement → préparation → collecte → remise → gains vendeur/coursier → litige/remboursement passent tous de bout en bout.
- Que l'application Flutter compile et passe les tests sur le commit actuel; l'exécution CI doit fournir la preuve.
- Que les paramètres tarifaires, KYC, notification, GPS et règles d'administration en production correspondent aux besoins métier.

## Conclusion honnête
Il serait inexact de dire que tout est développé et qu'il ne reste que des tests. Une part importante de la logique est présente dans le dépôt, mais l'audit d'implémentation, la validation des parcours complets et certaines intégrations opérationnelles restent à confirmer. Les résultats V39 sont des contrôles statiques locaux, pas une certification de production.
