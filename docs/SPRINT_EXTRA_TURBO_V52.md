# HAITIKET V52 — Garde-fous de pré-lancement

## Objectif
Ajouter un contrôle de régression statique, reproductible en local et dans le workflow GitHub Actions, centré sur les flux les plus sensibles avant toute recette de lancement.

## Contrôles automatisés
- Le point d'entrée de paiement externe historique reste fermé tant que le flux n'a pas été migré.
- Le paiement de commande interne passe par la RPC serveur.
- Le paiement de portefeuille est réservé aux commandes en attente de paiement.
- Le déblocage des gains doit rester bloqué en présence de litige ou de remboursement actif/exécuté.
- La confirmation de livraison reste associée au statut attendu et au PIN.
- Les coupons sont contrôlés côté serveur à la création de commande (activation, fenêtre temporelle, quota) et une rédemption par utilisateur est contrainte par la base.
- Les champs de devise et les API de frais HTG/USD distinctes restent présents.
- La boutique officielle reste explicitement identifiée et contrôlée côté serveur.

## Limites
Ce script lit le code source et les migrations SQL ; il ne prouve ni que les migrations s'exécutent, ni que les politiques RLS effectives sont sûres, ni que les prestataires de paiement répondent correctement. Une recherche de texte peut également passer à côté d'une erreur logique ou d'un problème de concurrence.

## Recette staging obligatoire avant production
1. Appliquer les migrations sur une base Supabase de staging restaurable et vérifier qu'elles terminent sans erreur.
2. Tester deux paiements simultanés pour une même commande : un seul débit doit réussir.
3. Tester un coupon au quota limite avec des commandes concurrentes : le quota ne doit pas être dépassé.
4. Vérifier qu'un litige ouvert ou un remboursement bloque les gains, puis tester le déblocage après résolution autorisée.
5. Vérifier le PIN de livraison, le statut de commande et le double envoi de confirmation.
6. Vérifier que les opérations HTG n'altèrent jamais le solde USD, et inversement ; tester explicitement les conversions autorisées.
7. Tester les accès anonymes, client, vendeur, livreur et administrateur aux RPC et aux tables sensibles.
8. Exécuter `flutter analyze`, `flutter test`, puis compiler les cibles réellement publiées.
9. Conserver les journaux CI, résultats SQL et captures de recette comme preuves de validation.

## Lancement local
Exécuter `./scripts_validate_v52.sh`. Un succès signifie uniquement que les assertions statiques ont réussi ; il ne constitue pas une autorisation de déploiement en production.
