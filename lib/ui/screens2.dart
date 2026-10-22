import 'dart:convert';
import 'package:flutter/material.dart';
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
import 'widgets.dart';

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

Widget _h(String t) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Text(t, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1)));

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
  bool locating = false;
  double? deliveryLat;
  double? deliveryLng;
  double? deliveryAccuracy;

  Future<void> useCurrentLocation() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Active la localisation GPS de ton appareil, puis réessaie.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw Exception('Autorisation de localisation refusée.');
      if (permission == LocationPermission.deniedForever) throw Exception('La localisation est bloquée dans les paramètres de l’appareil.');
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, timeLimit: Duration(seconds: 20)));
      if (!mounted) return;
      deliveryLat = pos.latitude;
      deliveryLng = pos.longitude;
      deliveryAccuracy = pos.accuracy;
      address.text = 'Position GPS du lieu de livraison : ${pos.latitude.toStringAsFixed(7)}, ${pos.longitude.toStringAsFixed(7)}. Précision déclarée par l’appareil : ${pos.accuracy.toStringAsFixed(0)} m. Heure de capture : ${pos.timestamp.toIso8601String()}. Le client a sélectionné ce lieu au moment de la commande.';
      setState(() {});
      toast(context, 'Position actuelle ajoutée. Vérifie que tu peux recevoir le colis à cet endroit.');
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> submit() async {
    final lines = CartStore.lines.value.values.toList();
    if (lines.isEmpty) return;
    setState(() => busy = true);
    try {
      final orders = await Repo.createOrders(lines, mode, address.text, coupon.text);
      CartStore.lines.value = {};
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, '${orders.length} commande(s) enregistrée(s). Stock réservé 30 min — paiement indisponible pour le moment.');
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
                      setState(() {});
                    },
                  ),
                );
              },
            ),
            OutlinedButton.icon(
              onPressed: locating ? null : useCurrentLocation,
              icon: locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
              label: Text(locating ? 'Localisation en cours…' : 'Livrer à ma position actuelle'),
            ),
            if (deliveryLat != null && deliveryLng != null) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Position sélectionnée : ${deliveryLat!.toStringAsFixed(6)}, ${deliveryLng!.toStringAsFixed(6)} · précision GPS déclarée : ${deliveryAccuracy!.toStringAsFixed(0)} m. Vérifie le point exact avant de commander.', style: const TextStyle(color: C.muted)),
            ),
            Field(address, 'Adresse ou lieu exact de livraison (domicile, école, université, travail, ami, camping, déplacement…)'),
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
          const Text("Le paiement n'est pas encore disponible : la commande reste « en attente de paiement » et le stock est libéré à l'expiration de la réservation.", style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
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
  void reload() => setState(() => f = Repo.myOrders());

  Future<void> checkPending() async {
    try {
      final l = await Repo.myOrders();
      for (final o in l) {
        if (o['status'] == 'PENDING_PAYMENT') await Repo.checkPayment('order', o['id'] as String);
      }
    } catch (_) {}
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
        _h('Mes commandes'),
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
                        const SizedBox(height: 6),
                        for (final it in (o['order_items'] as List)) Text('${it['qty']} × ${it['name']}${it['variant_label'] == null ? '' : ' (${it['variant_label']})'}'),
                        const SizedBox(height: 6),
                        Text('Total : ${money(o['total_minor'] as num, o['currency'] as String)}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.green)),
                        if (o['status'] == 'PENDING_PAYMENT') ...[
                          const SizedBox(height: 6),
                          PrimaryButton(label: 'Payer avec MonCash', icon: Icons.payments_outlined, onPressed: () => payAndOpen(context, 'order', o['id'] as String)),
                          TextButton(
                            onPressed: () async {
                              await Repo.checkPayment('order', o['id'] as String);
                              reload();
                            },
                            child: const Text("J'ai payé : vérifier mon paiement"),
                          ),
                        ],
                        if (o['status'] != 'PENDING_PAYMENT' && o['status'] != 'CANCELLED') TextButton(onPressed: () => showPin(context, o['id'] as String, 'Code de remise'), child: const Text('Mon code de remise')),
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
        _h('Espace vendeur'),
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

  Future<void> editProduct(Map<String, dynamic> p) async {
    final n = TextEditingController(text: '${p['name'] ?? ''}');
    final price = TextEditingController(text: (((p['price_minor'] as num?) ?? 0) / 100).toStringAsFixed(2));
    final stock = TextEditingController(text: '${p['stock'] ?? 0}');
    final desc = TextEditingController(text: '${p['description'] ?? ''}');
    final unit = TextEditingController(text: '${p['unit_label'] ?? 'unité'}');
    final attrs = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(p['attributes'] is Map ? p['attributes'] : <String, dynamic>{}));
    String currency = (p['currency'] as String?) ?? 'HTG';
    final variantsCtl = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(await Repo.productVariants(p['id'] as String)));
    final tiersCtl = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(await Repo.productTiers(p['id'] as String)));
    final statusOptions = ['published', 'paused', 'draft'];
    String productStatus = statusOptions.contains(p['status']) ? p['status'] as String : 'published';
    String? editCategory = p['category_id'] as String?;
    final categories = await Repo.categories();
    final audienceOptions = ['Tout public', 'Homme', 'Femme', 'Enfant', 'Adolescent', 'Unisexe'];
    String audience = audienceOptions.contains(p['audience']) ? p['audience'] as String : 'Tout public';
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
            DropdownButtonFormField<String>(
              value: audience,
              decoration: const InputDecoration(labelText: 'Public concerné'),
              items: [for (final a in audienceOptions) DropdownMenuItem(value: a, child: Text(a))],
              onChanged: (v) { if (v != null) setDialogState(() => audience = v); },
            ),
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
            TextField(controller: attrs, maxLines: 5, decoration: const InputDecoration(labelText: 'Caractéristiques supplémentaires (JSON)', helperText: 'Ex. marque, matière, modèle, dimensions, état, garantie…')),
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
      await Repo.updateProduct(p['id'] as String, {
        'name': n.text.trim(),
        'price_minor': (v * 100).round(),
        'stock': q,
        'description': desc.text.trim(),
        'unit_label': unit.text.trim(),
        'audience': audience == 'Tout public' ? null : audience,
        'category_id': editCategory,
        'status': productStatus,
        'attributes': jsonDecode(attrs.text.isEmpty ? '{}' : attrs.text) as Map<String, dynamic>,
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

  Future<void> orderAction(Map<String, dynamic> o, String v) async {
    final id = o['id'] as String;
    try {
      if (v == 'chat') return openChat(context, 'order', id);
      if (v == 'pin') return showPin(context, id, 'Code de collecte');
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

  @override
  Widget build(BuildContext context) {
    final active = widget.shop['status'] == 'active';
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.shop['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
          Text(active ? 'Boutique active' : 'En attente de vérification — vous pourrez publier après activation.', style: TextStyle(color: active ? C.green : C.terracotta, fontWeight: FontWeight.w700)),
          if (!personal) PlanCard(shop: widget.shop),
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
            const SizedBox(height: 16),
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
                        if (p['source'] == 'bazar' && !paidOk(p)) TextButton(onPressed: () => payAndOpen(context, 'bazar_listing', p['id'] as String), child: const Text('Payer'))
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
              if (items.isEmpty) return const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aucune commande.', style: TextStyle(color: C.muted)));
              return Column(children: [
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
