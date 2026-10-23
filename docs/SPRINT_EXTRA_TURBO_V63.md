# HAITIKET V63 — Centre de contrôle administratif

## Livré
- Nouvel onglet « Contrôle lancement » dans l'administration.
- Présentation des indicateurs du snapshot serveur V62 : remboursements non résolus et anciens, KYC à examiner, suppressions de boutiques, suppressions bloquées par remboursement, litiges et paiements à rapprocher.
- Actualisation manuelle et copie du snapshot JSON pour audit/triage.
- Vue en lecture seule : aucune mutation de commande, portefeuille, remboursement ou boutique depuis cet écran.
- Le rapport distingue l'absence de bloqueurs recensés par cette fonction de la validation complète de production.

## Dépendance
Le déploiement de la migration V62 (`0052_release_readiness_audit_v62.sql`) doit être fait avant l'utilisation de cet onglet. L'accès dépend du contrôle serveur `admin_unlocked()`.

## Tests staging requis
1. Administrateur déverrouillé : le rapport s'affiche et ses valeurs correspondent aux données de test.
2. Compte non administrateur/verrouillé : la fonction est refusée et l'écran présente une erreur sans fuite de données.
3. Ajouter un remboursement non exécuté, un dossier KYC en attente, une suppression de boutique et un litige; actualiser et vérifier les compteurs.
4. Copier le JSON et vérifier qu'aucune donnée d'identité sensible n'y figure.
5. Vérifier que l'écran n'écrit dans aucune table métier.

## Limites
Les contrôles statiques ne prouvent pas la compilation Flutter, la sécurité effective des politiques Supabase ni la validité des états remontés par les prestataires. Aucun remboursement externe n'est considéré exécuté sur la seule base de cet audit.
