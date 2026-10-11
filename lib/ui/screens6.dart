import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens5.dart';
import 'widgets.dart';

/// Ouvre la page de paiement MonCash (Bazik) pour une commande, une annonce Bazar ou un abonnement boutique.
Future<void> payAndOpen(BuildContext context, String purpose, String target) async {
  try {
    toast(context, 'Ouverture du paiement MonCash…');
    final url = await Repo.startPayment(purpose, target);
    final ok = await launchUrl(Uri.parse(url), mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication, webOnlyWindowName: '_self');
    if (!ok && context.mounted) toast(context, "Impossible d'ouvrir la page de paiement.");
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}

String feeText(int? minor, String usd) => minor == null ? '$usd USD (taux de change non configuré : paiement indisponible)' : '$usd USD ≈ ${money(minor, 'HTG')}';

class PlanCard extends StatelessWidget {
  final Map<String, dynamic> shop;
  const PlanCard({super.key, required this.shop});
  @override
  Widget build(BuildContext context) {
    final until = shop['plan_paid_until'] as String?;
    final valid = until != null && DateTime.parse(until).isAfter(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: valid ? C.mint : const Color(0xFFFFF1EC), borderRadius: BorderRadius.circular(18)),
      child: FutureBuilder<int?>(
        future: Repo.quoteFee('shop_plan'),
        builder: (_, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valid ? 'Abonnement actif jusqu\'au ${until.substring(0, 10)}' : 'Abonnement boutique non payé', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
          Text('Tarif mensuel : ${feeText(s.data, '20')}', style: const TextStyle(color: C.muted)),
          const SizedBox(height: 8),
          PrimaryButton(label: valid ? 'Prolonger de 30 jours' : "Payer l'abonnement", icon: Icons.payments_outlined, onPressed: s.data == null ? null : () => payAndOpen(context, 'shop_plan', shop['id'] as String)),
        ]),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onPick;
  const _Swatches({required this.value, required this.onPick});
  static const palette = ['#17332E', '#E8694A', '#F2B63D', '#2F6B52', '#1D4ED8', '#B91C1C', '#7C3AED', '#0F766E', '#111827', '#DB2777'];
  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (final h in palette)
          Pressable(
            onTap: () => onPick(h),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              width: value == h ? 46 : 38,
              height: value == h ? 46 : 38,
              decoration: BoxDecoration(color: hexColor(h), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: value == h ? hexColor(h)!.withValues(alpha: .6) : const Color(0x22000000), blurRadius: value == h ? 12 : 4)]),
              child: value == h ? const Icon(Icons.check, color: Colors.white, size: 22) : null,
            ),
          ),
      ]);
}

/// Personnalisation d'une boutique professionnelle : logo, bannière, slogan, couleurs.
class BrandingEditor extends StatefulWidget {
  final Map<String, dynamic> shop;
  const BrandingEditor({super.key, required this.shop});
  @override
  State<BrandingEditor> createState() => _BrandingState();
}

