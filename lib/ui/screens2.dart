import 'dart:async';
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens3.dart';
import 'screens5.dart';
import 'screens6.dart';
import 'screens7.dart';
import 'screens8.dart';
import 'screens9.dart';
import 'specs.dart';
import 'widgets.dart';
import 'mascot.dart';
import '../i18n.dart';

int _jsonListCount(String value) { try { final x = jsonDecode(value.isEmpty ? '[]' : value); return x is List ? x.length : 0; } catch (_) { return 0; } }

String statusFr(String s) =>
    const {
      'PENDING_PAYMENT': 'En attente de paiement',
      'PAYMENT_PROCESSING': 'Paiement en cours',
      'PAID': 'Payée',
      'CONFIRMED': 'Confirmée',
      'PREPARING': 'En préparation',
      'READY_FOR_PICKUP': 'Prête à récupérer',
      'IN_TRANSIT': 'En livraison',
      'DELIVERED': 'Livrée',
      'COMPLETED': 'Terminée',
      'CANCELLED': 'Annulée',
      'DISPUTED': 'Litige',
      'REFUNDED': 'Remboursée',
    }[s] ??
    s;


class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutState();
}

class _CheckoutState extends State<CheckoutScreen> {
  String mode = 'pickup';
  final address = TextEditingController();
  final coupon = TextEditingController();
  late Future<List<Map<String, dynamic>>> addrs = Repo.myAddresses();
  bool busy = false;
  double? deliveryLat;
  double? deliveryLng;
  double? deliveryAccuracyM;
  String? coordinateAddressSnapshot;
  bool locating = false;

  Future<void> useCurrentLocation() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'Autorisez la localisation dans les paramètres pour utiliser votre position.');
        return;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) toast(context, 'Activez le GPS de votre téléphone puis réessayez.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      if (!mounted) return;
      setState(() {
        deliveryLat = position.latitude;
        deliveryLng = position.longitude;
        deliveryAccuracyM = position.accuracy;
        address.text = 'Position GPS (${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)})';
        coordinateAddressSnapshot = address.text;
      });
      toast(context, 'Position récupérée. Vérifiez que vous êtes bien à la destination souhaitée.');
    } catch (_) {
      if (mounted) toast(context, 'Impossible de récupérer le GPS. Vous pouvez saisir une adresse manuellement.');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  /// Étape de paiement juste après la création : solde du portefeuille, paiement en un geste ou recharge.
  Future<Set<String>> offerPayment(List<Map<String, dynamic>> orders) async {
    if (!mounted || orders.isEmpty) return <String>{};
    final balances = <String, num>{};
    try {
      final w = await Repo.myWalletV2();
      ((w['balances'] as Map?) ?? const {}).forEach((k, v) => balances['$k'] = (v as num?) ?? 0);
    } catch (_) {}
    final totals = <String, int>{};
    for (final o in orders) {
      final cur = '${o['currency']}';
      totals[cur] = (totals[cur] ?? 0) + ((o['total_minor'] as num?)?.toInt() ?? 0);
    }
    final lacking = totals.entries.where((e) => (balances[e.key] ?? 0) < e.value).toList();
    if (!mounted) return <String>{};
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: Text('${orders.length} commande(s) à payer'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final e in totals.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Total ${e.key} : ${money(e.value, e.key)}\nVotre solde ${e.key} : ${money(balances[e.key] ?? 0, e.key)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 6),
            Text(
              lacking.isEmpty
                  ? 'Vous pouvez payer maintenant avec votre portefeuille. Le vendeur est prévenu dès le paiement ; votre argent reste protégé par HAITIKET jusqu\'à la livraison.'
                  : 'Solde insuffisant en ${lacking.map((e) => e.key).join(' et ')}. Rechargez votre portefeuille (MonCash / NatCash), puis revenez valider votre panier : vos articles y restent.',
              style: const TextStyle(color: C.muted),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, 'later'), child: const Text('Garder dans le panier')),
          if (lacking.isNotEmpty) TextButton(onPressed: () => Navigator.pop(d, 'topup'), child: const Text('Recharger')),
          if (lacking.isEmpty) FilledButton(onPressed: () => Navigator.pop(d, 'pay'), child: const Text('Payer maintenant')),
        ],
      ),
    );
    if (!mounted) return <String>{};
    if (choice == 'topup') {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Portefeuille')), body: const WalletScreen())));
      return <String>{};
    }
    if (choice != 'pay') return <String>{};
    final paid = <String>{};
    String? error;
    for (final o in orders) {
      try {
        await Repo.payOrderFromWallet('${o['id']}');
        paid.add('${o['id']}');
      } catch (e) {
        error = Repo.err(e);
      }
    }
    if (!mounted) return paid;
    if (error != null) toast(context, 'Paiement partiel ou refusé : $error');
    return paid;
  }

  Future<void> submit() async {
    final lines = CartStore.lines.value.values.toList();
    if (lines.isEmpty) return;
    if (mode == 'delivery' && address.text.trim().isEmpty) {
      toast(context, 'Indiquez une destination ou choisissez un point sur la carte avant de commander.');
      return;
    }
    setState(() => busy = true);
    try {
      await Repo.cancelMyPendingOrders(); // libère d'anciennes réservations non payées avant de recommencer
      final orders = await Repo.createOrders(lines, mode, address.text.trim(), coupon.text);
      var locationSaved = true;
      final coordinatesMatchAddress = coordinateAddressSnapshot != null && address.text == coordinateAddressSnapshot;
      if (mode == 'delivery' && deliveryLat != null && deliveryLng != null && coordinatesMatchAddress) {
        for (final order in orders) {
          try {
            await Repo.setOrderDeliveryLocation(order['id'].toString(), deliveryLat!, deliveryLng!, accuracyM: deliveryAccuracyM);
          } catch (_) {
            locationSaved = false;
          }
        }
      }
      if (!mounted) return;
      final paidIds = await offerPayment(orders);
      // Les réservations non payées sont annulées (stock remis en vente) : leurs articles restent dans le panier.
      for (final o in orders) {
        if (!paidIds.contains('${o['id']}')) {
          try {
            await Repo.cancelOrder('${o['id']}');
          } catch (_) {}
        }
      }
      // Seuls les articles réellement payés quittent le panier.
      if (paidIds.isNotEmpty) CartStore.removePaidNames(await Repo.orderItemNames(paidIds));
      final paidNow = paidIds.length == orders.length;
      if (!mounted) return;
      final gpsMessage = mode == 'delivery' && deliveryLat != null && coordinatesMatchAddress
          ? (locationSaved
              ? ' Destination GPS enregistrée.'
              : ' Attention : la commande existe, mais les coordonnées GPS n’ont pas toutes été enregistrées. Contactez le support avant de recommander.')
          : '';
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      if (paidIds.isNotEmpty) {
        navigator.pushReplacement(MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Mes commandes', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))), body: const OrdersScreen())));
      } else {
        navigator.pop();
      }
      messenger.showSnackBar(SnackBar(content: Text(
        paidNow
            ? '${orders.length} commande(s) payée(s). Le vendeur est prévenu.$gpsMessage'
            : paidIds.isEmpty
                ? 'Rien n\'a été payé : vos articles restent dans le panier.'
                : '${paidIds.length} commande(s) payée(s). Les autres articles restent dans le panier.$gpsMessage',
      )));
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final lines = CartStore.lines.value.values.toList();
    final total = CartStore.totalMinor;
    return Scaffold(
      appBar: AppBar(title: const Text('Commande', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        if (currentUser() == null) const EmptyState(title: 'Connexion requise', text: 'Connectez-vous depuis le menu avant de commander.'),
        if (currentUser() != null) ...[
          const Text('Mode de remise', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
          RadioGroup<String>(
            groupValue: mode,
            onChanged: (v) => setState(() => mode = v ?? 'pickup'),
            child: const Column(children: [
              RadioListTile<String>(value: 'pickup', title: Text('Retrait chez le vendeur')),
              RadioListTile<String>(value: 'delivery', title: Text('Livraison HAITIKET')),
            ]),
          ),
          if (mode == 'delivery') ...[
            FutureBuilder<List<Map<String, dynamic>>>(
              future: addrs,
              builder: (_, s) {
                final l = s.data ?? [];
                if (l.isEmpty) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Choisir une adresse enregistrée'),
                    items: [for (final a in l) DropdownMenuItem(value: a['id'] as String, child: Text('${a['label']} · ${a['commune']}'))],
                    onChanged: (v) {
                      final a = l.firstWhere((x) => x['id'] == v);
                      address.text = formatAddress(a);
                      deliveryLat = (a['lat'] as num?)?.toDouble();
                      deliveryLng = (a['lng'] as num?)?.toDouble();
                      deliveryAccuracyM = null;
                      coordinateAddressSnapshot = address.text;
                      setState(() {});
                    },
                  ),
                );
              },
            ),
            Field(address, 'Adresse de livraison (commune, quartier, repères)'),
            OutlinedButton.icon(
              onPressed: locating ? null : useCurrentLocation,
              icon: locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
              label: Text(locating ? 'Localisation en cours…' : 'Utiliser ma position actuelle'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await Navigator.of(context).push<DestinationPoint>(
                  MaterialPageRoute(builder: (_) => DestinationMapPicker(
                    initialLat: deliveryLat,
                    initialLng: deliveryLng,
                  )),
                );
                if (selected == null || !mounted) return;
                setState(() {
                  deliveryLat = selected.lat;
                  deliveryLng = selected.lng;
                  deliveryAccuracyM = null;
                  address.text = address.text.trim().isEmpty
                      ? 'Point GPS choisi sur la carte (${selected.lat.toStringAsFixed(6)}, ${selected.lng.toStringAsFixed(6)})'
                      : '${address.text.trim()} — point GPS (${selected.lat.toStringAsFixed(6)}, ${selected.lng.toStringAsFixed(6)})';
                  coordinateAddressSnapshot = address.text;
                });
                toast(context, 'Point exact choisi. Ajoutez un repère clair pour aider le livreur à vous trouver.');
              },
              icon: const Icon(Icons.map_outlined),
              label: const Text('Choisir le point exact sur la carte'),
            ),
            if (deliveryLat != null && deliveryLng != null) ...[
              const SizedBox(height: 6),
              Text('Destination sélectionnée : ${deliveryLat!.toStringAsFixed(6)}, ${deliveryLng!.toStringAsFixed(6)}', style: const TextStyle(color: C.green, fontWeight: FontWeight.w700)),
              Text('Précision GPS estimée : ${deliveryAccuracyM?.round() ?? 'point sélectionné sur la carte'}', style: const TextStyle(color: C.muted)),
            ],
            TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddressesScreen()));
                setState(() => addrs = Repo.myAddresses());
              },
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Gérer mes adresses'),
            ),
          ],
          Field(coupon, 'Code promo (facultatif)'),
          const SizedBox(height: 8),
          Text('Articles : ${money(total, lines.isEmpty ? 'HTG' : lines.first.currency)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Text('Frais de livraison, commission et total final : calculés par le serveur.', style: TextStyle(color: C.muted)),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Enregistrement…' : 'Réserver et commander')),
          const SizedBox(height: 10),
          const Text('Après la réservation, vous pourrez payer chaque commande depuis « Mes commandes », avec le portefeuille HTG ou USD correspondant exactement à la devise affichée. Aucun change automatique ne sera appliqué.', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

class DestinationPoint {
  final double lat;
  final double lng;
  const DestinationPoint(this.lat, this.lng);
}

/// Carte de sélection de destination. L'utilisateur place le repère en touchant la carte.
/// Ce choix est une coordonnée réelle saisie par l'utilisateur, jamais une position simulée.
class DestinationMapPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  const DestinationMapPicker({super.key, this.initialLat, this.initialLng});

  @override
  State<DestinationMapPicker> createState() => _DestinationMapPickerState();
}

class _DestinationMapPickerState extends State<DestinationMapPicker> {
  static const LatLng haitiCenter = LatLng(18.9712, -72.2852);
  late LatLng selected = widget.initialLat != null && widget.initialLng != null
      ? LatLng(widget.initialLat!, widget.initialLng!)
      : haitiCenter;
  bool touched = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Choisir la destination')),
        body: Column(children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Touchez la carte à l’endroit exact où le colis doit être remis : domicile, école, université, travail, chez un proche ou autre lieu.', style: TextStyle(height: 1.4)),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: selected,
                initialZoom: widget.initialLat != null ? 16 : 8,
                onTap: (_, point) => setState(() { selected = point; touched = true; }),
              ),
              children: [
                TileLayer(
                  urlTemplate: const String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                  userAgentPackageName: 'com.haitiket.app',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: selected,
                    width: 54,
                    height: 58,
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.location_pin, size: 42, color: C.terracotta),
                      Text('Livraison', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, backgroundColor: Colors.white)),
                    ]),
                  ),
                ]),
                RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Latitude : ${selected.latitude.toStringAsFixed(6)}  ·  Longitude : ${selected.longitude.toStringAsFixed(6)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(DestinationPoint(selected.latitude, selected.longitude)),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(touched || (widget.initialLat != null && widget.initialLng != null) ? 'Confirmer ce point' : 'Utiliser le centre affiché'),
                ),
              ]),
            ),
          ),
        ]),
      );
}

