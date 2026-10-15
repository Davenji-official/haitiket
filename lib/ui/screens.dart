import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'screens2.dart';
import 'screens4.dart';
import 'fx.dart';
import 'screens5.dart';
import 'screens7.dart';
import 'map_screen.dart';
import '../i18n.dart';
import 'package:geolocator/geolocator.dart' show Position;
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
  String? cat;
  String sort = 'recent';
  bool nearby = false;
  Position? me;
  final minC = TextEditingController(), maxC = TextEditingController();
  late final Future<List<Map<String, dynamic>>> cats = Repo.categories();
  Future<List<Map<String, dynamic>>>? f;
  String lastQ = '\u0000';

  int? minor(TextEditingController c) {
    final v = double.tryParse(c.text.replaceAll(',', '.'));
    return v == null ? null : (v * 100).round();
  }

  Future<List<Map<String, dynamic>>> load(String q) async {
    final items = await Repo.products(source: 'marketplace', q: q, categoryId: cat, minMinor: minor(minC), maxMinor: minor(maxC), sort: sort, limit: 60);
    if (me != null) {
      for (final p in items) {
        final sh = p['shops'] as Map?;
        final la = sh?['lat'], ln = sh?['lng'];
        if (la != null && ln != null) p['_dist'] = distKm(me!.latitude, me!.longitude, (la as num).toDouble(), (ln as num).toDouble());
      }
      if (nearby) items.sort((a, b) => ((a['_dist'] as double?) ?? 1e9).compareTo((b['_dist'] as double?) ?? 1e9));
    }
    return items;
  }

  void refresh() => setState(() => f = load(Repo.search.value));

  Widget chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: sel, onSelected: (_) => onTap()),
      );

  Future<void> toggleNearby(bool v) async {
    if (v && me == null) {
      final p = await myPosition(context);
      if (p == null) return;
      me = p;
    }
    nearby = v;
    refresh();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: Repo.search,
        builder: (_, q, __) {
          if (q != lastQ) {
            lastQ = q;
            f = load(q);
          }
          return ListView(padding: const EdgeInsets.all(18), children: [
            Row(children: [
              Expanded(child: Text(tr('Marketplace'), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1))),
              Pressable(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MapScreen(kind: 'pro'))),
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.map_outlined, color: C.ink)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Produits des boutiques professionnelles vérifiées.', style: TextStyle(fontSize: 17, color: C.muted, height: 1.4)),
            const SizedBox(height: 16),
            _promo(context, tr('Vous êtes commerçant ?'), 'Boutique professionnelle : 20 USD / mois. Vitrine, stock, commandes et livraison HAITIKET.', tr('Ouvrir ma boutique'), Icons.storefront, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopRequestScreen()))),
            SearchPill(onSubmit: (v) => Repo.search.value = v),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: cats,
                builder: (_, s) => ListView(scrollDirection: Axis.horizontal, children: [
                  chip(tr('Toutes'), cat == null, () {
                    cat = null;
                    refresh();
                  }),
                  for (final c in s.data ?? [])
                    chip('${c['name']}', cat == c['id'], () {
                      cat = c['id'] as String;
                      refresh();
                    }),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: minC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix min (HTG)', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: maxC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix max (HTG)', isDense: true))),
              IconButton(onPressed: refresh, icon: const Icon(Icons.check_circle, color: C.green, size: 32)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              DropdownButton<String>(
                value: sort,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: 'recent', child: Text(tr('Plus récents'))),
                  DropdownMenuItem(value: 'price_asc', child: Text(tr('Prix croissant'))),
                  DropdownMenuItem(value: 'price_desc', child: Text(tr('Prix décroissant'))),
                ],
                onChanged: (v) {
                  sort = v ?? 'recent';
                  refresh();
                },
              ),
              const Spacer(),
              FilterChip(avatar: const Icon(Icons.near_me, size: 18), label: Text(tr('Près de moi')), selected: nearby, onSelected: toggleNearby),
            ]),
            if (q.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Résultats pour « $q »', style: const TextStyle(color: C.muted, fontWeight: FontWeight.w700))),
            const SizedBox(height: 14),
            if (!Config.configured)
              _notConfigured()
            else
              FutureBuilder<List<Map<String, dynamic>>>(
                future: f,
                builder: (_, s) {
                  if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (s.hasError) return const EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.');
                  final items = s.data ?? [];
                  if (items.isEmpty) return EmptyState(title: q.isEmpty ? 'Aucun produit trouvé' : 'Aucun résultat', text: 'Modifiez vos filtres ou votre recherche. Seuls les produits réellement en stock sont affichés.');
                  return ProductGrid(items);
                },
              ),
          ]);
        },
      );
}