class _BrandingState extends State<BrandingEditor> {
  late final slogan = TextEditingController(text: (widget.shop['slogan'] ?? '') as String);
  late String? logo = widget.shop['logo_url'] as String?;
  late String? banner = widget.shop['banner_url'] as String?;
  late String? primary = widget.shop['color_primary'] as String?;
  late String? accent = widget.shop['color_accent'] as String?;
  bool busy = false;

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await Repo.updateBranding(widget.shop['id'] as String, logo, banner, slogan.text.trim(), primary, accent);
      if (mounted) toast(context, 'Boutique personnalisée.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Personnaliser ma boutique', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
        children: [
          const Align(alignment: Alignment.centerLeft, child: Text('Logo', style: TextStyle(fontWeight: FontWeight.w700))),
          ImageUploadField(onUrl: (u) => logo = u),
          const Align(alignment: Alignment.centerLeft, child: Text('Bannière', style: TextStyle(fontWeight: FontWeight.w700))),
          ImageUploadField(onUrl: (u) => banner = u),
          Field(slogan, 'Slogan (80 caractères max)'),
          const Align(alignment: Alignment.centerLeft, child: Text('Couleur principale', style: TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          _Swatches(value: primary, onPick: (h) => setState(() => primary = h)),
          const SizedBox(height: 14),
          const Align(alignment: Alignment.centerLeft, child: Text("Couleur d'accent", style: TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          _Swatches(value: accent, onPick: (h) => setState(() => accent = h)),
          const SizedBox(height: 16),
          PrimaryButton(label: busy ? 'Enregistrement…' : 'Enregistrer', icon: Icons.palette_outlined, onPressed: busy ? null : save),
          const SizedBox(height: 12),
        ],
      );
}

/// Publier une annonce au Bazar : produit d'un vendeur particulier, 2 USD pour 14 jours.
class ListingFormScreen extends StatefulWidget {
  const ListingFormScreen({super.key});
  @override
  State<ListingFormScreen> createState() => _ListingFormState();
}

class _ListingFormState extends State<ListingFormScreen> {
  final title = TextEditingController(), desc = TextEditingController(), price = TextEditingController(), qty = TextEditingController(text: '1'), city = TextEditingController();
  late final Future<List<Map<String, dynamic>>> cats = Repo.categories();
  late final Future<int?> fee = Repo.quoteFee('bazar_listing');
  String? img, catId;
  bool shareLoc = true, busy = false;

  Future<void> submit() async {
    final p = double.tryParse(price.text.replaceAll(',', '.'));
    final q = int.tryParse(qty.text);
    if (title.text.trim().length < 2 || p == null || p <= 0 || q == null || q < 1) return toast(context, 'Titre, prix et quantité valides requis.');
    setState(() => busy = true);
    try {
      final shopId = await Repo.ensurePersonalShop(city.text.trim());
      if (shareLoc) {
        final pos = await myPosition(context);
        if (pos != null) await Repo.setShopLocation(shopId, pos.latitude, pos.longitude);
      }
      await Repo.addProduct(shopId, title.text.trim(), (p * 100).round(), q, img, false, description: desc.text, categoryId: catId, source: 'bazar');
      if (!mounted) return;
      final fq = await fee;
      if (!mounted) return;
      final pay = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Annonce enregistrée'),
          content: Text("Pour la publier pendant 14 jours : ${feeText(fq, '2')}.\nVous pouvez aussi payer plus tard depuis « Espace vendeur »."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Plus tard')),
            if (fq != null) FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Payer maintenant')),
          ],
        ),
      );
      if (pay == true && mounted) {
        final rows = await Repo.shopProducts(shopId);
        final id = rows.first['id'] as String;
        if (mounted) await payAndOpen(context, 'bazar_listing', id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Publier au Bazar', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: C.mint.withValues(alpha: .6), borderRadius: BorderRadius.circular(20)),
            child: FutureBuilder<int?>(
              future: fee,
              builder: (_, s) => Text("Annonce de particulier : ${feeText(s.data, '2')} pour 14 jours, renouvelable. Sans renouvellement, elle est bloquée puis supprimée après 30 jours. Les acheteurs peuvent payer et se faire livrer comme dans la Marketplace.", style: const TextStyle(color: C.ink, fontSize: 16, height: 1.4, fontWeight: FontWeight.w600)),
            ),
          ),
          Field(title, "Titre de l'article"),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: cats,
            builder: (_, cs) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: [for (final c in cs.data ?? []) DropdownMenuItem(value: c['id'] as String, child: Text('${c['name']}'))],
                onChanged: (v) => catId = v,
              ),
            ),
          ),
          Field(desc, 'Description (état, taille, couleur…)'),
          Field(price, 'Prix en HTG', type: TextInputType.number),
          Field(qty, 'Quantité disponible', type: TextInputType.number),
          Field(city, 'Ville'),
          ImageUploadField(onUrl: (u) => img = u),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Afficher ma position approximative sur la carte du Bazar'), value: shareLoc, onChanged: (v) => setState(() => shareLoc = v)),
          const SizedBox(height: 8),
          PrimaryButton(label: busy ? 'Enregistrement…' : "Enregistrer l'annonce", icon: Icons.local_offer, onPressed: busy ? null : submit),
        ]),
      );
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});
  Widget card(String title, String a, String b) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
          const SizedBox(height: 10),
          Text('En attente : $a', style: const TextStyle(color: C.muted, fontSize: 16)),
          Text('Disponible à verser : $b', style: const TextStyle(color: C.green, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        const Padding(padding: EdgeInsets.only(bottom: 18), child: Text('Portefeuille', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1))),
        if (currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour voir vos soldes.')
        else
          FutureBuilder<Map<String, dynamic>>(
            future: Repo.myWallet(),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) return const EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.');
              final d = s.data!;
              String m(String k) => money((d[k] as num), 'HTG');
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                card('Ventes (vendeur)', m('seller_pending'), m('seller_available')),
                card('Livraisons (livreur)', m('courier_pending'), m('courier_available')),
                const Text("Ces soldes sont calculés à partir des commandes réellement payées. « Disponible » signifie livré et confirmé. Le versement vers votre portefeuille MonCash est effectué après validation par HAITIKET ; il n'est pas encore automatique.", style: TextStyle(color: C.muted, height: 1.4)),
              ]);
            },
          ),
      ]);
}
