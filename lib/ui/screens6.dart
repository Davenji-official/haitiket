import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens5.dart';
import 'widgets.dart';
import 'mascot.dart';

/// Paiement Bazar par portefeuille interne USD, sans redirection vers un prestataire externe.
Future<void> payBazarFromWallet(BuildContext context, String productId) async {
  try {
    await Repo.payBazarListingFromWallet(productId);
    if (context.mounted) toast(context, 'Annonce payée en USD et publiée pour 14 jours.');
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}

String usdFeeText(double? amount, String fallback) => amount == null ? 'Tarif indisponible (paiement bloqué)' : '\$${amount.toStringAsFixed(2)} USD';

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
      child: FutureBuilder<double?>(
        future: Repo.quoteWalletFeeUsd('shop_plan'),
        builder: (_, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valid ? "Abonnement actif jusqu’au ${until!.substring(0, 10)}" : 'Abonnement boutique non payé', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
          Text('Tarif mensuel : ${usdFeeText(s.data, '20')}', style: const TextStyle(color: C.muted)),
          const SizedBox(height: 8),
          PrimaryButton(
            label: valid ? 'Abonnement actif' : "Payer l'abonnement avec le portefeuille USD",
            icon: Icons.account_balance_wallet_outlined,
            onPressed: s.data == null || valid ? null : () async {
              try {
                await Repo.payShopPlanFromWallet(shop['id'] as String);
                if (context.mounted) toast(context, 'Abonnement payé depuis le portefeuille USD.');
              } catch (e) {
                if (context.mounted) toast(context, Repo.err(e));
              }
            },
          ),
          const SizedBox(height: 10),
          FutureBuilder<double?>(
            future: Repo.quoteWalletFeeUsd('shop_plan_yearly'),
            builder: (_, annual) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tarif annuel : ${usdFeeText(annual.data, '200')} USD', style: const TextStyle(color: C.muted)),
              const SizedBox(height: 6),
              PrimaryButton(
                label: valid ? 'Abonnement actif' : 'Payer l’abonnement annuel (365 jours)',
                icon: Icons.calendar_month_outlined,
                onPressed: annual.data == null || valid ? null : () async {
                  try {
                    await Repo.payShopPlanFromWallet(shop['id'] as String, period: 'yearly');
                    if (context.mounted) toast(context, 'Abonnement annuel payé depuis le portefeuille USD.');
                  } catch (e) {
                    if (context.mounted) toast(context, Repo.err(e));
                  }
                },
              ),
            ]),
          ),
          const Text('Le débit est effectué côté serveur. Aucun change automatique depuis le portefeuille HTG. Le renouvellement anticipé est désactivé tant que l’abonnement est actif.', style: TextStyle(color: C.muted, fontSize: 12)),
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

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late Future<Map<String, dynamic>> future = Repo.myWalletV2();
  final amount = TextEditingController();
  final phone = TextEditingController();
  final withdrawAmount = TextEditingController();
  final withdrawPhone = TextEditingController();
  String method = 'moncash';
  String topupCurrency = 'HTG';
  late Future<double?> rateFuture = Repo.walletExchangeRate();
  late Future<double?> withdrawRateFuture = Repo.walletWithdrawExchangeRate();
  String withdrawMethod = 'moncash';
  String withdrawCurrency = 'HTG';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    amount.addListener(_amountChanged);
    // Retour de la page de paiement : vérification automatique des recharges en attente.
    if (Uri.base.path.contains('/payment/') || Uri.base.queryParameters.containsKey('refference_id') || Uri.base.queryParameters.containsKey('id_transaction')) {
      _afterPaymentReturn();
    }
  }
  Future<void> _afterPaymentReturn() async {
    try {
      final n = await Repo.checkPendingTopups();
      if (!mounted) return;
      reload();
      toast(context, n > 0 ? 'Recharge confirmée : votre solde est à jour.' : 'Paiement en cours de confirmation par Plop Plop. Le solde sera mis à jour dès réception.');
    } catch (_) {}
  }
  void _amountChanged() { if (mounted) setState(() {}); }
  @override
  void dispose() { amount.removeListener(_amountChanged); amount.dispose(); phone.dispose(); withdrawAmount.dispose(); withdrawPhone.dispose(); super.dispose(); }
  void reload() => setState(() { future = Repo.myWalletV2(); rateFuture = Repo.walletExchangeRate(); withdrawRateFuture = Repo.walletWithdrawExchangeRate(); });
  Future<void> topup() async {
    final v = double.tryParse(amount.text.replaceAll(',', '.'));
    if (v == null || v < (topupCurrency == 'USD' ? 1 : 20)) return toast(context, 'Montant minimum : ${topupCurrency == 'USD' ? '1 USD' : '20 HTG'}.');
    if (method.endsWith('_ussd') && !RegExp(r'^509\d{8}$').hasMatch(phone.text.trim())) return toast(context, 'Entre un numéro haïtien au format 509XXXXXXXX.');
    setState(() => busy = true);
    try {
      final result = await Repo.startWalletTopup((v * 100).round(), topupCurrency, method, phone: phone.text.trim());
      final redirect = result['redirect_url']?.toString();
      if (redirect != null && redirect.isNotEmpty) {
        final ok = await launchUrl(Uri.parse(redirect), mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication, webOnlyWindowName: '_self');
        if (!ok && mounted) toast(context, 'Paiement créé, mais impossible d’ouvrir la page de paiement. Référence : ${result['reference']}');
      } else if (mounted) {
        toast(context, 'Demande de recharge créée. Confirme le code USSD sur ton téléphone. Référence : ${result['reference']}');
      }
      amount.clear();
      if (mounted) await showDialog<void>(context: context, builder: (d) => AlertDialog(title: const Text('Vérifier la recharge'), content: Text('Référence : ${result['reference']}\nMontant à créditer : ${(result['wallet_amount_minor'] as num? ?? (v * 100).round()) / 100} $topupCurrency\nMontant demandé par Plop Plop : ${((result['provider_amount_minor'] as num? ?? (v * 100).round()) / 100).toStringAsFixed(2)} HTG\nAprès avoir confirmé le paiement, appuie sur « Vérifier ». Le solde ne sera crédité qu’après confirmation de Plop Plop.'), actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fermer')), FilledButton(onPressed: () async { try { final st = await Repo.checkWalletTopup(result['reference'].toString()); if (d.mounted) Navigator.pop(d); if (mounted) toast(context, st == 'successful' ? 'Recharge confirmée.' : 'Statut : $st'); reload(); } catch(e) { if (mounted) toast(context, Repo.err(e)); } }, child: const Text('Vérifier'))]));
      reload();
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> withdraw() async {
    final v = double.tryParse(withdrawAmount.text.replaceAll(',', '.'));
    final ph = withdrawPhone.text.trim();
    final minimum = withdrawCurrency == 'USD' ? 1.0 : 50.0;
    if (v == null || v < minimum) return toast(context, 'Le retrait minimum est de ${withdrawCurrency == 'USD' ? '1 USD' : '50 HTG'}.');
    if (!RegExp(r'^509\d{8}$').hasMatch(ph)) return toast(context, 'Entre un numéro haïtien au format 509XXXXXXXX.');
    final confirmed = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Confirmer le retrait'),
      content: Text('Demander le retrait de ${v.toStringAsFixed(2)} $withdrawCurrency vers $ph par ${withdrawMethod == 'moncash' ? 'MonCash' : 'NatCash'} ? ${withdrawCurrency == 'USD' ? 'Le montant sera converti en HTG au taux de retrait configuré par l’administration.' : ''} Le montant peut rester temporairement réservé si le fournisseur ne confirme pas immédiatement.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmer'))],
    ));
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      final result = await Repo.withdrawWallet((v * 100).round(), withdrawCurrency, withdrawMethod, ph);
      final ref = result['reference']?.toString() ?? '';
      final status = result['status']?.toString() ?? 'processing';
      if (mounted) await showDialog<void>(context: context, builder: (d) => AlertDialog(
        title: Text(status == 'successful' ? 'Retrait confirmé' : status == 'failed' ? 'Retrait échoué' : 'Retrait en vérification'),
        content: Text('${result['message'] ?? result['error'] ?? 'Statut : $status'}\nRéférence : $ref\nNe soumets pas un deuxième retrait pour remplacer celui-ci tant que son statut n’est pas confirmé.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fermer')), if (status == 'processing') FilledButton(onPressed: () async { try { final st = await Repo.checkWalletWithdrawal(ref); if (d.mounted) Navigator.pop(d); if (mounted) toast(context, 'Statut du retrait : $st'); reload(); } catch(e) { if (mounted) toast(context, Repo.err(e)); } }, child: const Text('Vérifier'))],
      ));
      withdrawAmount.clear();
      reload();
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
    if (mounted) setState(() => busy = false);
  }

  Widget card(String title, String value) => Container(margin: const EdgeInsets.only(bottom: 12),padding: const EdgeInsets.all(18),decoration: BoxDecoration(color: Colors.white,borderRadius: BorderRadius.circular(20),border: Border.all(color:C.line)),child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w800,color:C.ink)),const SizedBox(height:8),Text(value,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800,color:C.green))]));
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const MascotHeader(mascot: Mascot.wallet, title: 'Portefeuille HAITIKET', subtitle: 'Ajoutez, gardez et retirez votre argent en sécurité.'),
    if(currentUser()==null) const EmptyState(title:'Connexion requise',text:'Connecte-toi pour utiliser le portefeuille.') else ...[
      FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return ErrorState(s.error);final d=s.data??{};final balances=(d['balances'] as Map?)??{};String bal(String c)=>money(((balances[c] as num?)??0),c);return Column(children:[card('Solde disponible · HTG',bal('HTG')),card('Solde disponible · USD',bal('USD'))]);}),
      const SizedBox(height:8), const Text('Ajouter de l’argent par MonCash ou NatCash',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:C.ink)),
      DropdownButtonFormField<String>(value:topupCurrency,decoration:const InputDecoration(labelText:'Devise à créditer'),items:const [DropdownMenuItem(value:'HTG',child:Text('Portefeuille HTG')),DropdownMenuItem(value:'USD',child:Text('Portefeuille USD'))],onChanged:busy?null:(v)=>setState(()=>topupCurrency=v??'HTG')),
      Field(amount,'Montant à créditer en $topupCurrency'),
      if (topupCurrency == 'USD') FutureBuilder<double?>(future:rateFuture,builder:(context,rateState){final rate=rateState.data;final value=double.tryParse(amount.text.replaceAll(',', '.'));final converted=rate!=null&&value!=null&&value>0?(value*rate):null;return Container(margin:const EdgeInsets.only(top:6,bottom:8),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:C.mint,borderRadius:BorderRadius.circular(12)),child:Text(rateState.connectionState!=ConnectionState.done?'Chargement du taux officiel HAITIKET…':rate==null?'Taux USD → HTG non configuré. La recharge USD est indisponible.': 'Taux fixé par l’administration : 1 USD = ${rate.toStringAsFixed(4)} HTG\nMontant estimé payé en HTG : ${converted==null?'—':converted.toStringAsFixed(2)} HTG. Le montant final est calculé côté serveur.',style:const TextStyle(color:C.ink,height:1.4)));}),
      DropdownButtonFormField<String>(value:method,decoration:const InputDecoration(labelText:'Méthode de paiement'),items:const [DropdownMenuItem(value:'moncash',child:Text('MonCash — page de paiement')),DropdownMenuItem(value:'natcash',child:Text('NatCash — page de paiement')),DropdownMenuItem(value:'moncash_ussd',child:Text('MonCash USSD')),DropdownMenuItem(value:'natcash_ussd',child:Text('NatCash USSD'))],onChanged:(v)=>setState(()=>method=v??'moncash')),
      if(method.endsWith('_ussd')) Field(phone,'Téléphone haïtien (509XXXXXXXX)'),
      const SizedBox(height:10),PrimaryButton(label:busy?'Préparation…':'Ajouter de l’argent',icon:Icons.add_card,onPressed:busy?null:topup),
      const SizedBox(height:22),
      const Text('Retirer vers MonCash ou NatCash',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:C.ink)),
      const SizedBox(height:6),
      const Text('Le retrait USD est converti en HTG au taux configuré par l’administration. Minimum : 1 USD ou 50 HTG. Le fournisseur doit confirmer le transfert et disposer du solde marchand nécessaire.',style:TextStyle(color:C.muted,height:1.4)),
      DropdownButtonFormField<String>(value:withdrawCurrency,decoration:const InputDecoration(labelText:'Devise à retirer'),items:const [DropdownMenuItem(value:'HTG',child:Text('Portefeuille HTG')),DropdownMenuItem(value:'USD',child:Text('Portefeuille USD'))],onChanged:busy?null:(v)=>setState(()=>withdrawCurrency=v??'HTG')),
      Field(withdrawAmount,'Montant à retirer ($withdrawCurrency)'),
      if (withdrawCurrency == 'USD') FutureBuilder<double?>(future:withdrawRateFuture,builder:(context,rateState){final rate=rateState.data;final value=double.tryParse(withdrawAmount.text.replaceAll(',', '.'));final converted=rate!=null&&value!=null&&value>0?value*rate:null;return Padding(padding:const EdgeInsets.only(top:4,bottom:8),child:Text(rate==null?'Taux USD → HTG pour les retraits non configuré.': 'Taux de retrait : 1 USD = ${rate.toStringAsFixed(4)} HTG\nMontant estimé reçu en HTG : ${converted?.toStringAsFixed(2) ?? '—'} HTG',style:const TextStyle(color:C.muted)));}),
      Field(withdrawPhone,'Numéro destinataire (509XXXXXXXX)',type:TextInputType.phone),
      DropdownButtonFormField<String>(value:withdrawMethod,decoration:const InputDecoration(labelText:'Recevoir par'),items:const [DropdownMenuItem(value:'moncash',child:Text('MonCash')),DropdownMenuItem(value:'natcash',child:Text('NatCash'))],onChanged:(v)=>setState(()=>withdrawMethod=v??'moncash')),
      const SizedBox(height:10),PrimaryButton(label:busy?'Traitement…':'Demander un retrait',icon:Icons.payments_outlined,onPressed:busy?null:withdraw),
      const SizedBox(height:10),
      const Text('Les achats, abonnements et revenus des ventes/livraisons doivent encore être reliés au portefeuille dans les flux métier. Ne considère pas le portefeuille comme prêt à la production avant validation du rapprochement Plop Plop et des tests réels.',style:TextStyle(color:C.muted,height:1.45)),
      const SizedBox(height:10),OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Actualiser le portefeuille')),
    ]
  ]);
}
