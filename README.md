# HAITIKET — projet Flutter + Supabase

HAITIKET est une application de marketplace, Bazar, boutiques, commandes et services de livraison en cours de développement.

## Contenu du dépôt
- `lib/` : application Flutter (Android/Web) et écrans.
- `supabase/migrations/` : schéma SQL et politiques de sécurité/RLS.
- `supabase/functions/` : fonctions Edge de paiement actuellement présentes dans le dépôt.
- `.github/workflows/build.yml` : workflow CI GitHub Actions.
- `DEPLOIEMENT_GITHUB.md` : instructions de publication et vérifications requises.
- `NOTES_VERSION.md` : ce qui a été ajouté dans cette archive et ce qui reste à valider.

## Important
Cette archive est une mise à jour de développement, pas une certification de mise en production. Les paiements réels, webhooks, politiques RLS, migrations et parcours de commande doivent être testés sur un projet Supabase de test avant la production. Ne placez jamais de clé privée de paiement ou de `service_role` dans Flutter/GitHub.

## Flutter
```bash
flutter pub get
flutter analyze
flutter test
flutter build web --release
```

## Sprint V23 — rapprochement financier
Voir `docs/SPRINT_EXTRA_TURBO_V23.md`. Migration `0033_financial_reconciliation_v23.sql` : rapport agrégé en lecture seule et confirmation de recharge Plop Plop plus stricte. Ne pas déployer sans staging et comparaison avec le relevé marchand du prestataire.


## V24 — rapprochement financier
Voir `docs/SPRINT_EXTRA_TURBO_V24.md`. Appliquer la migration `0034_financial_reconciliation_v24.sql` après les migrations précédentes sur staging avant production.

## Sprint V25 — parcours de commande
Voir `docs/SPRINT_EXTRA_TURBO_V25_CHECKOUT.md`. Le client est envoyé vers « Mes commandes » après réservation, où le paiement s'effectue avec le portefeuille correspondant à la devise de la commande. Exécuter `./scripts_validate_v25.sh` pour les contrôles statiques. Ces contrôles ne remplacent pas `flutter analyze`, les tests Flutter ou les essais d'intégration Supabase.

### HAITIKET V26 — garde-fous financiers
Voir `docs/SPRINT_EXTRA_TURBO_V26.md`. La migration `0035_financial_release_and_checkout_guards_v26.sql` durcit l'idempotence du paiement de commande et bloque la libération automatique des gains en présence de litige ou de remboursement actif. Appliquer d'abord sur une base de staging.

## Sprint V27 — livraison sécurisée

Voir `docs/SPRINT_EXTRA_TURBO_V27.md` pour les contrôles collecte/remise, l'audit de livraison et les limites de validation.

## Sprint V28 — parcours commerciaux
Voir `docs/SPRINT_EXTRA_TURBO_V28.md`. La migration `0037_commercial_flows_audit_v28.sql` ajoute le tarif annuel configurable et un audit commercial en lecture seule. Appliquer et valider sur staging avant production.

## HAITIKET V29 — préparation au lancement
Voir `docs/SPRINT_EXTRA_TURBO_V29.md`. Après installation de la migration `0038`, l'administration peut agréger les audits financiers, garde-fous, livraison et commerciaux. Ce rapport reste un outil de diagnostic et ne certifie pas la production.

## HAITIKET V30 — contrôles qualité automatisés

Voir `docs/SPRINT_EXTRA_TURBO_V30.md`. Exécuter `./scripts_validate_v30.sh` pour lancer les contrôles statiques V25–V29, vérifier la séquence des migrations et détecter certains noms de secrets côté Flutter. Le workflow `.github/workflows/quality-gates.yml` exécute ces contrôles sur push et pull request. Il ne remplace pas les builds Flutter ni les tests sur Supabase de staging.

## Qualité V31

La validation statique consolidée se lance avec `./scripts_validate_v31.sh`. GitHub Actions exécute également `flutter analyze` et `flutter test`. Ces contrôles ne remplacent pas les tests d'intégration sur une base Supabase de staging ni les essais du prestataire Plop Plop.

