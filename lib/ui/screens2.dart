import 'package:flutter/material.dart';
import '../config.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'widgets.dart';

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
  bool busy = false;

  Future<void> submit() async {
    final lines = CartStore.lines.value.values.toList();
    if (lines.isEmpty) return;
    setState(() => busy = true);
    try {
      final orders = await Repo.createOrders(lines, mode, address.text);
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
    final total = lines.fold<int>(0, (a, l) => a + l.priceMinor * l.qty);
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
          if (mode == 'delivery') Field(address, 'Adresse de livraison (commune, quartier, repères)'),
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

class _OrdersState extends State<OrdersScreen> {
  late Future<List<Map<String, dynamic>>> f = Repo.myOrders();
  void reload() => setState(() => f = Repo.myOrders());

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
              if (s.hasError) return const EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.');
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
                        for (final it in (o['order_items'] as List)) Text('${it['qty']} × ${it['name']}'),
                        const SizedBox(height: 6),
                        Text('Total : ${money(o['total_minor'] as num, o['currency'] as String)}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.green)),
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
  int imgKey = 0;
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
      await Repo.addProduct(widget.shop['id'] as String, name.text.trim(), (p * 100).round(), st, prodImg, true, description: desc.text);
      name.clear();
      price.clear();
      stock.clear();
      desc.clear();
      prodImg = null;
      imgKey++;
      reload();
      if (mounted) toast(context, 'Produit publié.');
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
          if (active) ...[
            const SizedBox(height: 16),
            Field(name, 'Nom du produit'),
            Field(price, 'Prix en HTG', type: TextInputType.number),
            Field(stock, 'Stock disponible', type: TextInputType.number),
            Field(desc, 'Description (facultatif)'),
            ImageUploadField(key: ValueKey(imgKey), onUrl: (u) => prodImg = u),
            FilledButton(onPressed: add, child: const Text('Publier le produit')),
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
                      subtitle: Text('${money(p['price_minor'] as num, p['currency'] as String)} · stock ${p['stock']} · ${p['status'] == 'published' ? 'publié' : 'masqué'}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(onPressed: (p['stock'] as int) > 0 ? () => patch(p['id'] as String, {'stock': (p['stock'] as int) - 1}) : null, icon: const Icon(Icons.remove_circle_outline)),
                        IconButton(onPressed: () => patch(p['id'] as String, {'stock': (p['stock'] as int) + 1}), icon: const Icon(Icons.add_circle_outline)),
                        Switch(value: p['status'] == 'published', onChanged: (v) => patch(p['id'] as String, {'status': v ? 'published' : 'paused'})),
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
                    title: Text('${(o['order_items'] as List).map((i) => '${i['qty']}× ${i['name']}').join(', ')}'),
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
