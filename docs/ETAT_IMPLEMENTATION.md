# État de l'implémentation HAITIKET — paquet de travail

## Fait dans cette itération
- Ajout du choix explicite « Livrer à ma position actuelle » au checkout.
- Gestion des autorisations de localisation, GPS désactivé, refus de permission, délai de capture et affichage de la précision rapportée par l'appareil.
- Le lieu choisi est transmis dans le champ texte d'adresse actuellement accepté par le backend.
- Ajout de la spécification détaillée des exigences livraison/temps réel/prix/KYC/admin/paiements.

## Pas encore fait / non certifié
- Les coordonnées ne sont pas encore stockées dans des colonnes géographiques dédiées.
- Le suivi GPS continu Realtime n'est pas implémenté dans tous les rôles.
- Les délais 45 minutes, livraison normale et extensions trafic ne sont pas encore liés à un moteur SLA réel.
- Le choix d'offre de livraison et les prix proposés par les livreurs ne sont pas encore intégrés de bout en bout.
- Le paiement de commandes/abonnements/Bazar par portefeuille n'est pas certifié de bout en bout.
- Le choix administrateur du prestataire de recharge/retrait doit être audité et intégré à la configuration réelle.
- Le guide PDF n'est pas encore servi par un bouton du panel admin.
- Compilation/tests Flutter non exécutés dans cet environnement (outil Flutter non disponible).

## Migration
Aucune nouvelle migration n'a été ajoutée dans cette itération. Ne pas exécuter les fichiers SQL_bloc_A/B/C ou d'autres migrations une seconde fois sans vérifier l'historique réel de Supabase.
