import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'screens2.dart';
import 'screens3.dart';
import 'screens4.dart';
import 'fx.dart';
import 'widgets.dart';

Widget _title(String t, [String? sub]) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1)),
      if (sub != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(sub, style: const TextStyle(fontSize: 17, color: C.muted, height: 1.4))),
      const SizedBox(height: 20),
    ]);

Widget _promo(BuildContext context, String title, String text, String cta, IconData icon, VoidCallback onTap) => Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(fontSize: 16, color: C.green, height: 1.4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        PrimaryButton(label: cta, icon: icon, onPressed: onTap),
      ]),
    );

Widget _notConfigured() => const EmptyState(title: 'En attente de configuration', text: "Le serveur n'est pas encore connecté. Ajoutez SUPABASE_URL et SUPABASE_ANON_KEY dans les secrets GitHub, puis relancez le build.");

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});
  @override
  State<MarketplaceScreen> createState() => _MarketplaceState();
}

class _MarketplaceState extends State<MarketplaceScreen> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: Repo.search,
        builder: (_, q, __) => ListView(padding: const EdgeInsets.all(18), children: [
          _title('Marketplace', 'Produits des boutiques professionnelles vérifiées.'),
          _promo(context, 'Vous êtes commerçant ?', 'Boutique professionnelle : 20 USD / mois. Vitrine, stock, commandes et livraison HAITIKET.', 'Ouvrir ma boutique', Icons.storefront, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopRequestScreen()))),
          SearchPill(onSubmit: (v) => Repo.search.value = v),
          if (q.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Résultats pour « $q »', style: const TextStyle(color: C.muted, fontWeight: FontWeight.w700))),
          const SizedBox(height: 20),
          if (!Config.configured)
            _notConfigured()
          else
            FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(q),
              future: Repo.products(q: q),
              builder: (_, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.hasError) return const EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.');
                final items = s.data ?? [];
                if (items.isEmpty) return EmptyState(title: q.isEmpty ? 'Aucun produit publié' : 'Aucun résultat', text: q.isEmpty ? 'Les produits apparaîtront ici dès que les boutiques en publieront.' : 'Essayez un autre mot-clé.');
                return ProductGrid(items);
              },
            ),
        ]),
      );
}

class BazarScreen extends StatelessWidget {
  const BazarScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        _title('Bazar', 'Achetez et vendez entre particuliers, près de chez vous.'),
        _promo(context, 'Vous êtes particulier ?', 'Publiez votre article : 2 USD pour 14 jours, sans boutique.', 'Publier une annonce', Icons.local_offer, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ListingFormScreen()))),
        if (!Config.configured)
          _notConfigured()
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Repo.listings(),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              final items = s.data ?? [];
              if (items.isEmpty) return const EmptyState(title: "Aucune annonce pour l'instant", text: 'Publiez le premier article depuis « Vendre ».');
              return Column(children: [
                for (final l in items)
                  Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      onTap: () => openChat(context, 'listing', l['id'] as String),
                      title: Text('${l['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${l['city'] ?? ''} · ${l['condition'] ?? ''}'),
                      trailing: Text(money(l['price_minor'] as num, (l['currency'] ?? 'HTG') as String), style: const TextStyle(fontWeight: FontWeight.w800, color: C.green)),
                    ),
                  ),
              ]);
            },
          ),
      ]);
}

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});
  @override
  State<NetworkScreen> createState() => _NetworkState();
}

class _NetworkState extends State<NetworkScreen> {
  final name = TextEditingController(), phone = TextEditingController(), zone = TextEditingController();
  String transport = 'moto';
  bool busy = false;