/// Frise d'avancement d'une commande payée : Payée, Préparation, Prête, En route, Livrée (ou Retirée).
class OrderProgress extends StatelessWidget {
  final String status;
  final bool delivery;
  const OrderProgress({super.key, required this.status, required this.delivery});

  @override
  Widget build(BuildContext context) {
    final steps = delivery ? const ['Payée', 'Préparation', 'Prête', 'En route', 'Livrée'] : const ['Payée', 'Préparation', 'Prête', 'Retirée'];
    final last = steps.length - 1;
    final idx = switch (status) {
      'PAID' => 0,
      'CONFIRMED' || 'PREPARING' => 1,
      'READY_FOR_PICKUP' => 2,
      'IN_TRANSIT' => delivery ? 3 : 2,
      'DELIVERED' || 'COMPLETED' => last,
      _ => -1,
    };
    if (idx < 0) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(children: [
              Row(children: [
                Expanded(child: Container(height: 3, color: i == 0 ? Colors.transparent : (i <= idx ? C.green : C.line))),
                CircleAvatar(radius: 11, backgroundColor: i <= idx ? C.green : C.line, child: Icon(i <= idx ? Icons.check : Icons.circle, size: i <= idx ? 14 : 6, color: Colors.white)),
                Expanded(child: Container(height: 3, color: i == last ? Colors.transparent : (i < idx ? C.green : C.line))),
              ]),
              const SizedBox(height: 4),
              Text(steps[i], textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500, color: i <= idx ? C.ink : C.muted)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersState();
}

class _OrdersState extends State<OrdersScreen> with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> f = Repo.myOrders();
  final Set<String> payingOrders = <String>{};
  void reload() => setState(() => f = Repo.myOrders());

  Future<void> checkPending() async {
    // Les commandes internes ne sont plus vérifiées auprès d'un prestataire externe.
    if (mounted) reload();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (currentUser() != null) checkPending();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && currentUser() != null) checkPending();
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        MascotHeader(mascot: Mascot.orders, title: tr('Mes commandes'), subtitle: 'Suivez chaque étape, de la préparation à la livraison.'),
        if (currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour voir vos commandes.')
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: f,
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) return ErrorState(s.error);
              final items = s.data ?? [];
              if (items.isEmpty) return const EmptyState(title: 'Aucune commande', text: 'Vos commandes apparaîtront ici.');
              return Column(children: [
                for (final o in items)
                  Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${(o['shops'] as Map?)?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: C.ink)),
                        Text(statusFr(o['status'] as String), style: const TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
                        OrderProgress(status: '${o['status']}', delivery: '${o['delivery_mode']}' == 'delivery'),
                        if (o['status'] == 'CANCELLED' || o['status'] == 'REFUNDED')
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                try {
                                  await Repo.hideOrder('${o['id']}');
                                  reload();
                                } catch (e) {
                                  if (context.mounted) toast(context, Repo.err(e));
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Retirer de ma liste'),
                            ),
                          ),
                        const SizedBox(height: 6),
                        for (final it in (o['order_items'] as List)) Text('${it['qty']} × ${it['name']}${it['variant_label'] == null ? '' : ' (${it['variant_label']})'}'),
                        const SizedBox(height: 6),
                        Text('Total : ${money(o['total_minor'] as num, o['currency'] as String)}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.green)),
                        if (o['status'] == 'PENDING_PAYMENT') ...[
                          const SizedBox(height: 6),
                          PrimaryButton(
                            label: payingOrders.contains(o['id'])
                                ? 'Paiement en cours…'
                                : 'Payer avec mon portefeuille ${o['currency']}',
                            icon: Icons.account_balance_wallet_outlined,
                            onPressed: payingOrders.contains(o['id']) ? null : () async {
                              final orderId = o['id'] as String;
                              setState(() => payingOrders.add(orderId));
                              try {
                                final result = await Repo.payOrderFromWallet(orderId);
                                if (!mounted) return;
                                toast(context, result['already_paid'] == true ? 'Cette commande est déjà payée.' : 'Paiement confirmé par HAITIKET.');
                                reload();
                              } catch (e) {
                                if (mounted) toast(context, Repo.err(e));
                              } finally {
                                if (mounted) setState(() => payingOrders.remove(orderId));
                              }
                            },
                          ),
                          const Text('Le paiement est vérifié côté serveur. Le solde utilisé doit être dans la même devise que la commande.'),
                        ],
                        if (o['status'] != 'PENDING_PAYMENT' && o['status'] != 'CANCELLED') TextButton(onPressed: () => showPin(context, o['id'] as String, 'Code de remise'), child: const Text('Mon code de remise')),
                        if (o['status'] == 'READY_FOR_PICKUP' || o['status'] == 'IN_TRANSIT')
                          const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('Donnez votre code seulement après avoir reçu votre colis : c\'est lui qui libère le paiement du vendeur et du livreur.', style: TextStyle(color: C.muted, fontSize: 12.5))),
                        if (const ['PAID', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'IN_TRANSIT', 'DELIVERED', 'COMPLETED'].contains(o['status']))
                          TextButton.icon(
                            icon: const Icon(Icons.location_on_outlined),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => OrderTrackingScreen(orderId: o['id'] as String, shopName: ((o['shops'] as Map?)?['name'] ?? 'Boutique').toString()),
                            )),
                            label: const Text('Suivre la livraison'),
                          ),
                        if (o['status'] == 'DELIVERED' || o['status'] == 'COMPLETED') TextButton(onPressed: () => reviewDialog(context, o['id'] as String), child: const Text('Laisser un avis')),
                        if (o['status'] == 'PAID')
                          TextButton(
                            onPressed: () async {
                              try {
                                await Repo.requestCancellation(o['id'] as String);
                                reload();
                                if (context.mounted) toast(context, 'Commande annulée. Le remboursement est en cours de traitement.');
                              } catch (e) {
                                if (context.mounted) toast(context, Repo.err(e));
                              }
                            },
                            child: const Text('Annuler (remboursement)'),
                          ),
                        if (const ['PAID', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'IN_TRANSIT', 'DELIVERED'].contains(o['status']))
                          TextButton(
                            onPressed: () async {
                              await disputeDialog(context, o['id'] as String);
                              reload();
                            },
                            child: const Text('Signaler un problème'),
                          ),
                        TextButton(onPressed: () => openChat(context, 'order', o['id'] as String), child: const Text('Écrire au vendeur')),
                        if (o['status'] == 'PENDING_PAYMENT')
                          TextButton(
                            onPressed: () async {
                              try {
                                await Repo.cancelOrder(o['id'] as String);
                                reload();
                              } catch (e) {
                                if (context.mounted) toast(context, Repo.err(e));
                              }
                            },
                            child: const Text('Annuler la commande'),
                          ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
      ]);
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        MascotHeader(mascot: Mascot.seller, title: tr('Espace vendeur'), subtitle: 'Boutique, produits, commandes et stock au même endroit.'),
        if (!Config.configured || currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour gérer votre boutique.')
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Repo.myShops(),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              final shops = s.data ?? [];
              if (shops.isEmpty) return const EmptyState(title: "Aucune boutique", text: "Demandez l'ouverture d'une boutique depuis « Vendre ».");
              return Column(children: [for (final sh in shops) ShopPanel(sh, key: ValueKey(sh['id']))]);
            },
          ),
      ]);
}

