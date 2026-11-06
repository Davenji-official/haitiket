import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'live_charts.dart';
import 'screens5.dart';
import 'widgets.dart';

SupabaseClient get _db => Supabase.instance.client;

num _n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);

Future<List<Map<String, dynamic>>> _rows(String fn, [Map<String, dynamic>? p]) async {
  final r = await _db.rpc(fn, params: p);
  return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

// ---------------------------------------------------------------------------
// Revenus de HAITIKET en direct
// ---------------------------------------------------------------------------
class AdminRevenuePage extends StatefulWidget {
  const AdminRevenuePage({super.key});
  @override
  State<AdminRevenuePage> createState() => _AdminRevenuePageState();
}

class _AdminRevenuePageState extends State<AdminRevenuePage> {
  int days = 30;
  Map<String, dynamic>? data;
  String? error;
  Timer? timer, clock;
  DateTime? updated;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => load());
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    clock?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await _db.rpc('admin_revenue_live', params: {'p_days': days});
      if (!mounted) return;
      setState(() {
        data = Map<String, dynamic>.from(r as Map);
        error = null;
        updated = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => error = Repo.err(e));
    }
  }

  Map<String, dynamic> cur(String section, String c) {
    final m = (data?[section] as Map?)?[c];
    return m == null ? <String, dynamic>{} : Map<String, dynamic>.from(m as Map);
  }

  Widget kpi(String label, num minor, String currency, IconData icon, {Color? color, String? sub}) => Container(
        width: 190,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 18, color: color ?? C.green), const SizedBox(width: 6), Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: C.muted)))]),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: minor.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text('${(v / 100).toStringAsFixed(2)} $currency', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: C.ink)),
          ),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: C.muted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (error != null && data == null) return EmptyState(title: 'Accès refusé ou migration manquante', text: '$error\n(Exécutez la migration 0069 dans Supabase.)');
    final d = data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final oH = cur('orders', 'HTG'), oU = cur('orders', 'USD');
    final offH = cur('official', 'HTG'), offU = cur('official', 'USD');
    final subs = _n(d['subscriptions_usd_minor']), bazar = _n(d['bazar_usd_minor']);
    final totalHtg = _n(oH['platform_net_earned']);
    final totalUsd = _n(oU['platform_net_earned']) + subs + bazar;
    final byDay = ((d['by_day'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final labels = [for (final r in byDay) '${r['day']}'.length >= 10 ? '${r['day']}'.substring(5, 10) : '${r['day']}'];
    List<double> col(String k) => [for (final r in byDay) _n(r[k]).toDouble() / 100];
    final secs = updated == null ? 0 : DateTime.now().difference(updated!).inSeconds;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Row(children: [
          Icon(Icons.circle, size: 11, color: const Color(0xFF25D366)),
          const SizedBox(width: 6),
          Expanded(child: Text('Revenus HAITIKET · en direct', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink))),
          Text('mis à jour il y a $secs s', style: TextStyle(color: C.muted, fontSize: 12)),
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
        ]),
        Text('Actualisation automatique toutes les 10 s. Commissions comptées à la livraison/remise confirmée ; abonnements et annonces Bazar à l’encaissement.', style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [for (final x in const [1, 7, 30, 90, 365]) ChoiceChip(label: Text(x == 1 ? "Aujourd'hui" : '$x jours'), selected: days == x, onSelected: (_) { days = x; load(); })]),
        const SizedBox(height: 10),
        Text('Total gagné par HAITIKET', style: TextStyle(fontWeight: FontWeight.w900, color: C.ink, fontSize: 16)),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 10, children: [
          kpi('Total HTG (commissions nettes)', totalHtg, 'HTG', Icons.account_balance_wallet_outlined, color: C.terracotta),
          kpi('Total USD (commissions + abonnements + Bazar)', totalUsd, 'USD', Icons.account_balance_outlined, color: C.terracotta),
        ]),
        const SizedBox(height: 12),
        Text('Détail', style: TextStyle(fontWeight: FontWeight.w900, color: C.ink, fontSize: 16)),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 10, children: [
          kpi('Commissions gagnées HTG', _n(oH['commission_earned']), 'HTG', Icons.percent, sub: '${_n(oH['orders_paid'])} commandes payées'),
          kpi('Commissions gagnées USD', _n(oU['commission_earned']), 'USD', Icons.percent, sub: '${_n(oU['orders_paid'])} commandes payées'),
          kpi('À venir HTG (en cours)', _n(oH['commission_pending']), 'HTG', Icons.hourglass_top, color: C.yellow),
          kpi('À venir USD (en cours)', _n(oU['commission_pending']), 'USD', Icons.hourglass_top, color: C.yellow),
          kpi('Abonnements boutiques', subs, 'USD', Icons.storefront_outlined, sub: '${_n(d['subscriptions_count'])} paiements'),
          kpi('Annonces Bazar', bazar, 'USD', Icons.sell_outlined, sub: '${_n(d['bazar_count'])} annonces'),
          kpi('Ventes boutique officielle HTG', _n(offH['sales_minor']), 'HTG', Icons.verified_outlined, sub: '${_n(offH['orders'])} commandes'),
          kpi('Ventes boutique officielle USD', _n(offU['sales_minor']), 'USD', Icons.verified_outlined, sub: '${_n(offU['orders'])} commandes'),
          kpi('Volume de ventes HTG', _n(oH['gmv_minor']), 'HTG', Icons.shopping_bag_outlined, color: C.muted),
          kpi('Volume de ventes USD', _n(oU['gmv_minor']), 'USD', Icons.shopping_bag_outlined, color: C.muted),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (_, c) {
          final two = c.maxWidth > 760;
          final w = two ? (c.maxWidth - 10) / 2 : c.maxWidth;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: w, child: LiveChart(title: 'Commissions HTG par jour', series: [ChartSeries('HTG', C.terracotta, col('commission_htg'))], labels: labels, bars: true, fmt: (v) => '${v.toStringAsFixed(2)} HTG')),
            SizedBox(width: w, child: LiveChart(title: 'Commissions USD par jour', series: [ChartSeries('USD', const Color(0xFF3B6FD4), col('commission_usd'))], labels: labels, bars: true, fmt: (v) => '${v.toStringAsFixed(2)} USD')),
            SizedBox(width: w, child: LiveChart(title: 'Abonnements et Bazar (USD)', series: [ChartSeries('Abonnements', C.green, col('subscriptions_usd')), ChartSeries('Bazar', C.yellow, col('bazar_usd'))], labels: labels, fmt: (v) => '${v.toStringAsFixed(2)} USD')),
            SizedBox(width: w, child: LiveChart(title: 'Ventes boutique officielle', series: [ChartSeries('HTG', C.green, col('official_htg')), ChartSeries('USD', const Color(0xFF3B6FD4), col('official_usd'))], labels: labels)),
          ]);
        }),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Commissions : taux par défaut + règles par produit / catégorie / boutique
