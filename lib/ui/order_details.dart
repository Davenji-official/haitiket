import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'contacts_widget.dart';
import 'screens5.dart';
import 'widgets.dart';

const kDeliveryKindLabels = <String, String>{
  'home': 'Domicile',
  'precise': 'Adresse précise',
  'meeting_point': 'Point de rencontre',
  'school': 'École',
  'work': 'Travail',
  'other': 'Autre lieu',
  'pickup': 'Retrait chez le vendeur',
  'center': 'Centre HAITIKET',
};

String deliveryKindLabel(Object? k) => kDeliveryKindLabels['$k'] ?? 'Adresse';

/// Fiche complète d'une commande pour le client, le vendeur et le livreur affecté (le livreur non affecté voit un aperçu).
class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailsScreen(this.orderId, {super.key});
  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late Future<Map<String, dynamic>> f = Repo.orderFullDetails(widget.orderId);

  Future<void> openMap(num lat, num lng) async {
    final ok = await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, "Impossible d'ouvrir la carte.");
  }

  Widget card(String title, List<Widget> children) => Card(
        color: C.card,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.ink)),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  Widget kv(String k, Object? v) => v == null || '$v'.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: TextStyle(color: C.muted))),
            Expanded(child: SelectableText('$v', style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );

  void zoom(String url) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(child: InteractiveViewer(child: Image.network(url, errorBuilder: (_, __, ___) => const Text('Image non affichable', style: TextStyle(color: Colors.white))))),
        ),
      ));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Détails de la commande', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: FutureBuilder<Map<String, dynamic>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return EmptyState(title: 'Commande inaccessible', text: Repo.err(s.error!));
            final d = s.data!;
            final preview = d['preview'] == true;
            final cur = '${d['currency']}';
            final shop = Map<String, dynamic>.from((d['shop'] as Map?) ?? const {});
            final items = ((d['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final immediate = d['speed'] == 'immediate';
            final isDelivery = d['mode'] == 'delivery';
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.all(14), children: [
                  if (preview)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(12)),
                      child: Text('Aperçu : l’adresse exacte et les numéros du client vous seront communiqués quand le client aura choisi votre offre.', style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
                    ),
                  card('Commande', [
                    kv('Statut', d['status']),
                    kv('Type', isDelivery ? 'Livraison HAITIKET' : 'Retrait chez le vendeur'),
                    kv('Type de commande', immediate ? '⚡ IMMÉDIATE — à préparer maintenant, délai estimé ~${d['promised_minutes'] ?? 45} min (objectif indicatif 45 min, sans garantie)' : 'Standard — délai estimé ~${_fmt(d['promised_minutes'] ?? shop['prep_minutes'] ?? 30)} (préparation du vendeur${isDelivery ? ' + livraison' : ''})'),
                    kv('Articles', money(d['items_minor'] as num, cur)),
                    kv('Livraison', isDelivery ? (_n(d['delivery_minor']) > 0 ? money(d['delivery_minor'] as num, cur) : 'Prix proposé par les livreurs') : null),
                    kv('Total', money(d['total_minor'] as num, cur)),
                  ]),
                  card('Boutique (collecte)', [
                    kv('Nom', shop['name']),
                    kv('Ville', shop['city']),
                    if (shop['lat'] != null) OutlinedButton.icon(onPressed: () => openMap(shop['lat'] as num, shop['lng'] as num), icon: const Icon(Icons.storefront_outlined), label: const Text('Itinéraire vers la boutique')),
                  ]),
                  if (isDelivery)
                    card('Livraison', [
                      kv('Type d’adresse', deliveryKindLabel(d['kind'])),
                      kv('Adresse', preview ? 'Communiquée après le choix du livreur' : d['address']),
                      kv('Repère', d['landmark']),
                      kv('Destinataire', d['recipient']),
                      if (!preview && d['lat'] != null) OutlinedButton.icon(onPressed: () => openMap(d['lat'] as num, d['lng'] as num), icon: const Icon(Icons.navigation_outlined), label: const Text('Itinéraire vers le client')),
                    ]),
                  if (!preview) ContactsCard(orderId: widget.orderId),
                  card('Articles (${items.length})', [
                    if (items.isEmpty) Text('Aucun article.', style: TextStyle(color: C.muted)),
                    for (final i in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: GestureDetector(
                          onTap: i['image_url'] == null ? null : () => zoom('${i['image_url']}'),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: i['image_url'] != null ? Image.network('${i['image_url']}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: C.mint, child: Icon(Icons.image_not_supported_outlined, color: C.muted))) : Container(color: C.mint, child: Icon(Icons.shopping_bag_outlined, color: C.green)),
                            ),
                          ),
                        ),
                        title: Text('${i['qty']}× ${i['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${i['variant'] ?? ''} ${money((i['unit_minor'] as num) * (i['qty'] as num), cur)}'.trim()),
                        trailing: i['video_url'] == null ? null : IconButton(tooltip: 'Voir la vidéo du produit', icon: Icon(Icons.play_circle_fill, color: C.green, size: 32), onPressed: () => launchUrl(Uri.parse('${i['video_url']}'), mode: LaunchMode.externalApplication)),
                      ),
                  ]),
                ]),
              ),
            );
          },
        ),
      );

  static num _n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);

  static String _fmt(Object? m) {
    final v = _n(m).toInt();
    if (v < 90) return '$v min';
    if (v < 60 * 48) return '${(v / 60).toStringAsFixed(v % 60 == 0 ? 0 : 1)} h';
    return '${(v / 1440).toStringAsFixed(1)} jours';
  }
}