class ShopPanel extends StatefulWidget {
  final Map<String, dynamic> shop;
  const ShopPanel(this.shop, {super.key});
  @override
  State<ShopPanel> createState() => _ShopPanelState();
}

class _ShopPanelState extends State<ShopPanel> {
  final name = TextEditingController(), price = TextEditingController(), stock = TextEditingController(), desc = TextEditingController();
  String? prodImg;
  String? catId;
  int imgKey = 0;
  late final Future<List<Map<String, dynamic>>> cats = Repo.categories();
  bool get personal => widget.shop['kind'] == 'personal';
  bool get official => widget.shop['is_official'] == true;

  bool paidOk(Map<String, dynamic> p) {
    final pu = p['paid_until'] as String?;
    return pu != null && DateTime.parse(pu).isAfter(DateTime.now());
  }

  String sub(Map<String, dynamic> p) {
    final base = '${money(p['price_minor'] as num, p['currency'] as String)} · stock ${p['stock']} · ${p['status'] == 'published' ? 'publié' : 'masqué'}';
    if (p['source'] != 'bazar') return base;
    return paidOk(p) ? '$base · payé jusqu\'au ${(p['paid_until'] as String).substring(0, 10)}' : '$base · non payé';
  }

  late Future<List<Map<String, dynamic>>> products = Repo.shopProducts(widget.shop['id'] as String);
  late Future<List<Map<String, dynamic>>> orders = Repo.shopOrders(widget.shop['id'] as String);

  void reload() => setState(() {
        products = Repo.shopProducts(widget.shop['id'] as String);
        orders = Repo.shopOrders(widget.shop['id'] as String);
      });