## V33 — Financial regression contract

See `docs/SPRINT_EXTRA_TURBO_V33.md` and run `./scripts_validate_v33.sh`. The SQL regression contract is read-only and must be executed against staging after migrations; static checks do not constitute a live database test.

## Contrôle de déploiement V34

Le script `scripts_validate_v34.sh` lance les contrôles statiques cumulés. Pour inventorier un environnement Supabase réel, consulter `docs/SPRINT_EXTRA_TURBO_V34.md` et exécuter le SQL V34 en lecture seule avec un accès autorisé. Les contrôles locaux ne remplacent pas les tests de staging.

## Sprint V36 — recette financière et état du développement

- `docs/SPRINT_EXTRA_TURBO_V36.md` contient la matrice de recette staging (wallets, commandes, remboursements, livraisons et litiges).
- `docs/ETAT_DEVELOPPEMENT_HAITIKET_V36.md` distingue les éléments présents dans le dépôt des validations encore nécessaires.
- `scripts_validate_v36.sh` vérifie les contrats statiques. Il ne remplace pas les tests sur une instance Supabase de staging.

## V39 — Release acceptance gate

Voir `docs/ETAT_DEVELOPPEMENT_HAITIKET_V39.md`, la checklist bloquante `docs/qa/RELEASE_CHECKLIST_V39.md` et la matrice `docs/qa/acceptance_matrix_v39.csv`. Les statuts des scénarios sont `NOT_RUN` jusqu'à exécution réelle avec preuve sur staging. Lancer `./scripts_validate_v39.sh` pour contrôler localement les artefacts; cela ne teste pas les paiements réels.

## HAITIKET V40 — Contrat commande/livraison

V40 ajoute un audit SQL structurel en lecture seule et une matrice de recette pour le cycle de commande, la collecte, la livraison et la libération des revenus. Lancez `./scripts_validate_v40.sh` pour les contrôles statiques. Pour exécuter l'audit SQL sur une base de staging autorisée, configurez `STAGING_ENVIRONMENT=staging`, `ALLOW_STAGING_READONLY_AUDIT=YES` et `STAGING_DATABASE_URL`, puis lancez `./scripts_run_order_delivery_contract_v40.sh`. Ne publiez jamais l'URL de connexion. Les scénarios de `docs/qa/order_delivery_matrix_v40.csv` restent `NOT_RUN` jusqu'à exécution avec preuves.

## HAITIKET V41 — tests avant publication

V41 ajoute `flutter test` comme étape bloquante dans les workflows Web et Android, avant les compilations, et vérifie ce contrat avec `./scripts_validate_v41.sh`. La gate `docs/qa/RELEASE_GATE_V41.md` liste les preuves de livraison qui restent `NOT_RUN` jusqu'à une exécution réelle. Les tests statiques ne prouvent pas le fonctionnement des paiements ni du projet Supabase distant.

## HAITIKET V42 — intégrité des ressources de publication

V42 bloque les builds si les logos ou mascottes requis sont absents/corrompus et si la génération des icônes échoue. Lancez `./scripts_validate_v42.sh` pour les contrôles statiques et consultez `docs/SPRINT_EXTRA_TURBO_V42.md` ainsi que `docs/qa/RELEASE_GATE_V42.md`. La réussite locale ne remplace pas le build GitHub Actions, les essais sur appareils, ni la recette Supabase/Plop Plop de staging.


### V43 — Annonces globales et identité FIBRAXA
Voir `docs/SPRINT_EXTRA_TURBO_V43.md`. Le message global nécessite l’application de la migration Supabase `0039_global_announcements_v43.sql` et une validation Realtime en staging avant la production.

### V44 — Export CSV du tableau de bord

Le tableau de bord administrateur permet de copier ses indicateurs scalaires actuels en CSV vers le presse-papiers. Ce contrôle n'ajoute aucun endpoint ni écriture métier. Lancez `./scripts_validate_v44.sh`. Le test Flutter, l'analyse Dart et les compilations restent à exécuter dans GitHub Actions avant de considérer la version validée.


### V45 — Journal d'audit administrateur

