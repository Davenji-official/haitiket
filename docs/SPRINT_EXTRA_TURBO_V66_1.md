# HAITIKET V66.1 — correction des ressources et de la migration

## Corrections apportées après contrôle du ZIP V66
- Synchronisation des 14 mascottes WebP et de `logo_t.png` vers `assets/`, le chemin utilisé par `pubspec.yaml` et `Image.asset()`.
- Mise à jour des étapes CI web/Android et qualité afin de recopier explicitement les mascottes depuis `lib/assets/mascots/` sans écraser la nouvelle icône `assets/logo.png`.
- Correction du numéro de migration Bazar KYC en `0053_bazar_kyc_gate_app_icon_v66.sql` : `0051_shop_reactivation_safety_v61.sql` et `0052_release_readiness_audit_v62.sql` existaient déjà. Cela évite le doublon `0051`.
- Rétablissement du bit exécutable des scripts shell utilisés directement par la CI.

## Vérifications effectuées
- Archive ZIP lisible et intégrité des fichiers vérifiée.
- Les 14 images WebP sont décodables et référencées par le code Flutter.
- Contrôle statique des ressources de livraison et tests de contrats Python V65.
- Validateurs statiques jusqu'à V66 passés dans l'environnement disponible.

## Limites
Flutter et Dart ne sont pas installés dans l'environnement de contrôle : `flutter pub get`, `flutter analyze`, `flutter test` et les builds Android/Web n'ont pas été exécutés ici. La migration SQL et le flux KYC doivent encore être appliqués et testés sur une base Supabase de staging avant production.