  Future<void> submit() async {
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty || zone.text.trim().isEmpty) return toast(context, 'Remplissez tous les champs.');
    setState(() => busy = true);
    try {
      await Repo.applyCourier(name.text.trim(), phone.text.trim(), transport, zone.text.trim());
      if (mounted) toast(context, 'Candidature envoyée. Vous serez contacté après vérification.');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        _title('HAITIKET Network', 'Devenez livreur indépendant. Chaque mission affiche votre rémunération avant acceptation.'),
        Field(name, 'Nom complet'),
        Field(phone, 'Téléphone', type: TextInputType.phone),
        DropdownButtonFormField<String>(
          initialValue: transport,
          decoration: const InputDecoration(labelText: 'Moyen de transport'),
          items: const [
            DropdownMenuItem(value: 'pied', child: Text('À pied')),
            DropdownMenuItem(value: 'velo', child: Text('Vélo')),
            DropdownMenuItem(value: 'moto', child: Text('Moto')),
            DropdownMenuItem(value: 'voiture', child: Text('Voiture')),
            DropdownMenuItem(value: 'camionnette', child: Text('Camionnette')),
          ],
          onChanged: (v) => setState(() => transport = v ?? 'moto'),
        ),
        const SizedBox(height: 12),
        Field(zone, "Zone d'activité (ex. Delmas)"),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Envoi…' : 'Envoyer ma candidature')),
        const SizedBox(height: 16),
        const EmptyState(title: 'Missions', text: "Les missions seront proposées après vérification de votre profil. Aucun livreur n'est affiché tant qu'il n'est pas réellement validé."),
      ]);
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        _title('Favoris'),
        if (currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour retrouver vos favoris sur tous vos appareils.')
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Repo.favorites(),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              final items = s.data ?? [];
              if (items.isEmpty) return const EmptyState(title: 'Aucun favori', text: 'Touchez le cœur sur un produit pour le garder ici.');
              return ProductGrid(items);
            },
          ),
      ]);
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: CartStore.lines,
        builder: (_, lines, __) {
          final l = lines.values.toList();
          final total = l.fold<int>(0, (a, x) => a + x.priceMinor * x.qty);
          return ListView(padding: const EdgeInsets.all(18), children: [
            _title('Panier'),
            if (l.isEmpty)
              const EmptyState(title: 'Votre panier est vide', text: 'Ajoutez des produits depuis la Marketplace.')
            else ...[
              for (final x in l)
                Card(
                  color: Colors.white,
                  child: ListTile(
                    title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(money(x.priceMinor, x.currency)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => CartStore.change(x.id, -1), icon: const Icon(Icons.remove_circle_outline)),
                      Text('${x.qty}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(onPressed: () => CartStore.change(x.id, 1), icon: const Icon(Icons.add_circle_outline)),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Total estimé : ${money(total, l.first.currency)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
              const SizedBox(height: 4),
              const Text('Le total final est recalculé par le serveur (livraison, frais, réductions).', style: TextStyle(color: C.muted)),
              const SizedBox(height: 16),
              PrimaryButton(label: 'Passer commande', icon: Icons.lock_outline, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()))),
              const SizedBox(height: 8),
              const Text('Paiement indisponible — en attente de configuration du prestataire.', style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
            ],
          ]);
        },
      );
}

class AccountScreen extends StatefulWidget {
  final VoidCallback onChanged;
  const AccountScreen({super.key, required this.onChanged});
  @override
  State<AccountScreen> createState() => _AccountState();
}

class _AccountState extends State<AccountScreen> {
  final email = TextEditingController(), pass = TextEditingController();
  bool busy = false;

  Future<void> auth(bool signup) async {
    setState(() => busy = true);
    try {
      if (signup) {
        await Repo.signUp(email.text.trim(), pass.text);
        if (mounted) toast(context, 'Compte créé. Vérifiez votre e-mail si une confirmation est demandée.');
      } else {
        await Repo.signIn(email.text.trim(), pass.text);
      }
      widget.onChanged();
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = currentUser();
    return ListView(padding: const EdgeInsets.all(18), children: [
      _title(u == null ? 'Se connecter' : 'Mon compte'),
      if (!Config.configured)
        _notConfigured()
      else if (u != null) ...[
        Text(u.email ?? '', style: const TextStyle(fontSize: 18, color: C.ink)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await Repo.signOut();
            widget.onChanged();
            if (mounted) setState(() {});
          },
          child: const Text('Se déconnecter'),
        ),
      ] else ...[
        Field(email, 'E-mail', type: TextInputType.emailAddress),
        Field(pass, 'Mot de passe', obscure: true),
        FilledButton(onPressed: busy ? null : () => auth(false), child: const Text('Se connecter')),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: busy ? null : () => auth(true), child: const Text('Créer un compte')),
      ],
    ]);
  }
}
