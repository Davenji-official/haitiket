import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data/repo.dart';
import '../i18n.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens8.dart';
import 'widgets.dart';

double distKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

String fmtKm(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

/// Position réelle de l'appareil (jamais inventée). Renvoie null si refusée ou indisponible.
Future<Position?> myPosition(BuildContext context) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) toast(context, 'Activez la localisation de votre appareil.');
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (context.mounted) toast(context, 'Autorisation de localisation refusée.');
      return null;
    }
    return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
  } catch (_) {
    if (context.mounted) toast(context, 'Position indisponible.');
    return null;
  }
}

Future<String?> askText(BuildContext c, String title, {String hint = '', bool obscure = false, TextInputType? type}) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, obscureText: obscure, keyboardType: type, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('Valider')),
      ],
    ),
  );
}

Future<void> showPin(BuildContext context, String orderId, String label) async {
  try {
    final pin = await Repo.getOrderPin(orderId);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(label),
        content: pin == null
            ? const Text("Aucun code disponible pour le moment. Il apparaît une fois la commande payée et confirmée.")
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(pin, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8, color: C.ink)),
                const SizedBox(height: 8),
                const Text('Ne le communiquez qu\'à la personne qui vous remet ou récupère le colis.', textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
              ]),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fermer'))],
      ),
    );
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}

Future<void> reviewDialog(BuildContext context, String orderId) async {
  int rating = 5;
  final ctl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (_, set) => AlertDialog(
        title: const Text('Votre avis'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++) IconButton(onPressed: () => set(() => rating = i), icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_border_rounded, color: C.yellow, size: 34)),
          ]),
          TextField(controller: ctl, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(hintText: 'Commentaire (facultatif)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Publier')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await Repo.createReview(orderId, rating, ctl.text);
    if (context.mounted) toast(context, 'Merci pour votre avis !');
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}

class Stars extends StatelessWidget {
  final num? avg;
  final int n;
  const Stars(this.avg, this.n, {super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, color: C.yellow, size: 20),
        const SizedBox(width: 4),
        Text(n == 0 ? "Pas encore d'avis" : '${avg ?? 0} ($n avis)', style: const TextStyle(fontWeight: FontWeight.w700, color: C.muted)),
      ]);
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsState();
}

class _NotificationsState extends State<NotificationsScreen> {
  late final Future<List<Map<String, dynamic>>> f = Repo.myNotifications().then((l) {
    Repo.markNotificationsRead().catchError((_) {});
    return l;
  });

  IconData icon(String k) => switch (k) {
        'order' => Icons.receipt_long_outlined,
        'message' => Icons.chat_bubble_outline,
        'support' => Icons.support_agent_outlined,
        'job' => Icons.two_wheeler_outlined,
        'shop' => Icons.storefront_outlined,
        'courier' => Icons.badge_outlined,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        Padding(padding: const EdgeInsets.only(bottom: 18), child: Text(tr('Notifications'), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1))),
        if (currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour voir vos notifications.')
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: f,
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              final items = s.data ?? [];
              if (items.isEmpty) return const EmptyState(title: 'Rien de nouveau', text: 'Vos alertes de commandes, messages et missions apparaîtront ici.');
              return Column(children: [
                for (var i = 0; i < items.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: Card(
                      color: items[i]['read_at'] == null ? C.mint : Colors.white,
                      child: ListTile(
                        leading: Icon(icon(items[i]['kind'] as String), color: C.green),
                        title: Text('${items[i]['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: items[i]['body'] == null ? null : Text('${items[i]['body']}'),
                      ),
                    ),
                  ),
              ]);
            },
          ),
      ]);
}

class ShopScreen extends StatefulWidget {
  final String shopId;
  const ShopScreen(this.shopId, {super.key});
  @override
  State<ShopScreen> createState() => _ShopState();
}

class _ShopState extends State<ShopScreen> {
  late final Future<Map<String, dynamic>> f = load();
  bool? following;
  int followDelta = 0;

  Future<Map<String, dynamic>> load() async {
    final id = widget.shopId;
    final info = await Repo.shopInfo(id);
    final rating = await Repo.shopRating(id);
    final stats = await Repo.shopStats(id);
    final products = await Repo.products(shopId: id, limit: 40);
    final reviews = await Repo.shopReviews(id);
    final fol = await Repo.isFollowing(id);
    return {'info': info, 'rating': rating, 'stats': stats, 'products': products, 'reviews': reviews, 'following': fol};
  }

