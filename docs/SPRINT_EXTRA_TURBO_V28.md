# HAITIKET V28 — parcours commerciaux

## Changements
- Migration `0037_commercial_flows_audit_v28.sql` ajoute le réglage annuel `shop_fee_yearly_usd` à 200 USD uniquement s'il n'existe pas déjà; la valeur reste modifiable par un administrateur.
- La fonction `admin_set_setting` accepte maintenant ce tarif annuel et le valide comme montant USD positif.
- La politique de lecture publique des réglages expose le tarif annuel afin que l'application puisse afficher le prix.
- L'écran d'abonnement boutique propose les formules mensuelle et annuelle en USD, via le portefeuille interne. Le serveur reste responsable du montant débité.
- L'audit commercial V28 est en lecture seule et rapporte les annonces Bazar publiées mais expirées, les abonnements professionnels expirés, les transactions de frais et certains écarts entre abonnements actifs et transactions de portefeuille.
- Un bouton permet de lancer l'audit depuis le panneau d'administration.

## Limites / installation
- Appliquer les migrations dans l'ordre jusqu'à `0037` sur un environnement de staging sauvegardé.
- L'audit ne corrige pas automatiquement les données et ne déclenche aucun mouvement financier.
- Un abonnement actif sans transaction de portefeuille correspondante est un avertissement, pas une preuve définitive de fraude : des paiements historiques/externes peuvent exister.
- Les abonnements ne peuvent pas être renouvelés avant expiration avec la logique existante; l'interface le signale au lieu de prétendre que le renouvellement anticipé est disponible.
- Contrôles statiques seulement. Pas de compilation Flutter/Dart ni d'exécution réelle de la migration Supabase dans cet environnement.