// ---------------------------------------------------------------------------
class AdminCommissionsPage extends StatefulWidget {
  const AdminCommissionsPage({super.key});
  @override
  State<AdminCommissionsPage> createState() => _AdminCommissionsPageState();
}

class _AdminCommissionsPageState extends State<AdminCommissionsPage> {
  late Future<List<Map<String, dynamic>>> rules = _rows('admin_list_commission_rules');
  late Future<List<Map<String, dynamic>>> settings = _rows('admin_list_settings');
  void reload() => setState(() {
        rules = _rows('admin_list_commission_rules');
        settings = _rows('admin_list_settings');
      });

  static const _scopeLabels = {'product': 'Produit', 'category': 'Catégorie', 'shop': 'Boutique'};

  Future<void> editDefault(int currentBps) async {
    final v = await askText(context, 'Commission par défaut (%)', hint: 'ex. 2 ou 2.5', type: const TextInputType.numberWithOptions(decimal: true));
    if (v == null) return;
    final pct = double.tryParse(v.replaceAll(',', '.'));
    if (pct == null || pct < 0 || pct > 100) return toast(context, 'Pourcentage invalide (0 à 100).');
    try {
      await _db.rpc('admin_set_setting_any', params: {'p_key': 'commission_bps', 'p_value': '${(pct * 100).round()}'});
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<Map<String, dynamic>?> pickTarget(String scope) async {
    if (scope == 'category') {
      final r = await _db.from('categories').select('id,name').order('name');
      final l = List<Map<String, dynamic>>.from(r);
      if (!mounted) return null;
      return showDialog<Map<String, dynamic>>(
        context: context,
        builder: (d) => SimpleDialog(title: const Text('Choisir une catégorie'), children: [for (final c in l) SimpleDialogOption(onPressed: () => Navigator.pop(d, c), child: Text('${c['name']}'))]),
      );
    }
    final q = TextEditingController();
    List<Map<String, dynamic>> res = [];
    Future<void> search(StateSetter set) async {
      try {
        res = scope == 'product'
            ? (await _rows('admin_search_products', {'p_q': q.text.trim(), 'p_status': 'published', 'p_limit': 30})).map((e) => {'id': e['id'], 'name': '${e['name']} · ${e['shop_name']}'}).toList()
            : (await _rows('admin_search_shops', {'p_q': q.text.trim()})).map((e) => {'id': e['id'], 'name': '${e['name']}${e['is_official'] == true ? ' (officielle)' : ''}'}).toList();
      } catch (_) {
        res = [];
      }
      set(() {});
    }

    if (!mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, set) {
        if (res.isEmpty && q.text.isEmpty) search(set);
        return AlertDialog(
          title: Text(scope == 'product' ? 'Choisir un produit' : 'Choisir une boutique'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: Column(children: [
              TextField(controller: q, onChanged: (_) => search(set), decoration: const InputDecoration(labelText: 'Rechercher', prefixIcon: Icon(Icons.search))),
              Expanded(child: ListView(children: [for (final r in res) ListTile(dense: true, title: Text('${r['name']}'), onTap: () => Navigator.pop(d, r))])),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler'))],
        );
      }),
    );
  }

  Future<void> addRule() async {
    String scope = 'product';
    final pct = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Nouvelle règle de commission'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(value: scope, decoration: const InputDecoration(labelText: 'S’applique à'), items: [for (final e in _scopeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => set(() => scope = v ?? 'product')),
            TextField(controller: pct, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Commission (%)', hintText: 'ex. 3.5')),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (facultatif)')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Choisir la cible'))],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final p = double.tryParse(pct.text.replaceAll(',', '.'));
    if (p == null || p < 0 || p > 100) return toast(context, 'Pourcentage invalide (0 à 100).');
    final target = await pickTarget(scope);
    if (target == null) return;
    try {
      await _db.rpc('admin_upsert_commission_rule', params: {'p_scope': scope, 'p_target': target['id'], 'p_bps': (p * 100).round(), 'p_note': note.text, 'p_active': true});
      if (mounted) toast(context, 'Règle enregistrée : appliquée aux prochaines commandes.');
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> toggle(Map<String, dynamic> r) async {
    try {
      await _db.rpc('admin_upsert_commission_rule', params: {'p_scope': r['scope'], 'p_target': r['target_id'], 'p_bps': r['bps'], 'p_note': r['note'], 'p_active': !(r['active'] == true)});
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> remove(Map<String, dynamic> r) async {
    try {
      await _db.rpc('admin_delete_commission_rule', params: {'p_id': r['id']});
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        Text('Commissions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink)),
        Text('Priorité : règle produit > règle catégorie > règle boutique > taux par défaut. Mettez 0 % sur la boutique officielle pour l’exempter. Les règles s’appliquent aux NOUVELLES commandes ; les commandes existantes gardent leur taux.', style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: settings,
          builder: (_, s) {
            final l = s.data ?? [];
            final row = l.where((r) => r['key'] == 'commission_bps');
            final bps = row.isEmpty ? 200 : int.tryParse('${row.first['value']}') ?? 200;
            return Card(
              color: C.card,
              child: ListTile(
                leading: Icon(Icons.percent, color: C.green),
                title: Text('Taux par défaut : ${(bps / 100).toStringAsFixed(2)} %', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Appliqué quand aucune règle ne correspond.'),
                trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => editDefault(bps)),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        FilledButton.icon(onPressed: addRule, icon: const Icon(Icons.add), label: const Text('Ajouter une règle')),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: rules,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return EmptyState(title: 'Erreur', text: '${Repo.err(s.error!)}\n(Exécutez la migration 0069.)');
            final l = s.data ?? [];
            if (l.isEmpty) return const EmptyState(title: 'Aucune règle', text: 'Tous les produits utilisent le taux par défaut.');
            return Column(children: [
              for (final r in l)
                Card(
                  color: r['active'] == true ? C.card : C.soft,
                  child: ListTile(
                    leading: Chip(label: Text(_scopeLabels['${r['scope']}'] ?? '${r['scope']}')),
                    title: Text('${r['target_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${(_n(r['bps']) / 100).toStringAsFixed(2)} %${r['note'] != null ? ' · ${r['note']}' : ''}${r['active'] == true ? '' : ' · désactivée'}'),
                    trailing: Wrap(children: [
                      IconButton(tooltip: r['active'] == true ? 'Désactiver' : 'Activer', icon: Icon(r['active'] == true ? Icons.toggle_on : Icons.toggle_off, color: C.green, size: 30), onPressed: () => toggle(r)),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => remove(r)),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ]);
}