  Future<void> add() async {
    final p = double.tryParse(price.text.replaceAll(',', '.'));
    final st = int.tryParse(stock.text);
    if (name.text.trim().isEmpty || p == null || p < 0 || st == null || st < 0) return toast(context, 'Nom, prix et stock valides requis.');
    try {
      await Repo.addProduct(widget.shop['id'] as String, name.text.trim(), (p * 100).round(), st, prodImg, !personal, description: desc.text, categoryId: catId, source: personal ? 'bazar' : 'marketplace');
      name.clear();
      price.clear();
      stock.clear();
      desc.clear();
      prodImg = null;
      imgKey++;
      reload();
      if (mounted) toast(context, personal ? 'Annonce enregistrée : payez pour la publier.' : 'Produit publié.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> configureWholesale(Map<String, dynamic> p) async {
    final enabled = p['wholesale_enabled'] == true;
    final priceCtl = TextEditingController(text: p['wholesale_price_minor'] == null ? '' : (((p['wholesale_price_minor'] as num).toInt()) / 100).toStringAsFixed(2));
    final minCtl = TextEditingController(text: '${p['wholesale_min_qty'] ?? 2}');
    var turnOn = enabled;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: const Text('Offre de gros'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(value: turnOn, onChanged: (v) => setD(() => turnOn = v), title: const Text('Proposer ce produit aux revendeurs')),
        TextField(controller: priceCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Prix de gros par unité (${p['currency'] ?? 'HTG'})')),
        TextField(controller: minCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantité minimale (au moins 2)')),
        const SizedBox(height: 8),
        const Text('Une demande ne débite aucun portefeuille. L’acceptation réserve le stock; la validation de remise décompte le stock. Le paiement reste séparé.', style: TextStyle(fontSize: 12)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer'))],
    )));
    if (ok != true || !mounted) return;
    final amount = double.tryParse(priceCtl.text.replaceAll(',', '.'));
    final minQty = int.tryParse(minCtl.text);
    if (turnOn && (amount == null || amount <= 0 || minQty == null || minQty < 2)) { toast(context, 'Saisis un prix positif et une quantité minimale valide.'); return; }
    try {
      await Repo.setWholesaleOffer(p['id'] as String, enabled: turnOn, priceMinor: turnOn ? (amount! * 100).round() : 0, minQty: minQty ?? 2);
      reload();
      if (mounted) toast(context, turnOn ? 'Offre de gros enregistrée.' : 'Offre de gros désactivée.');
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  Future<void> editProduct(Map<String, dynamic> p) async {
    final n = TextEditingController(text: '${p['name'] ?? ''}');
    final price = TextEditingController(text: (((p['price_minor'] as num?) ?? 0) / 100).toStringAsFixed(2));
    final stock = TextEditingController(text: '${p['stock'] ?? 0}');
    final desc = TextEditingController(text: '${p['description'] ?? ''}');
    final unit = TextEditingController(text: '${p['unit_label'] ?? 'unité'}');
    final specs = <String, dynamic>{...(p['attributes'] is Map ? Map<String, dynamic>.from(p['attributes'] as Map) : <String, dynamic>{})};
    String currency = (p['currency'] as String?) ?? 'HTG';
    final variantsCtl = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(await Repo.productVariants(p['id'] as String)));
    final tiersCtl = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(await Repo.productTiers(p['id'] as String)));
    final statusOptions = ['published', 'paused', 'draft'];
    String productStatus = statusOptions.contains(p['status']) ? p['status'] as String : 'published';
    String? editCategory = p['category_id'] as String?;
    final categories = await Repo.categories();
    final audienceOptions = ['Homme', 'Femme', 'Enfant', 'Adolescent', 'Unisexe'];
    final initialAudiences = (p['audiences'] as List?)?.map((x) => '$x').toSet() ?? <String>{};
    if (initialAudiences.isEmpty && p['audience'] != null) initialAudiences.add('${p['audience']}');
    final selectedAudiences = <String>{...initialAudiences.where(audienceOptions.contains)};
    List<Map<String, String>> media = [];
    try {
      final existing = await Repo.productMedia(p['id'] as String);
      media = existing.map((m) => {'url': '${m['url']}', 'kind': '${m['kind'] ?? 'image'}'}).toList();
      if (media.isEmpty && (p['image_url'] as String?)?.isNotEmpty == true) {
        media = [{'url': p['image_url'] as String, 'kind': 'image'}];
      }
    } catch (_) {
      if ((p['image_url'] as String?)?.isNotEmpty == true) {
        media = [{'url': p['image_url'] as String, 'kind': 'image'}];
      }
    }
    final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (d) => StatefulBuilder(
      builder: (d, setDialogState) => AlertDialog(
        title: const Text('Modifier complètement le produit'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Photos et vidéos', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            MediaPickerField(items: media, onChanged: () => setDialogState(() {})),
            const SizedBox(height: 14),
            TextField(controller: n, decoration: const InputDecoration(labelText: 'Nom du produit')),
            TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Prix (HTG)')),
            TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock total')),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unité de vente (ex. unité, paire, lot, kg)')),
            const Padding(padding: EdgeInsets.only(top: 10, bottom: 4), child: Text('Publics concernés (plusieurs choix possibles)', style: TextStyle(fontWeight: FontWeight.w800))),
            Wrap(spacing: 6, runSpacing: 2, children: [
              for (final a in audienceOptions)
                FilterChip(label: Text(a), selected: selectedAudiences.contains(a), onSelected: (yes) => setDialogState(() { if (yes) { selectedAudiences.add(a); } else { selectedAudiences.remove(a); } })),
            ]),
            TextButton(onPressed: () => setDialogState(() => selectedAudiences.clear()), child: const Text('Effacer les publics ciblés (tout public)')),
            TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
            DropdownButtonFormField<String?>(value: editCategory, decoration: const InputDecoration(labelText: 'Catégorie'), items: [const DropdownMenuItem<String?>(value: null, child: Text('Aucune catégorie')), for (final c in categories) DropdownMenuItem<String?>(value: c['id'] as String, child: Text('${c['name']}'))], onChanged: (v) { setDialogState(() => editCategory = v); }),
            DropdownButtonFormField<String>(value: currency, decoration: const InputDecoration(labelText: 'Devise du prix'), items: const [DropdownMenuItem(value: 'HTG', child: Text('Gourdes (HTG)')), DropdownMenuItem(value: 'USD', child: Text('Dollars (USD)'))], onChanged: (v) { if (v != null) setDialogState(() => currency = v); }),
            OutlinedButton.icon(
              icon: const Icon(Icons.tune),
              label: Text('Modifier visuellement les variantes (${_jsonListCount(variantsCtl.text)})'),
              onPressed: () async {
                try {
                  final raw = jsonDecode(variantsCtl.text.isEmpty ? '[]' : variantsCtl.text);
                  if (raw is! List || raw.any((x) => x is! Map)) throw const FormatException();
                  final result = await editProductVariantsDialog(context, raw.map((x) => Map<String, dynamic>.from(x as Map)).toList());
                  if (result != null) setDialogState(() => variantsCtl.text = const JsonEncoder.withIndent('  ').convert(result));
                } catch (_) { toast(context, 'Impossible de lire les variantes actuelles.'); }
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.price_change_outlined),
              label: Text('Modifier les tarifs par quantité (${_jsonListCount(tiersCtl.text)})'),
              onPressed: () async {
                try {
                  final raw = jsonDecode(tiersCtl.text.isEmpty ? '[]' : tiersCtl.text);
                  if (raw is! List || raw.any((x) => x is! Map)) throw const FormatException();
                  final result = await editProductTiersDialog(context, raw.map((x) => Map<String, dynamic>.from(x as Map)).toList());
                  if (result != null) setDialogState(() => tiersCtl.text = const JsonEncoder.withIndent('  ').convert(result));
                } catch (_) { toast(context, 'Impossible de lire les tarifs actuels.'); }
              },
            ),
            DropdownButtonFormField<String>(value: productStatus, decoration: const InputDecoration(labelText: 'Visibilité du produit'), items: [for (final st in statusOptions) DropdownMenuItem(value: st, child: Text({'published':'Publié','paused':'Masqué / en pause','draft':'Brouillon'}[st]!))], onChanged: (v) { if (v != null) setDialogState(() => productStatus = v); }),
            const Padding(padding: EdgeInsets.only(top: 14), child: Text('Caractéristiques du produit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            if (editCategory != null)
              SpecsForm(key: ValueKey('specs-$editCategory'), fields: specsFor(categories.where((c) => c['id'] == editCategory).map((c) => '${c['name']}').firstOrNull), values: specs)
            else
              const Padding(padding: EdgeInsets.only(top: 6), child: Text('Choisissez une catégorie ci-dessus pour afficher ses champs (tailles, couleurs, marque, état, garantie…).', style: TextStyle(color: C.muted))),
            const SizedBox(height: 8),
            const Text('Retire un média avec ✕. Le premier média image disponible devient la photo de couverture.', style: TextStyle(fontSize: 12, color: C.muted)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer toutes les modifications')),
        ],
      ),
    ));
    if (ok != true) return;
    final v = double.tryParse(price.text.replaceAll(',', '.'));
    final q = int.tryParse(stock.text);
    if (n.text.trim().length < 2 || v == null || v < 0 || q == null || q < 0 || unit.text.trim().isEmpty) {
      return toast(context, 'Vérifie le nom, le prix, le stock et l’unité.');
    }
    try {
      final attrsOut = Map<String, dynamic>.from(specs);
      final extraColors = (attrsOut.remove('_colors_extra') ?? '').toString();
      final colorList = List<Map<String, dynamic>>.from(((attrsOut['colors'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      for (final nm in extraColors.split(',')) {
        final t = nm.trim();
        if (t.isNotEmpty && !colorList.any((c) => '${c['name']}'.toLowerCase() == t.toLowerCase())) colorList.add({'name': t, 'hex': null});
      }
      if (colorList.isNotEmpty) attrsOut['colors'] = colorList;
      attrsOut.removeWhere((k, v) => v == null || (v is List && v.isEmpty) || (v is String && v.isEmpty));
      await Repo.updateProduct(p['id'] as String, {
        'name': n.text.trim(),
        'price_minor': (v * 100).round(),
        'stock': q,
        'description': desc.text.trim(),
        'unit_label': unit.text.trim(),
        'audiences': selectedAudiences.toList()..sort(),
        'audience': selectedAudiences.length == 1 ? selectedAudiences.first : null,
        'category_id': editCategory,
        'status': productStatus,
        'attributes': attrsOut,
        'currency': currency,
      });
      final variantsJson = jsonDecode(variantsCtl.text.isEmpty ? '[]' : variantsCtl.text);
      final tiersJson = jsonDecode(tiersCtl.text.isEmpty ? '[]' : tiersCtl.text);
      if (variantsJson is! List || variantsJson.any((x) => x is! Map)) throw const FormatException('Les variantes doivent être un tableau JSON d’objets.');
      if (tiersJson is! List || tiersJson.any((x) => x is! Map)) throw const FormatException('Les tarifs doivent être un tableau JSON d’objets.');
      await Repo.replaceProductVariants(p['id'] as String, variantsJson.map((x) => Map<String, dynamic>.from(x as Map)).toList());
      await Repo.replaceProductTiers(p['id'] as String, tiersJson.map((x) => Map<String, dynamic>.from(x as Map)).toList());
      await Repo.replaceProductMedia(p['id'] as String, media);
      reload();
      if (mounted) toast(context, 'Produit, photos et vidéos mis à jour.');
    } catch (e) {
      if (mounted) toast(context, 'Enregistrement incomplet ou refusé : ${Repo.err(e)}');
    }
  }

  Future<void> removeProduct(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Supprimer ce produit ?'),
      content: Text('« ${p['name']} » sera retiré du catalogue. Les commandes déjà passées conserveront leur historique.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer'))],
    ));
    if (ok != true) return;
    try { await Repo.deleteProduct(p['id'] as String); reload(); if (mounted) toast(context, 'Produit retiré du catalogue.'); }
    catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  Future<void> resumeShopNow() async {
    final id = widget.shop['id'] as String;
    try {
      if (widget.shop['deletion_review_status'] == 'rejected') {
        await Repo.reactivateShopAfterDeletionRejection(id);
      } else {
        await Repo.resumeShop(id);
      }
      if (!mounted) return;
      setState(() { widget.shop['status'] = 'active'; widget.shop['deletion_review_status'] = 'none'; });
      toast(context, 'Boutique réactivée.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> manageShop(String action) async {
    final currentName = '${widget.shop['name'] ?? ''}';
    final ctl = TextEditingController(text: currentName);
    if (action == 'rename') {
      final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
        title: const Text('Modifier le nom de la boutique'),
        content: TextField(controller: ctl, maxLength: 80, decoration: const InputDecoration(labelText: 'Nom public', helperText: 'Le nom doit être disponible et comporte 2 à 80 caractères.')),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Vérifier et enregistrer'))],
      ));
      if (ok != true) return;
      if (ctl.text.trim().length < 2) return toast(context, 'Le nom doit contenir au moins 2 caractères.');
    } else {
      final close = action == 'close';
      final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
        title: Text(close ? 'Demander la suppression de la boutique ?' : 'Suspendre la boutique ?'),
        content: Text(close ? 'La boutique sera suspendue immédiatement, les commandes non terminées seront traitées et les remboursements nécessaires mis en file. La suppression définitive exige une validation administrative et un délai minimal de 30 jours. L’historique sera conservé.' : 'La boutique sera suspendue immédiatement. Les commandes non terminées seront annulées ou mises en traitement de remboursement. Contactez le support pour demander sa réactivation.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(close ? 'Envoyer la demande' : 'Suspendre'))],
      ));
      if (ok != true) return;
    }
    try {
      final result = await Repo.manageOwnShop(widget.shop['id'] as String, action: action, name: ctl.text.trim());
      if (!mounted) return;
      setState(() { widget.shop['name'] = result['name']; widget.shop['status'] = result['status']; });
      toast(context, action == 'rename' ? 'Nom de boutique mis à jour.' : action == 'close' ? 'Demande envoyée : délai de 30 jours et validation administrative requis.' : 'Boutique suspendue; remboursements éventuels mis en file.');
    } catch (e) { if (mounted) toast(context, 'Opération refusée : ${Repo.err(e)}'); }
  }

  Future<void> orderAction(Map<String, dynamic> o, String v) async {
    final id = o['id'] as String;
    try {
      if (v == 'chat') return openChat(context, 'order', id);
      if (v == 'pin') return showPin(context, id, 'Code de collecte');
      if (v == 'hide') {
        await Repo.hideOrder(id);
        if (mounted) toast(context, 'Commande retirée de votre liste (l\'historique reste conservé).');
        reload();
        return;
      }
      if (v == 'dispute') {
        await disputeDialog(context, id);
        reload();
        return;
      }
      if (v == 'handover') {
        final pin = await askText(context, 'Code donné par le client', type: TextInputType.number);
        if (pin == null || pin.isEmpty) return;
        final ok = await Repo.confirmHandover(id, pin);
        if (mounted) toast(context, ok ? 'Remise confirmée.' : 'Code incorrect.');
        reload();
        return;
      }
      await Repo.sellerSetOrderStatus(id, v);
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> patch(String id, Map<String, dynamic> d) async {
    try {
      await Repo.updateProduct(id, d);
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Widget _officialShopDashboard() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: products,
      builder: (context, productSnapshot) {
        final productRows = productSnapshot.data ?? const <Map<String, dynamic>>[];
        final published = productRows.where((p) => p['status'] == 'published').length;
        final lowStock = productRows.where((p) => p['status'] == 'published' && ((p['stock'] as num?)?.toInt() ?? 0) <= 3).toList();
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: orders,
          builder: (context, orderSnapshot) {
            final orderRows = orderSnapshot.data ?? const <Map<String, dynamic>>[];
            final statusCounts = <String, int>{};
            final totals = <String, int>{'HTG': 0, 'USD': 0};
            for (final order in orderRows) {
              final status = '${order['status'] ?? 'UNKNOWN'}';
              statusCounts[status] = (statusCounts[status] ?? 0) + 1;
              final currency = '${order['currency'] ?? ''}';
              if (totals.containsKey(currency)) {
                totals[currency] = totals[currency]! + ((order['total_minor'] as num?)?.toInt() ?? 0);
              }
            }
            Widget metric(String label, String value, IconData icon) => Container(
              constraints: const BoxConstraints(minWidth: 135),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 20, color: C.green),
                const SizedBox(width: 8),
                Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.ink)),
                  Text(label, style: const TextStyle(fontSize: 11, color: C.muted)),
                ])),
              ]),
            );
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(official ? 'Vue d’ensemble — boutique officielle' : 'Vue d’ensemble — boutique professionnelle', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.ink)),
                const SizedBox(height: 4),
                const Text('Les commandes affichées sont les 50 plus récentes au maximum. Les montants sont séparés par devise et ne représentent pas un relevé comptable.', style: TextStyle(fontSize: 12, color: C.muted)),
                const SizedBox(height: 12),
                if (productSnapshot.connectionState != ConnectionState.done || orderSnapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator(),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  metric('Produits au catalogue', '${productRows.length}', Icons.inventory_2_outlined),
                  metric('Produits publiés', '$published', Icons.storefront_outlined),
                  metric('Stock faible (≤ 3)', '${lowStock.length}', Icons.warning_amber_outlined),
                  metric('Commandes chargées', '${orderRows.length}', Icons.receipt_long_outlined),
                ]),
                const SizedBox(height: 12),
                const Text('Volume des commandes chargées par devise', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  metric('Total HTG', money(totals['HTG']!, 'HTG'), Icons.payments_outlined),
                  metric('Total USD', money(totals['USD']!, 'USD'), Icons.attach_money),
                ]),
                if (statusCounts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('État des commandes', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final entry in statusCounts.entries)
                      Chip(label: Text('${statusFr(entry.key)} : ${entry.value}')),
                  ]),
                ],
                if (lowStock.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('À réapprovisionner', style: TextStyle(fontWeight: FontWeight.w700, color: C.terracotta)),
                  for (final product in lowStock.take(5))
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('• ${product['name']} — stock ${product['stock']}', style: const TextStyle(fontSize: 13))),
                  if (lowStock.length > 5) Text('Et ${lowStock.length - 5} autre(s) produit(s).', style: const TextStyle(fontSize: 12, color: C.muted)),
                ],
              ]),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.shop['status'] == 'active';
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Flexible(child: Text('${widget.shop['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink))), if (widget.shop['verified_at'] != null) const Padding(padding: EdgeInsets.only(left: 8), child: Chip(avatar: Icon(Icons.verified, size: 16, color: Colors.blue), label: Text('Boutique vérifiée'), visualDensity: VisualDensity.compact))]),
          Text(
            {'active': 'Boutique active', 'pending': 'En attente de vérification', 'draft': 'Brouillon', 'suspended': widget.shop['deletion_review_status'] == 'pending_admin' || widget.shop['deletion_review_status'] == 'approved' ? 'Suppression demandée : en examen par l’administration (délai minimal de 30 jours). Votre boutique reste suspendue.' : 'Boutique suspendue.', 'closed': 'Boutique fermée définitivement'}[widget.shop['status']] ?? 'Statut : ${widget.shop['status']}',
            style: TextStyle(color: active ? C.green : C.terracotta, fontWeight: FontWeight.w700),
          ),
          if (!official && widget.shop['status'] != 'closed') Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(onPressed: () => manageShop('rename'), icon: const Icon(Icons.edit_outlined), label: const Text('Modifier le nom')),
            if (widget.shop['status'] == 'active') OutlinedButton.icon(onPressed: () => manageShop('suspend'), icon: const Icon(Icons.pause_circle_outline), label: const Text('Suspendre')),
            if (widget.shop['status'] != 'closed') TextButton.icon(onPressed: () => manageShop('close'), icon: const Icon(Icons.store_mall_directory_outlined), label: const Text('Fermer définitivement')),
          ]),
          if (!official && widget.shop['status'] == 'suspended' && widget.shop['deletion_review_status'] != 'pending_admin' && widget.shop['deletion_review_status'] != 'approved')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 8, children: [
                FilledButton.icon(onPressed: resumeShopNow, icon: const Icon(Icons.play_circle_outline), label: const Text('Réactiver ma boutique')),
                const Text('Si la suspension vient de l’administration, contactez le support.', style: TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
          if (widget.shop['status'] == 'closed') const Text('Boutique fermée définitivement — historique conservé.', style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
          if (!personal && !official && widget.shop['status'] == 'active' && widget.shop['deletion_review_status'] != 'pending_admin' && widget.shop['deletion_review_status'] != 'approved') PlanCard(shop: widget.shop),
          if (official) const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.verified, color: C.green), title: Text('Boutique officielle HAITIKET', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Abonnement vendeur non requis.')),
          if (!personal && active) BrandingEditor(shop: widget.shop),
          if (active)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final pos = await myPosition(context);
                  if (pos == null) return;
                  try {
                    await Repo.setShopLocation(widget.shop['id'] as String, pos.latitude, pos.longitude);
                    if (mounted) toast(context, 'Position de la boutique enregistrée (arrondie à ~100 m).');
                  } catch (e) {
                    if (mounted) toast(context, Repo.err(e));
                  }
                },
                icon: const Icon(Icons.my_location),
                label: const Text('Partager la position de ma boutique'),
              ),
            ),
          if (active) ...[
            const SizedBox(height: 16),
            PrimaryButton(
              label: personal ? 'Nouvelle annonce' : 'Nouveau produit',
              icon: Icons.add_box_outlined,
              onPressed: () async {
                final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NewProductScreen(shopId: widget.shop['id'] as String, bazar: personal)));
                if (id != null) {
                  reload();
                  if (personal && mounted) toast(context, 'Annonce enregistrée : payez pour la publier.');
                }
              },
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopCouponsScreen(shopId: widget.shop['id'] as String))),
              icon: const Icon(Icons.local_offer_outlined),
              label: const Text('Promotions et coupons'),
            ),
            if (!personal && !official) OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WholesaleCenterScreen())),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Fournisseurs et achats en gros'),
            ),
            const SizedBox(height: 16),
            if (official) _officialShopDashboard(),
            if (!personal && !official) _officialShopDashboard(),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: products,
              builder: (_, s) {
                final items = s.data ?? [];
                if (items.isEmpty) return const Text('Aucun produit.', style: TextStyle(color: C.muted));
                return Column(children: [
                  for (final p in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(sub(p)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (official)
                          IconButton(
                            tooltip: p['is_featured'] == true ? 'Retirer des produits mis en avant' : 'Mettre en avant dans la boutique',
                            onPressed: () async {
                              try {
                                await Repo.adminSetOfficialProductFeatured(p['id'] as String, p['is_featured'] != true);
                                reload();
                                if (mounted) toast(context, p['is_featured'] == true ? 'Produit retiré de la sélection mise en avant.' : 'Produit mis en avant dans le catalogue.');
                              } catch (e) {
                                if (mounted) toast(context, Repo.err(e));
                              }
                            },
                            icon: Icon(p['is_featured'] == true ? Icons.star : Icons.star_border, color: p['is_featured'] == true ? C.yellow : C.muted),
                          ),
                        if (!personal && !official) IconButton(
                          tooltip: p['wholesale_enabled'] == true ? 'Modifier l’offre de gros' : 'Proposer un prix de gros',
                          onPressed: () => configureWholesale(p),
                          icon: Icon(Icons.inventory_2_outlined, color: p['wholesale_enabled'] == true ? C.green : C.muted),
                        ),
                        IconButton(
                          tooltip: 'Modifier les informations principales',
                          onPressed: () => editProduct(p),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Supprimer du catalogue',
                          onPressed: () => removeProduct(p),
                          icon: const Icon(Icons.delete_outline, color: C.terracotta),
                        ),
                        if (((p['product_variants'] as List?) ?? const []).isNotEmpty)
                          IconButton(
                            tooltip: 'Stock par variante',
                            onPressed: () async {
                              await variantStockDialog(context, p);
                              reload();
                            },
                            icon: const Icon(Icons.inventory_2_outlined),
                          )
                        else ...[
                          IconButton(onPressed: (p['stock'] as int) > 0 ? () => patch(p['id'] as String, {'stock': (p['stock'] as int) - 1}) : null, icon: const Icon(Icons.remove_circle_outline)),
                          IconButton(onPressed: () => patch(p['id'] as String, {'stock': (p['stock'] as int) + 1}), icon: const Icon(Icons.add_circle_outline)),
                        ],
                        if (p['source'] == 'bazar' && !paidOk(p)) TextButton(onPressed: () async { await payBazarFromWallet(context, p['id'] as String); reload(); }, child: const Text('Payer avec portefeuille USD'))
                        else Switch(value: p['status'] == 'published', onChanged: (v) => patch(p['id'] as String, {'status': v ? 'published' : 'paused'})),
                      ]),
                    ),
                ]);
              },
            ),
          ],
          const SizedBox(height: 16),
          const Text('Commandes reçues', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink)),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: orders,
            builder: (_, s) {
              final items = s.data ?? [];
              if (items.isEmpty) return const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aucune commande payée pour le moment.', style: TextStyle(color: C.muted)));
              return Column(children: [
                if (items.any((o) => o['status'] == 'CANCELLED' || o['status'] == 'REFUNDED'))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        try {
                          final n = await Repo.hideCancelledOrders(widget.shop['id'] as String);
                          if (mounted) toast(context, '$n commande(s) annulée(s) retirée(s) de votre liste.');
                          reload();
                        } catch (e) {
                          if (mounted) toast(context, Repo.err(e));
                        }
                      },
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Nettoyer les commandes annulées'),
                    ),
                  ),
                for (final o in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                trailing: PopupMenuButton<String>(
                      onSelected: (v) => orderAction(o, v),
                      itemBuilder: (_) {
                        final st = o['status'];
                        final dm = o['delivery_mode'];
                        return [
                          const PopupMenuItem(value: 'chat', child: Text('Écrire au client')),
                          if (const ['CANCELLED', 'REFUNDED', 'COMPLETED'].contains(st)) const PopupMenuItem(value: 'hide', child: Text('Retirer de ma liste')),
                          if (st == 'PAID') const PopupMenuItem(value: 'CONFIRMED', child: Text('Confirmer la commande')),
                          if (st == 'CONFIRMED') const PopupMenuItem(value: 'PREPARING', child: Text('Passer en préparation')),
                          if (st == 'PREPARING') const PopupMenuItem(value: 'READY_FOR_PICKUP', child: Text('Marquer prête')),
                          if (dm == 'delivery' && (st == 'CONFIRMED' || st == 'PREPARING' || st == 'READY_FOR_PICKUP')) const PopupMenuItem(value: 'pin', child: Text('Code de collecte (livreur)')),
                          if (dm == 'pickup' && st == 'READY_FOR_PICKUP') const PopupMenuItem(value: 'handover', child: Text('Valider la remise (code client)')),
                          if (const ['PAID', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'IN_TRANSIT', 'DELIVERED'].contains(st)) const PopupMenuItem(value: 'dispute', child: Text('Ouvrir un litige')),
                        ];
                      },
                    ),
                    title: Text('${(o['order_items'] as List).map((i) => '${i['qty']}× ${i['name']}${i['variant_label'] == null ? '' : ' (${i['variant_label']})'}').join(', ')}'),
                    subtitle: Text('${statusFr(o['status'] as String)} · net vendeur ${money(o['seller_net_minor'] as num, o['currency'] as String)} (commission ${money(o['commission_minor'] as num, o['currency'] as String)})'),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}