La console dispose d'un onglet de consultation en lecture seule du journal d'audit, avec filtre et limite serveur de 200 entrées. Appliquez `supabase/migrations/0040_admin_audit_log_v45.sql` en staging puis lancez `./scripts_validate_v45.sh`. Les tests Flutter, builds et contrôles de permissions distants doivent encore être exécutés avant production.


## V46 — Export CSV du journal administratif

V46 ajoute l’export CSV des entrées filtrées du journal administratif, avec échappement CSV et neutralisation des préfixes de formules de tableur. La portée est limitée aux 200 entrées au plus chargées dans l’écran. Voir `docs/SPRINT_EXTRA_TURBO_V46.md`; les tests Flutter et staging restent requis.

## V47 — Statistiques historiques administratives

V47 ajoute un historique quotidien des commandes sur 7, 30 ou 90 jours, avec graphiques distincts pour HTG et USD. La fonction SQL `admin_order_history_v47` est en lecture seule, nécessite une session authentifiée et une console administrateur déverrouillée, et limite les périodes à 90 jours. Appliquer `supabase/migrations/0041_admin_order_history_v47.sql` en staging avant d’utiliser cette vue. Les montants sont exprimés en unités mineures et ne constituent pas un relevé comptable.


## V48 — Boutique officielle HAITIKET

Le panneau administration propose un onglet « Boutique officielle » pour créer et personnaliser la boutique de la plateforme sans abonnement vendeur. Ses produits utilisent la source Marketplace et portent un badge officiel. Appliquer `supabase/migrations/0042_official_platform_shop_v48.sql` en staging, puis tester les permissions et le parcours produits/commandes avant la production. Voir `docs/SPRINT_EXTRA_TURBO_V48.md`.
## HAITIKET V49 — Boutique officielle à la une

La boutique officielle peut mettre ses produits à la une depuis son panneau d’administration. Les produits sélectionnés apparaissent avant les autres dans le catalogue et portent le badge « À la une ». Cette action est limitée côté serveur à un administrateur déverrouillé et est consignée dans le journal d’audit. Voir `docs/SPRINT_EXTRA_TURBO_V49.md`.


## HAITIKET V50 — Tableau de gestion de la boutique officielle
V50 ajoute au panneau de la boutique officielle des indicateurs de catalogue, des alertes de stock faible, les commandes récentes par statut et les montants de commandes HTG/USD affichés séparément. Les chiffres de commandes sont limités aux 50 plus récentes et ne sont pas un relevé comptable. Voir `docs/SPRINT_EXTRA_TURBO_V50.md` et lancer `./scripts_validate_v50.sh`. Les tests Flutter et la recette Supabase de staging restent nécessaires.


## HAITIKET V51 — Suivi du cycle de vie des promotions
V51 ajoute un résumé des coupons valides, visibles, expirés ou ayant atteint leur quota. Le statut affiché est indicatif et ne remplace pas la validation serveur au paiement. Voir `docs/SPRINT_EXTRA_TURBO_V51.md` et lancer `./scripts_validate_v51.sh`. Les contrôles Flutter et la recette Supabase de staging restent nécessaires.


## V52 — Garde-fous de pré-lancement

V52 ajoute `scripts_validate_v52.sh` au workflow de qualité afin de vérifier statiquement plusieurs invariants de paiements, portefeuilles, coupons, livraison et boutique officielle. Voir `docs/SPRINT_EXTRA_TURBO_V52.md` pour les limites et la recette Supabase de staging. Ces contrôles statiques ne constituent pas une validation de production.


## HAITIKET V53 — outils vendeur et publics multiples
V53 ajoute la sélection multi-publics sur les produits, le filtrage Marketplace par public, les suggestions de boutiques, la modification sécurisée du nom, la suspension/fermeture logique d'une boutique et le retrait volontaire d'un livreur. La recherche de nom unique est imposée en base après normalisation ; les doublons historiques doivent être résolus avant migration. Les liens de partage directs sont opérationnels pour la version Web sur le domaine courant ; les liens universels Android/iOS demandent encore une configuration du domaine officiel. Voir `docs/SPRINT_EXTRA_TURBO_V53.md` et lancer `./scripts_validate_v53.sh`.