  Future<void> toggle(bool current) async {
    if (currentUser() == null) return toast(context, 'Connectez-vous pour suivre une boutique.');
    try {
      final now = await Repo.toggleFollow(widget.shopId);
      setState(() {
        followDelta += now == current ? 0 : (now ? 1 : -1);
        following = now;
      });
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Widget stat(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 18, color: c), const SizedBox(width: 6), Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: c))]),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
          if (s.hasError) return Scaffold(appBar: AppBar(), body: const Padding(padding: EdgeInsets.all(18), child: EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.')));
          final d = s.data!;
          final info = d['info'] as Map<String, dynamic>;
          final rating = d['rating'] as Map<String, dynamic>;
          final stats = d['stats'] as Map<String, dynamic>;
          final products = List<Map<String, dynamic>>.from(d['products'] as List);
          final reviews = List<Map<String, dynamic>>.from(d['reviews'] as List);
          final primary = hexColor(info['color_primary'] as String?) ?? C.ink;
          final accent = hexColor(info['color_accent'] as String?) ?? C.terracotta;
          final fol = following ?? (d['following'] as bool);
          final banner = info['banner_url'] as String?;
          final logo = info['logo_url'] as String?;
          final slogan = info['slogan'] as String?;
          final personal = info['kind'] == 'personal';
          return Scaffold(
            appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text('${info['name']}', style: const TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(tooltip: 'Signaler', icon: const Icon(Icons.flag_outlined), onPressed: () => reportDialog(context, 'shop', widget.shopId))]),
            body: ListView(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [primary, accent])),
                  child: banner == null ? null : Image.network(banner, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                ),
                Positioned(
                  left: 18,
                  bottom: -38,
                  child: CircleAvatar(radius: 42, backgroundColor: Colors.white, child: CircleAvatar(radius: 38, backgroundColor: accent, backgroundImage: logo == null ? null : NetworkImage(logo), child: logo == null ? const Icon(Icons.storefront, color: Colors.white, size: 36) : null)),
                ),
              ]),
              const SizedBox(height: 50),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${info['name']}', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: primary)),
                  if (slogan != null) Text(slogan, style: TextStyle(fontSize: 17, fontStyle: FontStyle.italic, color: accent, fontWeight: FontWeight.w700)),
                  Text('${personal ? 'Vendeur particulier (Bazar)' : 'Boutique professionnelle'} · ${info['city'] ?? ''}', style: const TextStyle(color: C.muted)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    stat(Icons.people_outline, '${((stats['followers'] as num).toInt() + followDelta)} abonné(s)', primary),
                    stat(Icons.inventory_2_outlined, '${stats['products']} produit(s)', primary),
                    stat(Icons.shopping_bag_outlined, '${stats['sold']} vendu(s)', primary),
                    Stars(rating['avg_rating'] as num?, (rating['n'] as num).toInt()),
                  ]),
                  const SizedBox(height: 16),
                  Pressable(
                    onTap: () => toggle(fol),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      decoration: BoxDecoration(color: fol ? Colors.white : accent, border: Border.all(color: accent, width: 2), borderRadius: BorderRadius.circular(26)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                          child: Icon(fol ? Icons.notifications_active : Icons.notifications_none, key: ValueKey(fol), color: fol ? accent : Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Text(fol ? 'Abonné' : 'Suivre la boutique', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: fol ? accent : Colors.white)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Abonnez-vous pour être averti de chaque nouveau produit.', style: TextStyle(color: C.muted)),
                  const SizedBox(height: 22),
                  const Text('Produits', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
                  const SizedBox(height: 10),
                  if (products.isEmpty) const Text('Aucun produit disponible.', style: TextStyle(color: C.muted)) else ProductGrid(products),
                  const SizedBox(height: 24),
                  const Text('Avis des clients', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
                  const SizedBox(height: 10),
                  if (reviews.isEmpty) const Text("Aucun avis. Les avis proviennent uniquement d'achats réellement livrés.", style: TextStyle(color: C.muted)),
                  for (final r in reviews)
                    Card(
                      color: Colors.white,
                      child: ListTile(
                        title: Row(children: [for (var i = 0; i < (r['rating'] as int); i++) const Icon(Icons.star_rounded, color: C.yellow, size: 18)]),
                        subtitle: r['comment'] == null ? null : Text('${r['comment']}'),
                      ),
                    ),
                  const SizedBox(height: 30),
                ]),
              ),
            ]),
          );
        },
      );
}
