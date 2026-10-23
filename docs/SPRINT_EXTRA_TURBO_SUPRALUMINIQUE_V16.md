# HAITIKET — Sprint Extra Turbo Supraluminique V16

## Livré dans ce sprint

- L'écran coursier propose maintenant un tarif de livraison et un délai estimé au lieu de présenter l'ancienne acceptation directe comme parcours principal.
- Le prix est saisi dans la devise de la mission, converti en unités mineures côté application, puis validé côté serveur par `propose_delivery_price`.
- Le client peut consulter les offres actives depuis l'écran de suivi, comparer le montant et le délai, puis choisir une offre.
- Les offres expirées sont marquées comme telles côté serveur et les offres sont triées par prix, délai, puis date.
- Nouvelle migration additive `0026_delivery_offers_by_order.sql`, qui ne renvoie les offres qu'au propriétaire de la commande et uniquement pour une commande en livraison.

## Déploiement SQL

Après avoir vérifié que les migrations précédentes jusqu'à `0025_repair_courier_location_return_type.sql` sont correctement appliquées, exécuter uniquement :

`supabase/migrations/0026_delivery_offers_by_order.sql`

Ne pas relancer toute la série de migrations sur une base existante. La migration `0025` reste la réparation ciblée du problème de type de retour PostgreSQL rencontré avec `get_active_courier_location(uuid)`.

## Limites importantes — pas encore production-ready

- Le choix d'une offre attribue la mission mais **ne déclenche pas encore le paiement automatique de la livraison**. L'interface le signale explicitement avant la confirmation.
- Le parcours de paiement des commandes, abonnements et frais Bazar doit encore être raccordé de bout en bout à un prestataire réel, avec webhooks vérifiés et opérations idempotentes.
- Le rafraîchissement des offres et du suivi est par polling au premier plan, pas par une garantie de temps réel ni de suivi GPS permanent en arrière-plan.
- Il faut tester les migrations sur une copie de la base, puis lancer `flutter analyze`, les tests et un build Android/Web dans un environnement Flutter/Supabase configuré. Ces outils et une base connectée n'étaient pas disponibles dans l'environnement de génération de cette archive.