## V54 — Espace fournisseur et achats en gros

V54 ajoute des offres de gros par produit et des demandes de réapprovisionnement entre boutiques professionnelles. Le serveur vérifie les propriétaires, les quantités, le stock disponible et les transitions de statut; le stock est réservé à l’acceptation puis décompté à la confirmation de remise. Ce flux n’effectue aucun paiement. Voir `docs/SPRINT_EXTRA_TURBO_V54.md` et appliquer `supabase/migrations/0045_wholesale_supplier_workflow_v54.sql` en staging après validation du schéma.


## V55 — Expiration des réservations fournisseurs

V55 ajoute une échéance de sept jours aux demandes de gros acceptées, permet à l'acheteur d'annuler une demande acceptée avant remise et fournit une RPC de nettoyage périodique réservée à `service_role`. Aucun paiement n'est déclenché. Voir `docs/SPRINT_EXTRA_TURBO_V55.md` et appliquer `supabase/migrations/0046_wholesale_reservation_expiry_v55.sql` en staging après vérification du schéma.


## HAITIKET V56 — Historique commercial fournisseurs

V56 journalise côté base les événements de demandes fournisseurs (création, acceptation, refus, annulation, expiration et remise) et les expose en lecture aux seuls propriétaires des boutiques participantes. Les clients authentifiés ne peuvent pas écrire dans le journal. Le backfill des demandes existantes crée une référence d'état courant, sans inventer les transitions historiques. Aucun paiement n'est déclenché. Voir `docs/SPRINT_EXTRA_TURBO_V56.md`, puis appliquer `supabase/migrations/0047_wholesale_request_history_v56.sql` en staging après revue des migrations précédentes.


## HAITIKET V57 — Rapports fournisseurs et export CSV
V57 ajoute des filtres 7/30/90 jours et par type d'événement au journal des achats fournisseurs, un résumé HTG/USD séparé et un export CSV copié dans le presse-papiers avec protection contre les formules de tableur. Le rapport est limité aux 200 événements les plus récents chargés; les sommes d'événements peuvent compter plusieurs étapes d'une même demande et ne constituent pas un relevé comptable ou une preuve de paiement. Voir `docs/SPRINT_EXTRA_TURBO_V57.md` et lancer `./scripts_validate_v57.sh`. La compilation Flutter et les tests Supabase de staging restent nécessaires.


## HAITIKET V58 — Registre de stock professionnel
V58 ajoute un journal des stocks alimenté par un déclencheur SQL, une RPC sécurisée d'ajustement avec motif obligatoire et protection des quantités réservées aux achats fournisseurs et un écran d'inventaire accessible depuis le centre fournisseurs. Les propriétaires de boutiques peuvent consulter leurs mouvements; les écritures directes du client sont interdites. La table `product_stock_movements` suit `products.stock` et ne couvre pas encore `product_variants.stock` ni l'affectation à chaque commande de détail. Voir `docs/SPRINT_EXTRA_TURBO_V58.md` et lancer `./scripts_validate_v58.sh`. Les tests Flutter et Supabase de staging restent nécessaires.


## HAITIKET V59 — Journal des variantes
V59 étend la traçabilité aux stocks de variantes (taille/couleur), ajoute une RPC sécurisée d'ajustement et des commandes d'ajustement par variante dans l'écran Inventaire. Le stock agrégé du produit reste synchronisé par le déclencheur existant. Les références vers commandes/remises/retours sont préparées mais pas encore alimentées par tous les parcours métier. Les mouvements de variante et les mouvements agrégés peuvent tous deux être consignés pour une même opération. Aucun paiement n'est déclenché. Voir `docs/SPRINT_EXTRA_TURBO_V59.md` et lancer `./scripts_validate_v59.sh`; tests Flutter et Supabase staging obligatoires avant production.