class BazarScreen extends StatefulWidget {
  const BazarScreen({super.key});
  @override
  State<BazarScreen> createState() => _BazarState();
}

class _BazarState extends State<BazarScreen> {
  bool nearby = false;
  Position? me;
  late Future<List<Map<String, dynamic>>> f = load();

  Future<List<Map<String, dynamic>>> load() async {
    final items = await Repo.products(source: 'bazar', limit: 60);
    if (me != null) {
      for (final p in items) {
        final sh = p['shops'] as Map?;
        final la = sh?['lat'], ln = sh?['lng'];
        if (la != null && ln != null) p['_dist'] = distKm(me!.latitude, me!.longitude, (la as num).toDouble(), (ln as num).toDouble());
      }
      if (nearby) items.sort((a, b) => ((a['_dist'] as double?) ?? 1e9).compareTo((b['_dist'] as double?) ?? 1e9));
    }
    return items;
  }

  Future<void> toggleNearby(bool v) async {
    if (v && me == null) {
      final p = await myPosition(context);
      if (p == null) return;
      me = p;
    }
    setState(() {
      nearby = v;
      f = load();
    });
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {
          setState(() => f = load());
          await f;
        },
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Row(children: [
            const Expanded(child: Text('Bazar', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1))),
            Pressable(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MapScreen(kind: 'personal'))),
              child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.map_outlined, color: C.ink)),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('Achetez et vendez entre particuliers : paiement et livraison HAITIKET comme en boutique.', style: TextStyle(fontSize: 17, color: C.muted, height: 1.4)),
          const SizedBox(height: 16),
          _promo(context, tr('Vous êtes particulier ?'), 'Publiez votre article : 2 USD pour 14 jours, sans boutique professionnelle.', tr('Publier une annonce'), Icons.local_offer, () => startBazarListing(context)),
          Align(alignment: Alignment.centerRight, child: FilterChip(avatar: const Icon(Icons.near_me, size: 18), label: Text(tr('Près de moi')), selected: nearby, onSelected: toggleNearby)),
          const SizedBox(height: 12),
          if (!Config.configured)
            _notConfigured()
          else
            FutureBuilder<List<Map<String, dynamic>>>(
              future: f,
              builder: (_, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.hasError) return const EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.');
                final items = s.data ?? [];
                if (items.isEmpty) return const EmptyState(title: "Aucune annonce pour l'instant", text: 'Publiez le premier article du Bazar.');
                return ProductGrid(items);
              },
            ),
        ]),
      );
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
          final total = CartStore.totalMinor;
          return ListView(padding: const EdgeInsets.all(18), children: [
            _title(tr('Panier')),
            if (l.isEmpty)
              const EmptyState(title: 'Votre panier est vide', text: 'Ajoutez des produits depuis la Marketplace.')
            else ...[
              for (final x in l)
                Card(
                  color: Colors.white,
                  child: ListTile(
                    title: Text(x.variantLabel == null ? x.name : '${x.name} (${x.variantLabel})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${money(CartStore.unitFor(x), x.currency)} / unité${CartStore.unitFor(x) < x.basePrice ? ' · tarif quantité' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => CartStore.change(x.key, -1), icon: const Icon(Icons.remove_circle_outline)),
                      Text('${x.qty}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(onPressed: () => CartStore.change(x.key, 1), icon: const Icon(Icons.add_circle_outline)),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Total estimé : ${money(total, l.first.currency)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
              const SizedBox(height: 4),
              const Text('Le total final est recalculé par le serveur (livraison, frais, réductions).', style: TextStyle(color: C.muted)),
              const SizedBox(height: 16),
              PrimaryButton(label: tr('Passer commande'), icon: Icons.lock_outline, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()))),
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
