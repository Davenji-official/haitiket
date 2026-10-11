import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../data/repo.dart';
import '../i18n.dart';
import '../theme.dart';
import 'fx.dart';
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

class ShopScreen extends StatelessWidget {
  final String shopId;
  const ShopScreen(this.shopId, {super.key});

  Future<Map<String, dynamic>> load() async {
    final info = await Repo.shopInfo(shopId);
    final rating = await Repo.shopRating(shopId);
    final products = await Repo.products(shopId: shopId, limit: 40);
    final reviews = await Repo.shopReviews(shopId);
    return {'info': info, 'rating': rating, 'products': products, 'reviews': reviews};
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Boutique', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: FutureBuilder<Map<String, dynamic>>(
          future: load(),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return const Padding(padding: EdgeInsets.all(18), child: EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.'));
            final d = s.data!;
            final info = d['info'] as Map<String, dynamic>;
            final rating = d['rating'] as Map<String, dynamic>;
            final products = List<Map<String, dynamic>>.from(d['products'] as List);
            final reviews = List<Map<String, dynamic>>.from(d['reviews'] as List);
            return ListView(padding: const EdgeInsets.all(18), children: [
              Text('${info['name']}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: C.ink)),
              Text('${info['city'] ?? ''}', style: const TextStyle(color: C.muted, fontSize: 17)),
              const SizedBox(height: 8),
              Stars(rating['avg_rating'] as num?, (rating['n'] as num).toInt()),
              const SizedBox(height: 20),
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
            ]);
          },
        ),
      );
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapState();
}

class _MapState extends State<MapScreen> {
  final controller = MapController();
  late final Future<List<Map<String, dynamic>>> f = Repo.shopsGeo();
  Position? me;

  Future<void> locate() async {
    final p = await myPosition(context);
    if (p == null) return;
    setState(() => me = p);
    controller.move(LatLng(p.latitude, p.longitude), 14);
  }

  String shopLine(Map<String, dynamic> s, double lat, double lng) {
    final city = (s['city'] ?? '').toString();
    if (me == null) return city;
    final d = fmtKm(distKm(me!.latitude, me!.longitude, lat, lng));
    return '$city · à $d à vol d\u2019oiseau';
  }

  void openShop(Map<String, dynamic> s) {
    final lat = (s['lat'] as num).toDouble(), lng = (s['lng'] as num).toDouble();
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['name']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: C.ink)),
          Text(shopLine(s, lat, lng), style: const TextStyle(color: C.muted)),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Voir la boutique',
            icon: Icons.storefront,
            onPressed: () {
              Navigator.pop(c);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(s['id'] as String)));
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Carte'), style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        floatingActionButton: FloatingActionButton.extended(onPressed: locate, backgroundColor: C.ink, foregroundColor: Colors.white, icon: const Icon(Icons.my_location), label: Text(tr('Près de moi'))),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            final shops = s.data ?? [];
            return Stack(children: [
              FlutterMap(
                mapController: controller,
                options: const MapOptions(initialCenter: LatLng(18.5392, -72.335), initialZoom: 11),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.haitiket.haitiket'),
                  MarkerLayer(markers: [
                    for (final sh in shops)
                      Marker(
                        point: LatLng((sh['lat'] as num).toDouble(), (sh['lng'] as num).toDouble()),
                        width: 48,
                        height: 48,
                        child: Pressable(onTap: () => openShop(sh), child: const Icon(Icons.location_on, color: C.terracotta, size: 46)),
                      ),
                    if (me != null) Marker(point: LatLng(me!.latitude, me!.longitude), width: 40, height: 40, child: const Icon(Icons.my_location, color: Colors.blue, size: 34)),
                  ]),
                  const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
                ],
              ),
              if (s.connectionState == ConnectionState.done && shops.isEmpty)
                Positioned(top: 12, left: 12, right: 12, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)), child: const Text("Aucune boutique n'a encore partagé sa position.", style: TextStyle(color: C.ink, fontWeight: FontWeight.w700)))),
            ]);
          },
        ),
      );
}
