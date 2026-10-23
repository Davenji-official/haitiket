# HAITIKET V64 — Contrat d'acceptation avant lancement

## Objectif
V64 ne prétend pas remplacer les tests d'intégration. Il ajoute un contrôle de cohérence qui vérifie que les mécanismes critiques introduits dans V58–V63 restent présents dans le dépôt et que le pipeline CI conserve les étapes Flutter.

## Contrôles statiques
- Traçabilité du stock et références de mouvements aux commandes et remises fournisseurs.
- Ajustement de stock avec verrouillage transactionnel et protection des réservations de gros.
- Cycle de suppression/réactivation et garde-fous KYC/remboursement.
- Rapport administratif de préparation au lancement, en lecture seule.
- Présence des étapes `flutter analyze` et `flutter test` dans la CI.

## Scénarios obligatoires en staging
1. Deux achats simultanés du dernier article : une seule réservation doit réussir.
2. Paiement refusé puis webhook répété : aucune double écriture ni débit supplémentaire.
3. Annulation d'une commande payée : le remboursement reste en attente jusqu'à confirmation réelle du prestataire.
4. Suppression de boutique avec commande en cours : nouvelles ventes bloquées, historique conservé, clôture finale refusée tant que les remboursements ne sont pas résolus et le délai de 30 jours écoulé.
5. KYC incomplet ou non approuvé : aucun badge vérifié ni activation de rôle soumis à vérification.
6. Compte banni avec session ouverte : les mutations sensibles doivent être refusées côté serveur.
7. Remise fournisseur et retour : chaque mouvement de stock possède une référence métier vérifiable et les quantités restent cohérentes.

## Exécution
```bash
./scripts_validate_v64.sh
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Les scénarios d'intégration exigent un projet Supabase de staging et des identifiants de prestataire de test. Ne jamais lancer ces tests sur les données de production. Les remboursements externes ne sont considérés comme terminés qu'après confirmation du prestataire.