class StockLedgerScreen extends StatefulWidget {
  const StockLedgerScreen({super.key});
  @override
  State<StockLedgerScreen> createState() => _StockLedgerScreenState();
}

class _StockLedgerScreenState extends State<StockLedgerScreen> {
  late Future<List<Map<String, dynamic>>> productsFuture = _loadProducts();
  late Future<List<Map<String, dynamic>>> movementsFuture = Repo.stockMovements();
  String? selectedProductId;

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    final shops = await Repo.myShops();
    final result = <Map<String, dynamic>>[];
    for (final shop in shops.where((s) => s['status'] == 'active' && s['kind'] != 'personal' && s['is_official'] != true)) {
      final products = await Repo.shopProducts(shop['id'] as String);
      for (final product in products) {
        if (product['status'] == 'removed') continue;
        result.add({...product, 'ledger_shop_name': shop['name']});
      }
    }
    return result;
  }

  void refresh() => setState(() {
    productsFuture = _loadProducts();
    movementsFuture = Repo.stockMovements();
  });

  Future<void> _adjust(Map<String, dynamic> product) async {
    final deltaCtl = TextEditingController();
    final reasonCtl = TextEditingController();
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Ajuster le stock — ${product['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Stock actuel : ${product['stock'] ?? 0}'),
        TextField(controller: deltaCtl, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: 'Variation (+ entrée / − sortie)', hintText: 'Ex. 12 ou -3')),
        TextField(controller: reasonCtl, maxLength: 240, decoration: const InputDecoration(labelText: 'Motif obligatoire', hintText: 'Ex. inventaire physique, casse, réception')),
        const SizedBox(height: 8),
        const Text('Le serveur refuse un stock négatif et inscrit chaque variation au journal.', style: TextStyle(fontSize: 12)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(ctx, {'delta': deltaCtl.text, 'reason': reasonCtl.text}), child: const Text('Enregistrer'))],
    ));
    if (result == null || !mounted) return;
    final delta = int.tryParse(result['delta'] ?? '');
    final reason = (result['reason'] ?? '').trim();
    if (delta == null || delta == 0 || reason.length < 3) { toast(context, 'Saisis une variation non nulle et un motif de 3 caractères minimum.'); return; }
    try {
      await Repo.adjustProductStock(product['id'] as String, delta, reason);
      refresh();
      if (mounted) toast(context, 'Stock ajusté et mouvement enregistré.');
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  Future<void> _adjustVariant(Map<String, dynamic> product, Map<String, dynamic> variant) async {
    final deltaCtl = TextEditingController();
    final reasonCtl = TextEditingController();
    final label = [variant['size'], variant['color_name']].where((v) => v != null && '$v'.trim().isNotEmpty).join(' · ');
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Ajuster la variante — ${label.isEmpty ? 'Variante' : label}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Produit : ${product['name']} · stock variante : ${variant['stock'] ?? 0}'),
        TextField(controller: deltaCtl, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: 'Variation (+ / −)', hintText: 'Ex. 5 ou -2')),
        TextField(controller: reasonCtl, maxLength: 240, decoration: const InputDecoration(labelText: 'Motif obligatoire', hintText: 'Réception, inventaire, casse…')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(ctx, {'delta': deltaCtl.text, 'reason': reasonCtl.text}), child: const Text('Enregistrer'))],
    ));
    if (result == null || !mounted) return;
    final delta = int.tryParse(result['delta'] ?? '');
    final reason = (result['reason'] ?? '').trim();
    if (delta == null || delta == 0 || reason.length < 3) { toast(context, 'Saisis une variation non nulle et un motif de 3 caractères minimum.'); return; }
    try {
      await Repo.adjustVariantStock(variant['id'] as String, delta, reason);
      refresh();
      if (mounted) toast(context, 'Stock de variante ajusté et tracé.');
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventaire et mouvements de stock')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Ajustements sécurisés', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const Text('Les quantités sont modifiées côté serveur. Chaque changement est conservé dans un journal consultable par le propriétaire de la boutique.'),
      FutureBuilder<List<Map<String, dynamic>>>(future: productsFuture, builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
        if (snap.hasError) return Text('Produits indisponibles : ${Repo.err(snap.error!)}');
        final products = snap.data ?? [];
        if (products.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aucun produit trouvé dans tes boutiques professionnelles actives.'));
        if (selectedProductId == null || !products.any((p) => p['id'] == selectedProductId)) selectedProductId = products.first['id'] as String;
        final selected = products.firstWhere((p) => p['id'] == selectedProductId);
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(value: selectedProductId, isExpanded: true, decoration: const InputDecoration(labelText: 'Produit'), items: [for (final p in products) DropdownMenuItem(value: p['id'] as String, child: Text('${p['name']} · ${p['ledger_shop_name']} · stock ${p['stock'] ?? 0}', overflow: TextOverflow.ellipsis))], onChanged: (v) => setState(() => selectedProductId = v)),
          const SizedBox(height: 8),
          Text('Stock actuel : ${selected['stock'] ?? 0}'),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: () => _adjust(selected), icon: const Icon(Icons.tune), label: const Text('Ajuster le stock global')),
          if (((selected['product_variants'] as List?) ?? const []).isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Variantes (taille / couleur)', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final rawVariant in (selected['product_variants'] as List))
              if (rawVariant is Map) Builder(builder: (context) {
                final v = Map<String, dynamic>.from(rawVariant);
                final variantLabel = [v['size'], v['color_name']].where((x) => x != null && '$x'.trim().isNotEmpty).join(' · ');
                return ListTile(contentPadding: EdgeInsets.zero, title: Text(variantLabel.isEmpty ? 'Variante' : variantLabel), subtitle: Text('Stock : ${v['stock'] ?? 0}'), trailing: IconButton(tooltip: 'Ajuster la variante', onPressed: () => _adjustVariant(selected, v), icon: const Icon(Icons.tune)));
              }),
          ],
        ])));
      }),
      const SizedBox(height: 20),
      const Text('Journal des mouvements', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const Text('Affiche les 200 mouvements les plus récents accessibles. Le journal est une trace de stock, pas une preuve de paiement.'),
      FutureBuilder<List<Map<String, dynamic>>>(future: movementsFuture, builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
        if (snap.hasError) return Text('Journal indisponible : ${Repo.err(snap.error!)}');
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('Aucun mouvement enregistré pour le moment.'));
        return Column(children: [for (final row in rows) Card(child: ListTile(
          leading: Icon((row['quantity_delta'] as num? ?? 0) >= 0 ? Icons.add_box_outlined : Icons.indeterminate_check_box_outlined),
          title: Text('${(row['quantity_delta'] as num? ?? 0) > 0 ? '+' : ''}${row['quantity_delta']} unités · ${row['movement_type'] == 'initial_stock' ? 'Stock initial' : row['movement_type'] == 'manual_adjustment' ? 'Ajustement manuel' : 'Variation de stock'}'),
          subtitle: Text('${row['reason'] ?? ''}\n${row['created_at'] ?? ''} · ${row['old_stock'] ?? '—'} → ${row['new_stock']}'),
          isThreeLine: true,
        ))]);
      }),
    ]),
  );
}