/// Réglages vendeur : délai de préparation, livraison immédiate et prix fixé par le vendeur pour l'immédiat.
class SellerDeliverySettingsCard extends StatefulWidget {
  final String shopId;
  const SellerDeliverySettingsCard({super.key, required this.shopId});
  @override
  State<SellerDeliverySettingsCard> createState() => _SellerDeliverySettingsCardState();
}

class _SellerDeliverySettingsCardState extends State<SellerDeliverySettingsCard> {
  final prep = TextEditingController(text: '30'), immPrep = TextEditingController(text: '20'), feeHtg = TextEditingController(), feeUsd = TextEditingController();
  bool immediate = false, loaded = false, busy = false;
  String prepUnit = 'min';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await Supabase.instance.client.from('shops').select('prep_minutes,immediate_delivery_enabled,immediate_prep_minutes,immediate_fee_htg_minor,immediate_fee_usd_minor').eq('id', widget.shopId).maybeSingle();
      if (r != null && mounted) {
        setState(() {
          final pm = ((r['prep_minutes'] as num?) ?? 30).toInt();
          if (pm >= 1440 && pm % 1440 == 0) {
            prepUnit = 'j';
            prep.text = '${pm ~/ 1440}';
          } else if (pm >= 60 && pm % 60 == 0) {
            prepUnit = 'h';
            prep.text = '${pm ~/ 60}';
          } else {
            prepUnit = 'min';
            prep.text = '$pm';
          }
          immPrep.text = '${r['immediate_prep_minutes'] ?? 20}';
          immediate = r['immediate_delivery_enabled'] == true;
          feeHtg.text = r['immediate_fee_htg_minor'] == null ? '' : (((r['immediate_fee_htg_minor'] as num) / 100).toString());
          feeUsd.text = r['immediate_fee_usd_minor'] == null ? '' : (((r['immediate_fee_usd_minor'] as num) / 100).toString());
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  int? minor(String t) {
    final v = double.tryParse(t.trim().replaceAll(',', '.'));
    return v == null ? null : (v * 100).round();
  }

  Future<void> save() async {
    final pv = double.tryParse(prep.text.trim().replaceAll(',', '.'));
    final p = pv == null ? null : (pv * (prepUnit == 'j' ? 1440 : (prepUnit == 'h' ? 60 : 1))).round();
    final ip = int.tryParse(immPrep.text.trim()) ?? 20;
    if (p == null || p < 1 || p > 14400) return toast(context, 'Délai de préparation standard : de 1 minute à 10 jours.');
    if (ip < 5 || ip > 240) return toast(context, 'Préparation immédiate : 5 à 240 minutes.');
    setState(() => busy = true);
    try {
      await Repo.sellerSetDeliverySettings(widget.shopId, p, immediate, minor(feeHtg.text), minor(feeUsd.text), immediatePrepMinutes: ip);
      if (mounted) toast(context, 'Réglages enregistrés.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Commandes immédiates et standard', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.ink)),
          Text('Standard : prix normal, vous annoncez votre délai (minutes, heures ou jours ; réglable aussi produit par produit). Immédiate : objectif indicatif de 45 min, sans garantie, en retrait comme en livraison ; réservée aux produits que vous marquez « immédiat possible ».', style: TextStyle(color: C.muted, fontSize: 12)),
          if (!loaded) const LinearProgressIndicator(),
          Row(children: [
            Expanded(child: Field(prep, 'Délai de préparation standard par défaut', type: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 10),
            DropdownButton<String>(value: prepUnit, items: const [DropdownMenuItem(value: 'min', child: Text('minutes')), DropdownMenuItem(value: 'h', child: Text('heures')), DropdownMenuItem(value: 'j', child: Text('jours'))], onChanged: (v) => setState(() => prepUnit = v ?? 'min')),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: immediate, onChanged: (v) => setState(() => immediate = v), title: const Text('Accepter les commandes immédiates (retrait et livraison)')),
          if (immediate) ...[
            Field(immPrep, 'Temps de préparation en immédiat (minutes)', type: TextInputType.number),
            Text('Supplément de commande immédiate (facultatif) : s’ajoute au prix normal des articles. Le prix de la livraison, lui, est toujours proposé par les livreurs.', style: TextStyle(color: C.muted, fontSize: 12)),
            Field(feeHtg, 'Supplément immédiat en HTG (vide = aucun)', type: const TextInputType.numberWithOptions(decimal: true)),
            Field(feeUsd, 'Supplément immédiat en USD (vide = aucun)', type: const TextInputType.numberWithOptions(decimal: true)),
          ],
          const SizedBox(height: 6),
          FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
        ]),
      );
}


/// Taux USD propre à la boutique : permet aux clients de payer en gourdes vos produits en USD à VOTRE taux.
class SellerUsdRateCard extends StatefulWidget {
  final String shopId;
  const SellerUsdRateCard({super.key, required this.shopId});
  @override
  State<SellerUsdRateCard> createState() => _SellerUsdRateCardState();
}

class _SellerUsdRateCardState extends State<SellerUsdRateCard> {
  final rate = TextEditingController();
  double? platform;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    Repo.shopUsdRate(widget.shopId).then((r) {
      if (r == null || !mounted) return;
      setState(() {
        platform = (r['platform_rate'] as num?)?.toDouble();
        if (r['own'] == true) rate.text = '${r['rate']}';
      });
    });
  }

  Future<void> save() async {
    final t = rate.text.trim().replaceAll(',', '.');
    final v = t.isEmpty ? null : double.tryParse(t);
    if (t.isNotEmpty && (v == null || v <= 0)) return toast(context, 'Taux invalide.');
    setState(() => busy = true);
    try {
      await Repo.sellerSetUsdRate(widget.shopId, v);
      if (mounted) toast(context, v == null ? 'Taux de la plateforme appliqué.' : 'Votre taux est enregistré.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mon taux pour les produits en USD', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.ink)),
          Text('Un client qui n’a que des gourdes peut payer vos produits en USD à ce taux (HTG pour 1 USD). Vous recevez alors des gourdes. Vide = taux de la plateforme${platform == null ? '' : ' (${platform!.toStringAsFixed(2)})'}. Écart maximal autorisé par rapport au taux de la plateforme : défini par l’administration.', style: TextStyle(color: C.muted, fontSize: 12)),
          Field(rate, 'Mon taux : 1 USD = … HTG', type: const TextInputType.numberWithOptions(decimal: true)),
          FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer mon taux')),
        ]),
      );
}