## HAITIKET V60 — Traçabilité et sécurité opérationnelle
V60 rattache les mouvements de stock aux commandes et remises fournisseurs, ajoute les entrées de stock documentées (réception/retour), impose un délai de 30 jours et une revue admin pour les demandes de suppression de boutique, traite les commandes actives et met les remboursements en file. Le KYC privé calcule l'âge côté serveur et distingue les pièces requises pour majeurs et mineurs; l'activation des boutiques et l'approbation des livreurs exigent une vérification approuvée. Les badges vérifiés sont distincts du Bazar. Les actions admin de bannissement/rétablissement/suppression logique sont auditées. Voir `docs/SPRINT_EXTRA_TURBO_V60.md`, lancer `./scripts_validate_v60.sh`. Le test de course réel `tests/concurrency/run_variant_stock_race_v60.sh` exige une base Supabase de staging jetable et un SKU de test à stock 1. Les remboursements ne sont pas déclarés exécutés sans confirmation réelle du prestataire; Flutter et migrations SQL doivent être testés avant production.

## HAITIKET V61 — Réactivation explicite des boutiques
V61 corrige le cycle de suppression : un refus administratif ne réactive plus automatiquement une boutique après annulation de commandes. La réactivation devient une action explicite du propriétaire, soumise au KYC approuvé et à l'absence de remboursements non exécutés, et laisse une trace d'audit. Voir `docs/SPRINT_EXTRA_TURBO_V61.md`; lancer `./scripts_validate_v61.sh`. Migration SQL, compatibilité des triggers et parcours Flutter doivent être testés sur Supabase de staging avant production.

## HAITIKET V62 — Contrôle de préparation opérationnelle
V62 ajoute une photographie administrative en lecture seule des principaux blocages opérationnels : remboursements en attente et anciens, KYC à examiner, suppressions de boutiques en cours, suppressions bloquées par des remboursements, commandes contestées et paiements nécessitant une réconciliation. La fonction ne modifie aucun statut et ne confirme pas les remboursements prestataire. Voir `docs/SPRINT_EXTRA_TURBO_V62.md`; appliquer `supabase/migrations/0052_release_readiness_audit_v62.sql` en staging et vérifier les permissions avant production.


## HAITIKET V63 — Centre de contrôle administratif

Ajoute un onglet de contrôle opérationnel en lecture seule basé sur le snapshot `admin_release_readiness_v62()`. Il présente les remboursements non résolus et anciens, les files KYC, les demandes de suppression de boutique, les suppressions bloquées par des remboursements, les litiges et les paiements nécessitant un rapprochement. Le rapport peut être copié en JSON. Aucun remboursement ni fermeture n'est exécuté depuis cet écran. Voir `docs/SPRINT_EXTRA_TURBO_V63.md`.

## HAITIKET V64 — Contrat d'acceptation avant lancement

Ajoute `scripts_validate_v64.sh`, un contrôle statique transversal des garde-fous de stock, du cycle de vie des boutiques, du KYC, du centre de contrôle administratif et des étapes Flutter CI. Les scénarios réels d'achat concurrent, paiement/webhook, annulation/remboursement, suppression et bannissement sont documentés dans `docs/SPRINT_EXTRA_TURBO_V64.md` et doivent être exécutés sur un environnement Supabase de staging avant production. Le contrôle statique ne remplace pas ces tests d'intégration.


## V65 — Tests de contrat exécutables

V65 ajoute `tests/release/test_release_contract_v65.py`, une suite Python exécutable qui contrôle la présence des contrats critiques (stock, concurrence, suppression de boutique, réactivation, KYC, audit de préparation et CI). Lancer `./scripts_validate_v65.sh`. Ces tests inspectent le code source et ne remplacent pas les tests PostgreSQL/Supabase sur une base de staging.
\n\n## V66 — Bazar KYC et icône\nVoir `docs/SPRINT_EXTRA_TURBO_V66.md`. Le Bazar exige désormais un KYC approuvé côté interface et base de données. Icône panda verte : `assets/logo.png`.\n

V66.1 corrige les chemins des mascottes pour Flutter/CI et renumérote la migration Bazar KYC en `0053_bazar_kyc_gate_app_icon_v66.sql` afin d’éviter un doublon avec la migration V61. Voir `docs/SPRINT_EXTRA_TURBO_V66_1.md`.