class WholesaleCenterScreen extends StatefulWidget {
  const WholesaleCenterScreen({super.key});
  @override
  State<WholesaleCenterScreen> createState() => _WholesaleCenterScreenState();
}

class _WholesaleCenterScreenState extends State<WholesaleCenterScreen> {
  final searchCtl = TextEditingController();
  late Future<List<Map<String, dynamic>>> shopsFuture = Repo.myShops();
  late Future<List<Map<String, dynamic>>> offersFuture = Repo.wholesaleOffers();
  late Future<List<Map<String, dynamic>>> requestsFuture = Repo.wholesaleRequests();
  late Future<List<Map<String, dynamic>>> eventsFuture = Repo.wholesaleRequestEvents();
  String? buyerShopId;
  int historyDays = 30;
  String historyType = 'all';
  void refresh() => setState(() { shopsFuture = Repo.myShops(); offersFuture = Repo.wholesaleOffers(query: searchCtl.text); requestsFuture = Repo.wholesaleRequests(); eventsFuture = Repo.wholesaleRequestEvents(); });

  Future<void> requestOffer(Map<String, dynamic> offer, String shopId) async {
    final qtyCtl = TextEditingController(text: '${offer['wholesale_min_qty'] ?? 2}');
    final noteCtl = TextEditingController();
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Demander ${offer['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Prix proposé : ${money(offer['wholesale_price_minor'] as num, offer['currency'] as String)} · minimum ${offer['wholesale_min_qty']}'),
        TextField(controller: qtyCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantité demandée')),
        TextField(controller: noteCtl, decoration: const InputDecoration(labelText: 'Note au fournisseur (facultatif)')),
        const SizedBox(height: 8),
        const Text('Cette action envoie une demande, sans paiement automatique. Le stock n’est réservé qu’après acceptation du fournisseur.', style: TextStyle(fontSize: 12)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(ctx, {'qty': qtyCtl.text, 'note': noteCtl.text}), child: const Text('Envoyer la demande'))],
    ));
    if (result == null || !mounted) return;
    final qty = int.tryParse(result['qty'] ?? '');
    if (qty == null || qty < 2) { toast(context, 'La quantité doit être au moins égale à 2.'); return; }
    try { await Repo.createWholesaleRequest(offer['id'] as String, shopId, qty, note: result['note']); refresh(); if (mounted) toast(context, 'Demande fournisseur envoyée. Aucun paiement n’a été effectué.'); }
    catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  Future<void> act(Map<String, dynamic> request, String action) async {
    try { await Repo.updateWholesaleRequest(request['id'] as String, action); refresh(); if (mounted) toast(context, 'Demande mise à jour.'); }
    catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  String _supplierCsvCell(Object? value) {
    var raw = '${value ?? ''}'.replaceAll('\r', ' ').replaceAll('\n', ' ');
    final trimmed = raw.trimLeft();
    if (trimmed.isNotEmpty && '=+-@'.contains(trimmed[0])) raw = "'$raw";
    return '\"${raw.replaceAll('\"', '\"\"')}\"';
  }

  List<Map<String, dynamic>> _filterSupplierEvents(List<Map<String, dynamic>> events) {
    final cutoff = DateTime.now().toUtc().subtract(Duration(days: historyDays));
    return events.where((event) {
      final at = DateTime.tryParse('${event['created_at'] ?? ''}')?.toUtc();
      final inPeriod = at != null && !at.isBefore(cutoff);
      final typeMatches = historyType == 'all' || event['event_type'] == historyType;
      return inPeriod && typeMatches;
    }).toList();
  }

  Future<void> _exportSupplierEvents(List<Map<String, dynamic>> events) async {
    final rows = <List<Object?>>[
      ['Rapport', 'Historique des achats fournisseurs HAITIKET'],
      ['Exporté le (UTC)', DateTime.now().toUtc().toIso8601String()],
      ['Période', 'Derniers $historyDays jours'],
      ['Type', historyType == 'all' ? 'Tous les événements' : historyType],
      ['Note', 'Historique visible pour les boutiques participantes; maximum 200 événements chargés. Les demandes ne prouvent pas un paiement.'],
      ['Date UTC', 'ID demande', 'Événement', 'Ancien statut', 'Nouveau statut', 'Acheteur (ID boutique)', 'Vendeur (ID boutique)', 'Quantité', 'Prix unitaire en unités mineures', 'Total en unités mineures', 'Devise', 'Expiration', 'Acteur'],
      ...events.map((e) => <Object?>[
        e['created_at'], e['request_id'], e['event_type'], e['old_status'], e['new_status'],
        e['buyer_shop_id'], e['seller_shop_id'], e['quantity'], e['unit_price_minor'],
        e['total_minor'], e['currency'], e['expires_at'], e['actor_id'],
      ]),
    ];
    final csv = rows.map((row) => row.map(_supplierCsvCell).join(',')).join('\r\n');
    await Clipboard.setData(ClipboardData(text: '\uFEFF$csv'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export CSV copié : ${events.length} événement(s). Collez dans un tableur puis enregistrez en .csv.')));
  }

  @override
  void dispose() { searchCtl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fournisseurs et achats en gros')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Catalogue de gros', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const Text('Les demandes ne prélèvent pas d’argent. Confirme les conditions avec le fournisseur avant tout paiement.'),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StockLedgerScreen())), icon: const Icon(Icons.inventory_2_outlined), label: const Text('Ouvrir l’inventaire et le journal de stock'))),
      FutureBuilder<List<Map<String, dynamic>>>(future: shopsFuture, builder: (context, snap) {
        final shops = (snap.data ?? []).where((s) => s['status'] == 'active' && s['kind'] != 'personal' && s['is_official'] != true).toList();
        if (shops.isNotEmpty && (buyerShopId == null || !shops.any((s) => s['id'] == buyerShopId))) buyerShopId = shops.first['id'] as String;
        if (shops.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Une boutique professionnelle active est nécessaire pour envoyer une demande fournisseur.'));
        return DropdownButtonFormField<String>(value: buyerShopId, decoration: const InputDecoration(labelText: 'Acheter pour ma boutique'), items: [for (final shop in shops) DropdownMenuItem(value: shop['id'] as String, child: Text('${shop['name']}'))], onChanged: (v) => setState(() => buyerShopId = v));
      }),
      const SizedBox(height: 10),
      TextField(controller: searchCtl, decoration: InputDecoration(labelText: 'Rechercher un produit de gros', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => offersFuture = Repo.wholesaleOffers(query: searchCtl.text)))), onSubmitted: (v) => setState(() => offersFuture = Repo.wholesaleOffers(query: v))),
      FutureBuilder<List<Map<String, dynamic>>>(future: offersFuture, builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        final offers = snap.data ?? [];
        if (offers.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('Aucune offre de gros disponible pour le moment.'));
        return Column(children: [for (final offer in offers) Builder(builder: (context) {
          final shop = offer['shops'] is Map ? Map<String, dynamic>.from(offer['shops'] as Map) : <String, dynamic>{};
          return Card(child: ListTile(
            leading: offer['image_url'] == null ? const Icon(Icons.inventory_2_outlined) : null,
            title: Text('${offer['name']}'), subtitle: Text('${shop['name'] ?? 'Fournisseur'} · ${money(offer['wholesale_price_minor'] as num, offer['currency'] as String)} / unité · min. ${offer['wholesale_min_qty']} · stock ${offer['stock']}'),
            trailing: FilledButton(onPressed: buyerShopId == null ? null : () => requestOffer(offer, buyerShopId!), child: const Text('Demander')),
          ));
        })]);
      }),
      const SizedBox(height: 24),
      const Text('Mes demandes fournisseur', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      FutureBuilder<List<Map<String, dynamic>>>(future: requestsFuture, builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('Aucune demande fournisseur.'));
        return FutureBuilder<List<Map<String, dynamic>>>(future: shopsFuture, builder: (context, ownedSnap) {
          final ownedIds = (ownedSnap.data ?? []).map((shop) => shop['id'].toString()).toSet();
          return Column(children: [for (final req in rows) Builder(builder: (context) {
            final isSeller = ownedIds.contains(req['seller_shop_id'].toString());
            final isBuyer = ownedIds.contains(req['buyer_shop_id'].toString());
            return Card(child: ListTile(
              title: Text('${req['quantity']} × ${req['product_name']}'),
              subtitle: Text('${req['buyer_shop_name']} → ${req['seller_shop_name']} · ${money(req['total_minor'] as num, req['currency'] as String)} · ${req['status']}${req['status'] == 'accepted' && req['expires_at'] != null ? ' · réservation jusqu’au ${req['expires_at']}' : ''}'),
              trailing: Wrap(spacing: 2, children: [
                if (isSeller && req['status'] == 'pending') IconButton(tooltip: 'Accepter', onPressed: () => act(req, 'accept'), icon: const Icon(Icons.check_circle_outline)),
                if (isSeller && req['status'] == 'pending') IconButton(tooltip: 'Refuser', onPressed: () => act(req, 'reject'), icon: const Icon(Icons.cancel_outlined)),
                if (isSeller && req['status'] == 'accepted') IconButton(tooltip: 'Confirmer la remise et décompter le stock', onPressed: () => act(req, 'fulfill'), icon: const Icon(Icons.inventory_outlined)),
                if (isBuyer && (req['status'] == 'pending' || req['status'] == 'accepted')) IconButton(tooltip: 'Annuler ma demande et libérer la réservation si elle est acceptée', onPressed: () => act(req, 'cancel'), icon: const Icon(Icons.undo)),
              ]),
            ));
          })]);
        });
      }),
      const SizedBox(height: 24),
      const Text('Historique des opérations fournisseurs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const Text('Journal des créations, décisions, expirations et remises. Les montants conservent leur devise d’origine. Les statistiques ne représentent pas des paiements encaissés.'),
      Row(children: [
        Expanded(child: DropdownButtonFormField<int>(value: historyDays, decoration: const InputDecoration(labelText: 'Période'), items: const [DropdownMenuItem(value: 7, child: Text('7 jours')), DropdownMenuItem(value: 30, child: Text('30 jours')), DropdownMenuItem(value: 90, child: Text('90 jours'))], onChanged: (v) => setState(() => historyDays = v ?? 30))),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<String>(value: historyType, decoration: const InputDecoration(labelText: 'Événement'), items: const [DropdownMenuItem(value: 'all', child: Text('Tous')), DropdownMenuItem(value: 'request_created', child: Text('Créations')), DropdownMenuItem(value: 'request_accepted', child: Text('Acceptations')), DropdownMenuItem(value: 'request_rejected', child: Text('Refus')), DropdownMenuItem(value: 'request_cancelled', child: Text('Annulations')), DropdownMenuItem(value: 'reservation_expired', child: Text('Expirations')), DropdownMenuItem(value: 'goods_handed_over', child: Text('Remises'))], onChanged: (v) => setState(() => historyType = v ?? 'all'))),
      ]),
      FutureBuilder<List<Map<String, dynamic>>>(future: eventsFuture, builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(8), child: Text('Historique indisponible : ${Repo.err(snap.error!)}'));
        final allEvents = snap.data ?? [];
        final events = _filterSupplierEvents(allEvents);
        String label(String type) => switch (type) {
          'request_created' => 'Demande créée',
          'request_accepted' => 'Demande acceptée',
          'request_rejected' => 'Demande refusée',
          'request_cancelled' => 'Demande annulée',
          'reservation_expired' => 'Réservation expirée',
          'goods_handed_over' => 'Remise confirmée',
          'reservation_deadline_set' => 'Échéance de réservation mise à jour',
          _ => 'Demande mise à jour',
        };
        final totals = <String, int>{'HTG': 0, 'USD': 0};
        for (final e in events) { final currency = '${e['currency'] ?? ''}'; final amount = int.tryParse('${e['total_minor'] ?? 0}') ?? 0; if (totals.containsKey(currency)) totals[currency] = totals[currency]! + amount; }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rapport sur ${events.length} événement(s) filtré(s) · ${historyDays} jours', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Totaux des événements : ${money(totals['HTG']!, 'HTG')} · ${money(totals['USD']!, 'USD')}'),
            const SizedBox(height: 4),
            const Text('Totaux indicatifs des événements, pas un chiffre d’affaires ni une preuve de paiement.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: events.isEmpty ? null : () => _exportSupplierEvents(events), icon: const Icon(Icons.download_outlined), label: Text('Exporter ${events.length} événement(s) en CSV')),
          ]))),
          if (events.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Aucun événement pour ces filtres.')),
          for (final event in events) Card(child: ListTile(
            leading: Icon(event['event_type'] == 'goods_handed_over' ? Icons.inventory_2_outlined : event['event_type'] == 'reservation_expired' ? Icons.timer_off_outlined : Icons.history),
            title: Text(label(event['event_type']?.toString() ?? '')),
            subtitle: Text('Demande ${event['request_id']}\n${event['old_status'] == null ? 'État initial : ${event['new_status']}' : '${event['old_status']} → ${event['new_status']}'} · ${event['quantity']} unités · ${money(event['total_minor'] as num, event['currency'] as String)} · ${event['created_at']}'),
            isThreeLine: true,
          )),
        ]);
      }),
    ]),
  );
}

/// Suivi client de la position du coursier affecté.
/// La position est lue via une RPC sécurisée côté serveur; aucune lecture directe de courier_status.
class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String shopName;
  const OrderTrackingScreen({super.key, required this.orderId, required this.shopName});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> with WidgetsBindingObserver {
  static const LatLng _haitiCenter = LatLng(18.9712, -72.2852);
  final MapController _mapController = MapController();
  Timer? _poller;
  Map<String, dynamic>? _courier;
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdate;
  DateTime? _courierPositionAt;
  List<Map<String, dynamic>> _offers = [];
  bool _offersLoading = false;
  String? _offersError;
  Map<String, dynamic>? _trafficDelay;

  double? get _destinationLat => double.tryParse('${_courier?['destination_lat'] ?? ''}');
  double? get _destinationLng => double.tryParse('${_courier?['destination_lng'] ?? ''}');
  bool get _hasDestination => _destinationLat != null && _destinationLng != null &&
      _destinationLat!.isFinite && _destinationLng!.isFinite &&
      _destinationLat! >= -90 && _destinationLat! <= 90 &&
      _destinationLng! >= -180 && _destinationLng! <= 180;

  double? get _lat => double.tryParse('${_courier?['lat'] ?? ''}');
  double? get _lng => double.tryParse('${_courier?['lng'] ?? ''}');
  bool get _hasPosition => _lat != null && _lng != null &&
      _lat!.isFinite && _lng!.isFinite && _lat! >= -90 && _lat! <= 90 &&
      _lng! >= -180 && _lng! <= 180;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _refreshOffers();
    _poller = Timer.periodic(const Duration(seconds: 10), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) { _refresh(); _refreshOffers(); }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { _refresh(); _refreshOffers(); }
  }

  Future<void> _refresh() async {
    try {
      final row = await Repo.activeCourierLocation(widget.orderId);
      final delay = await Repo.deliveryTrafficDelay(widget.orderId);
      if (!mounted) return;
      setState(() {
        _trafficDelay = delay;
        _courier = row;
        _error = null;
        _loading = false;
        final rawTimestamp = row?['location_updated_at'];
        _courierPositionAt = rawTimestamp == null ? null : DateTime.tryParse(rawTimestamp.toString())?.toLocal();
        _lastUpdate = DateTime.now();
      });
      if (_hasPosition) {
        _mapController.move(LatLng(_lat!, _lng!), 15);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = Repo.err(e);
        _loading = false;
      });
    }
  }

  Future<void> _refreshOffers() async {
    if (!mounted || _offersLoading) return;
    setState(() { _offersLoading = true; _offersError = null; });
    try {
      final offers = await Repo.deliveryOffersForOrder(widget.orderId);
      if (!mounted) return;
      setState(() { _offers = offers; _offersLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _offersError = Repo.err(e); _offersLoading = false; });
    }
  }

  Future<void> _chooseOffer(Map<String, dynamic> offer) async {
    final accepted = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Choisir ce coursier ?'),
      content: Text('Prix proposé : ${money(offer['amount_minor'] as num, offer['currency'] as String)}\nDélai annoncé : ${offer['eta_minutes']} min\n\nHAITIKET ajustera les frais dans la devise de la commande : un supplément sera débité du portefeuille correspondant, ou la différence sera remboursée dans ce portefeuille.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Retour')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Choisir'))],
    ));
    if (accepted != true || !mounted) return;
    try {
      await Repo.selectDeliveryPriceOffer(offer['offer_id'].toString());
      if (!mounted) return;
      toast(context, 'Coursier sélectionné. Les frais ont été ajustés via le portefeuille de la commande.');
      await _refreshOffers();
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  String _updatedText() {
    if (_courierPositionAt == null) return 'Dernière position du coursier : inconnue.';
    final local = _courierPositionAt!;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    final age = DateTime.now().difference(_courierPositionAt!);
    final stale = age > const Duration(minutes: 2);
    final suffix = stale ? ' · position périmée (${age.inMinutes} min)' : '';
    return 'Dernière position serveur : $hh:$mm:$ss$suffix';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Suivi de livraison')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.shopName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink)),
              const SizedBox(height: 4),
              const Text('La carte affiche uniquement la position du coursier autorisée par le serveur.'),
              const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              if (_trafficDelay != null) ...[
                Card(
                  color: const Color(0xFFFFF1EC),
                  child: ListTile(
                    leading: const Icon(Icons.traffic, color: C.terracotta),
                    title: Text('Retard signalé : +${((_trafficDelay!['extension_minutes'] as num?) ?? 0) ~/ 60} h', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${_trafficDelay!['reason'] ?? 'Motif non précisé'}\nSignalé le ${_trafficDelay!['reported_at'] ?? ''}'),
                  ),
                ),
              ],
              const Text('Offres des coursiers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (_offersLoading && _offers.isEmpty) const LinearProgressIndicator(),
              if (_offersError != null) Text('Offres indisponibles : $_offersError', style: const TextStyle(color: C.terracotta)),
              if (!_offersLoading && _offers.isEmpty && _offersError == null)
                const Text('Aucune offre active pour le moment. Les coursiers disponibles peuvent proposer leur tarif.', style: TextStyle(color: C.muted)),
              for (final offer in _offers)
                Card(
                  child: ListTile(
                    title: Text('${offer['courier_name']} · ${money(offer['amount_minor'] as num, offer['currency'] as String)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${offer['eta_minutes']} min${(offer['note'] ?? '').toString().trim().isEmpty ? '' : ' · ${offer['note']}'}'),
                    trailing: FilledButton(onPressed: () => _chooseOffer(offer), child: const Text('Choisir')),
                  ),
                ),
              Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _refreshOffers, icon: const Icon(Icons.refresh), label: const Text('Actualiser les offres'))),
              if (_error != null) Text('Impossible de récupérer la position : $_error', style: const TextStyle(color: C.terracotta)),
              if (!_loading && _error == null && !_hasPosition)
                const Text('POSITION INDISPONIBLE : aucune coordonnée valide reçue. Vérifie que le coursier est affecté, autorisé à partager sa position et connecté.'),
              if (_hasPosition && _courierPositionAt != null && DateTime.now().difference(_courierPositionAt!) > const Duration(minutes: 2))
                const Text('ATTENTION : la dernière position est ancienne. Le marqueur ne représente pas nécessairement la position actuelle.', style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
              if (!_hasDestination)
                const Text('Destination réelle non enregistrée pour cette commande. La carte ne peut pas inventer son emplacement.', style: TextStyle(color: C.terracotta)),
              if (_hasPosition) Text('Coursier : ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
              if (_hasDestination) Text('Destination : ${_destinationLat!.toStringAsFixed(5)}, ${_destinationLng!.toStringAsFixed(5)}'),
              Text(_updatedText(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Align(alignment: Alignment.centerRight, child: TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
              )),
            ]),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: const MapOptions(initialCenter: _haitiCenter, initialZoom: 8),
              children: [
                TileLayer(
                  urlTemplate: const String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                  userAgentPackageName: 'com.haitiket.app',
                ),
                if (_hasPosition || _hasDestination)
                  MarkerLayer(markers: [
                    if (_hasPosition) Marker(
                      point: LatLng(_lat!, _lng!), width: 64, height: 64,
                      child: const Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.delivery_dining, size: 38, color: C.terracotta),
                        Text('Coursier', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, backgroundColor: Colors.white)),
                      ]),
                    ),
                    if (_hasDestination) Marker(
                      point: LatLng(_destinationLat!, _destinationLng!), width: 76, height: 64,
                      child: const Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.location_on, size: 38, color: Colors.blue),
                        Text('Destination', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, backgroundColor: Colors.white)),
                      ]),
                    ),
                  ]),
              ],
            ),
          ),
        ]),
      );
}
