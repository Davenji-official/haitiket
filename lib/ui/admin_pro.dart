import '../media_formats.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'admin_finance.dart';
import 'admin_ops.dart';
import 'live_charts.dart';
import 'admin_screen.dart';
import 'fx.dart';
import 'screens5.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Accès données (RPC sécurisées côté serveur : chaque fonction vérifie admin_unlocked()).
// ---------------------------------------------------------------------------
SupabaseClient get _db => Supabase.instance.client;

Future<List<Map<String, dynamic>>> _rows(String fn, [Map<String, dynamic>? p]) async {
  final r = await _db.rpc(fn, params: p);
  return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Future<Map<String, dynamic>> _obj(String fn, [Map<String, dynamic>? p]) async =>
    Map<String, dynamic>.from(await _db.rpc(fn, params: p) as Map);

num _n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);

String _ago(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return 'jamais';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  return 'il y a ${diff.inDays} j';
}

String _date(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '—';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

Future<bool> _confirm(BuildContext c, String title, String text) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmer')),
        ],
      ),
    ) ??
    false;

// ---------------------------------------------------------------------------
// Prise de contrôle d'un compte (support). Journalisée ; la session admin est restaurable.
// ---------------------------------------------------------------------------
class AdminImpersonation {
  static final ValueNotifier<String?> active = ValueNotifier<String?>(null);
  static String? _adminRefreshToken;
  static String? _targetId;

  static Future<void> start(BuildContext c, String userId, String label) async {
    final reason = await askText(c, 'Motif de la prise de contrôle', hint: 'Obligatoire (ex. ticket support #123)');
    if (reason == null || reason.trim().length < 5) {
      if (c.mounted && reason != null) toast(c, 'Motif trop court (5 caractères minimum).');
      return;
    }
    if (!c.mounted) return;
    final ok = await _confirm(c, 'Prendre le contrôle ?',
        'Vous serez connecté comme « $label ». Cette action est enregistrée dans le journal admin avec votre identité et le motif. Aucune action financière ne doit être faite sans accord du client.');
    if (!ok || !c.mounted) return;
    try {
      final res = await _db.functions.invoke('admin-impersonate', body: {'user_id': userId, 'reason': reason.trim()});
      final data = res.data;
      if (data is! Map || data['token_hash'] == null) throw 'Réponse invalide du serveur';
      _adminRefreshToken = _db.auth.currentSession?.refreshToken;
      await _db.auth.verifyOTP(tokenHash: '${data['token_hash']}', type: OtpType.magiclink);
      _targetId = userId;
      active.value = label;
      if (data['was_banned'] == true && c.mounted) toast(c, 'Compte bloqué/supprimé : accès temporaire de 20 minutes, blocage rétabli à la sortie.');
      if (c.mounted) Navigator.of(c).popUntil((r) => r.isFirst);
    } on FunctionException catch (e) {
      final d = e.details;
      var msg = d is Map && d['error'] != null ? '${d['error']}' : '$d';
      if (e.status == 404) {
        msg = 'La fonction « admin-impersonate » n’est pas déployée sur Supabase (commande : supabase functions deploy admin-impersonate).';
      } else if (msg.contains('admin_begin_support_session') || msg.contains('admin_log_impersonation')) {
        msg = 'La migration SQL 0067 n’a pas été exécutée dans Supabase.';
      } else if (msg.contains('verrouill') || msg.contains('admin_console_locked')) {
        msg = 'Console admin verrouillée : déverrouillez-la avec votre code.';
      }
      if (c.mounted) toast(c, msg);
    } catch (e) {
      if (c.mounted) toast(c, Repo.err(e));
    }
  }

  static Future<void> exit(BuildContext c) async {
    final t = _adminRefreshToken;
    try {
      if (t != null) {
        await _db.auth.setSession(t);
      } else {
        await _db.auth.signOut();
      }
    } catch (e) {
      if (c.mounted) toast(c, 'Session admin expirée : reconnectez-vous. (${Repo.err(e)})');
      await _db.auth.signOut();
    }
    final target = _targetId;
    if (target != null) {
      try {
        await _db.rpc('admin_end_support_session', params: {'p_user': target});
      } catch (_) {}
    }
    _targetId = null;
    _adminRefreshToken = null;
    active.value = null;
  }
}

/// Bandeau rouge affiché en haut de l'application pendant une prise de contrôle.
class ImpersonationBanner extends StatelessWidget {
  const ImpersonationBanner({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: AdminImpersonation.active,
        builder: (_, who, __) => who == null
            ? const SizedBox.shrink()
            : Material(
                color: const Color(0xFFB3261E),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.admin_panel_settings, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Mode support : connecté en tant que $who', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                    TextButton(
                      style: TextButton.styleFrom(backgroundColor: C.card),
                      onPressed: () => AdminImpersonation.exit(context),
                      child: const Text('Quitter', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w900)),
                    ),
                  ]),
                ),
              ),
      );
}

// ---------------------------------------------------------------------------
// Graphiques (sans dépendance externe)
// ---------------------------------------------------------------------------
typedef _Series = ChartSeries;

class _ChartCard extends StatelessWidget {
  final String title, subtitle;
  final List<ChartSeries> series;
  final bool bars;
  final List<String> labels;
  const _ChartCard({required this.title, required this.series, required this.labels, this.subtitle = '', this.bars = false});

  @override
  Widget build(BuildContext context) => LiveChart(title: title, subtitle: subtitle, series: series, labels: labels, bars: bars);
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const _Kpi(this.label, this.value, this.icon, {this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 165,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Row(children: [
          Icon(icon, color: color ?? C.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink)),
              Text(label, style: TextStyle(fontSize: 11, color: C.muted)),
            ]),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Console principale
// ---------------------------------------------------------------------------
class AdminPro extends StatefulWidget {
  const AdminPro({super.key});
  @override
  State<AdminPro> createState() => _AdminProState();
}

class _AdminProState extends State<AdminPro> {
  int idx = 0;
  static const _items = <(String, IconData)>[
    ('Analytique', Icons.insights_outlined),
    ('Revenus', Icons.payments_outlined),
    ('Commissions', Icons.percent),
    ('Recharges', Icons.sync_alt),
    ('Carte live', Icons.map_outlined),
    ('Clients', Icons.people_alt_outlined),
    ('Commandes', Icons.receipt_long_outlined),
    ('Catalogue', Icons.inventory_2_outlined),
    ('Logistique', Icons.local_shipping_outlined),
    ('Antifraude', Icons.shield_outlined),
    ('Diffusion', Icons.campaign_outlined),
    ('Réglages', Icons.tune),
    ('Modules', Icons.apps_outlined),
  ];

  Widget page() {
    switch (idx) {
      case 0:
        return const _AnalyticsPage();
      case 1:
        return const AdminRevenuePage();
      case 2:
        return const AdminCommissionsPage();
      case 3:
        return const AdminTopupsPage();
      case 4:
        return const AdminLiveMapPage();
      case 5:
        return const _ClientsPage();
      case 6:
        return const _OrdersPage();
      case 7:
        return const _CatalogPage();
      case 8:
        return const AdminLogisticsPage();
      case 9:
        return const AdminFraudPage();
      case 10:
        return const _BroadcastPage();
      case 11:
        return const _SettingsPage();
      default:
        return const AdminScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    if (wide) {
      return Row(children: [
        NavigationRail(
          selectedIndex: idx,
          onDestinationSelected: (i) => setState(() => idx = i),
          labelType: NavigationRailLabelType.all,
          backgroundColor: C.bg,
          destinations: [for (final it in _items) NavigationRailDestination(icon: Icon(it.$2), label: Text(it.$1))],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: KeyedSubtree(key: ValueKey(idx), child: page())),
      ]);
    }
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                avatar: Icon(_items[i].$2, size: 18),
                label: Text(_items[i].$1),
                selected: idx == i,
                onSelected: (_) => setState(() => idx = i),
              ),
            ),
        ]),
      ),
      Expanded(child: KeyedSubtree(key: ValueKey(idx), child: page())),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 1. Analytique
// ---------------------------------------------------------------------------
class _AnalyticsPage extends StatefulWidget {
  const _AnalyticsPage();
  @override
  State<_AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<_AnalyticsPage> {
  int days = 30;
  Timer? timer;
  List<Map<String, dynamic>>? lastSeries;
  Map<String, dynamic>? lastStats;
  late Future<Map<String, dynamic>> stats = _obj('admin_online_stats');
  late Future<List<Map<String, dynamic>>> series = _rows('admin_timeseries', {'p_days': days});
  late Future<List<Map<String, dynamic>>> breakdown = _rows('admin_order_status_breakdown');

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {
          stats = _obj('admin_online_stats');
          series = _rows('admin_timeseries', {'p_days': days});
          breakdown = _rows('admin_order_status_breakdown');
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void reload() => setState(() {
        stats = _obj('admin_online_stats');
        series = _rows('admin_timeseries', {'p_days': days});
        breakdown = _rows('admin_order_status_breakdown');
      });

  List<double> col(List<Map<String, dynamic>> l, String k, {double div = 1}) => [for (final r in l) _n(r[k]).toDouble() / div];

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => reload(),
        child: ListView(padding: const EdgeInsets.all(14), children: [
          Row(children: [
            Expanded(child: Text('Tableau de bord en temps réel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink))),
            IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
          ]),
          Text('Chiffres issus de la base. « En ligne » = vu il y a moins de 3 minutes. Actualisation automatique toutes les 30 s.', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 10),
          FutureBuilder<Map<String, dynamic>>(
            future: stats,
            builder: (_, s) {
              if (s.hasError) return EmptyState(title: 'Accès refusé', text: Repo.err(s.error!));
              if (s.data != null) lastStats = s.data;
              final d = s.data ?? lastStats;
              if (d == null) return const LinearProgressIndicator();
              String v(String k) => '${_n(d[k]).toInt()}';
              return Wrap(spacing: 10, runSpacing: 10, children: [
                _Kpi('En ligne maintenant', v('online_now'), Icons.circle, color: const Color(0xFF25D366)),
                _Kpi('Actifs (15 min)', v('active_15m'), Icons.bolt),
                _Kpi('Actifs 24 h', v('active_24h'), Icons.today),
                _Kpi('Actifs 7 jours', v('active_7d'), Icons.date_range),
                _Kpi('Actifs 30 jours', v('active_30d'), Icons.calendar_month),
                _Kpi('Inactifs +30 j', v('inactive_30d'), Icons.bedtime_outlined, color: C.muted),
                _Kpi('Utilisateurs', v('total_users'), Icons.people),
                _Kpi('Nouveaux aujourd’hui', v('new_today'), Icons.person_add_alt),
                _Kpi('Nouveaux 7 jours', v('new_7d'), Icons.person_add),
                _Kpi('Comptes bloqués', v('banned'), Icons.block, color: C.terracotta),
                _Kpi('Livreurs en ligne', v('couriers_available'), Icons.two_wheeler),
                _Kpi('Livreurs approuvés', v('couriers_approved'), Icons.badge_outlined),
                _Kpi('Boutiques actives', v('shops_active'), Icons.storefront_outlined),
                _Kpi('Missions ouvertes', v('open_jobs'), Icons.hourglass_top, color: C.terracotta),
                _Kpi('Livraisons en cours', v('jobs_in_progress'), Icons.local_shipping_outlined),
                _Kpi('Commandes en cours', v('orders_in_progress'), Icons.receipt_long_outlined),
              ]);
            },
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            for (final d in const [7, 30, 90, 180])
              ChoiceChip(label: Text('$d jours'), selected: days == d, onSelected: (_) { days = d; reload(); }),
          ]),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: series,
            builder: (_, s) {
              if (s.hasError && lastSeries == null) return Text(Repo.err(s.error!));
              if (s.data != null) lastSeries = s.data;
              final l = s.data ?? lastSeries;
              if (l == null) return const LinearProgressIndicator();
              final labels = [for (final r in l) '${r['day']}'.length >= 10 ? '${r['day']}'.substring(5, 10) : '${r['day']}'];
              double sum(String k, {double div = 1}) => col(l, k, div: div).fold(0.0, (a, b) => a + b);
              return LayoutBuilder(builder: (_, c) {
                final two = c.maxWidth > 760;
                final cards = <Widget>[
                  _ChartCard(title: 'Inscriptions', subtitle: '${sum('signups').toInt()}', series: [_Series('Inscriptions', C.green, col(l, 'signups'))], labels: labels, bars: true),
                  _ChartCard(title: 'Utilisateurs actifs par jour', subtitle: 'max ${col(l, 'active_users').fold<double>(0, (a, b) => a > b ? a : b).toInt()}', series: [_Series('Actifs', C.terracotta, col(l, 'active_users'))], labels: labels),
                  _ChartCard(title: 'Commandes', subtitle: '${sum('orders').toInt()} (${sum('paid_orders').toInt()} payées)', series: [_Series('Créées', C.yellow, col(l, 'orders')), _Series('Payées', C.green, col(l, 'paid_orders'))], labels: labels),
                  _ChartCard(title: 'Ventes HTG (payées)', subtitle: '${sum('gmv_htg', div: 100).toStringAsFixed(0)} HTG', series: [_Series('HTG', C.green, col(l, 'gmv_htg', div: 100))], labels: labels),
                  _ChartCard(title: 'Ventes USD (payées)', subtitle: '${sum('gmv_usd', div: 100).toStringAsFixed(2)} USD', series: [_Series('USD', const Color(0xFF3B6FD4), col(l, 'gmv_usd', div: 100))], labels: labels),
                  _ChartCard(title: 'Commissions gagnées', subtitle: '${sum('commission_htg', div: 100).toStringAsFixed(0)} HTG · ${sum('commission_usd', div: 100).toStringAsFixed(2)} USD', series: [_Series('HTG', C.terracotta, col(l, 'commission_htg', div: 100))], labels: labels, bars: true),
                ];
                return Wrap(spacing: 10, runSpacing: 10, children: [for (final w in cards) SizedBox(width: two ? (c.maxWidth - 10) / 2 : c.maxWidth, child: w)]);
              });
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: breakdown,
            builder: (_, s) {
              final l = s.data;
              if (l == null || l.isEmpty) return const SizedBox.shrink();
              final mx = l.map((r) => _n(r['n']).toDouble()).reduce((a, b) => a > b ? a : b);
              return Card(
                color: C.card,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Commandes par statut', style: TextStyle(fontWeight: FontWeight.w900, color: C.ink)),
                    const SizedBox(height: 8),
                    for (final r in l)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          SizedBox(width: 150, child: Text('${r['status']}', style: const TextStyle(fontSize: 12))),
                          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(minHeight: 12, value: mx == 0 ? 0 : _n(r['n']).toDouble() / mx, color: C.green, backgroundColor: C.mint))),
                          SizedBox(width: 44, child: Text('${r['n']}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
                        ]),
                      ),
                  ]),
                ),
              );
            },
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// 2. Clients : recherche, fiche 360°, prise de contrôle
// ---------------------------------------------------------------------------
class _ClientsPage extends StatefulWidget {
  const _ClientsPage();
  @override
  State<_ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<_ClientsPage> {
  final q = TextEditingController();
  String filter = 'all';
  final List<Map<String, dynamic>> items = [];
  bool loading = false, more = true;
  String? error;

  static const _filters = <(String, String)>[
    ('all', 'Tous'), ('online', 'En ligne'), ('active24', 'Actifs 24 h'), ('inactive', 'Inactifs'),
    ('new', 'Nouveaux'), ('sellers', 'Vendeurs'), ('couriers', 'Livreurs'), ('banned', 'Bloqués'),
  ];

  @override
  void initState() {
    super.initState();
    search(reset: true);
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Future<void> search({bool reset = false}) async {
    if (loading) return;
    if (reset) { items.clear(); more = true; }
    setState(() { loading = true; error = null; });
    try {
      final r = await _rows('admin_search_users_v73', {'p_q': q.text.trim(), 'p_filter': filter, 'p_limit': 30, 'p_offset': items.length});
      items.addAll(r);
      more = r.length == 30;
    } catch (e) {
      error = Repo.err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        TextField(
          controller: q,
          onSubmitted: (_) => search(reset: true),
          decoration: InputDecoration(
            labelText: 'Chercher un client : nom, e-mail, téléphone, WhatsApp, ville ou identifiant',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => search(reset: true)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final f in _filters) ChoiceChip(label: Text(f.$2), selected: filter == f.$1, onSelected: (_) { filter = f.$1; search(reset: true); }),
        ]),
        const SizedBox(height: 8),
        if (error != null) EmptyState(title: 'Erreur', text: error!),
        if (!loading && items.isEmpty && error == null) const EmptyState(title: 'Aucun résultat', text: 'Essayez un autre nom ou retirez le filtre.'),
        for (final u in items) _tile(u),
        if (loading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (!loading && more && items.isNotEmpty) TextButton(onPressed: () => search(), child: const Text('Charger plus')),
      ]);

  Widget _tile(Map<String, dynamic> u) {
    final online = u['online'] == true;
    final blocked = u['account_status'] != 'active' || u['suspended'] == true;
    final url = '${u['avatar_url'] ?? ''}';
    return Card(
      color: blocked ? C.tint : C.card,
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserDetail(userId: u['id'] as String))).then((_) => search(reset: true)),
        leading: Stack(children: [
          CircleAvatar(backgroundColor: C.mint, backgroundImage: url.startsWith('http') ? NetworkImage(url) : null, child: url.startsWith('http') ? null : Icon(Icons.person, color: C.green)),
          Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: online ? const Color(0xFF25D366) : Colors.grey, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
        ]),
        title: Text('${u['display_name'] ?? 'Sans nom'}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${u['email'] ?? ''}\n${u['phone'] ?? 'tél. —'} · ${online ? 'EN LIGNE' : 'vu ${_ago(u['last_seen_at'])}'}'
          '${u['is_courier'] == true ? ' · Livreur' : ''}${_n(u['shops_count']) > 0 ? ' · Vendeur' : ''}${u['is_admin'] == true ? ' · ADMIN' : ''}${blocked ? ' · BLOQUÉ' : ''}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class AdminUserDetail extends StatefulWidget {
  final String userId;
  const AdminUserDetail({super.key, required this.userId});
  @override
  State<AdminUserDetail> createState() => _AdminUserDetailState();
}

class _AdminUserDetailState extends State<AdminUserDetail> {
  late Future<Map<String, dynamic>> f = _obj('admin_user_360', {'p_user': widget.userId});
  late Future<Map<String, dynamic>> fx = _extra();
  Future<Map<String, dynamic>> _extra() async {
    try {
      return await _obj('admin_user_extra', {'p_user': widget.userId});
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void reload() => setState(() {
        f = _obj('admin_user_360', {'p_user': widget.userId});
        fx = _extra();
      });

  Future<void> notifyUser() async {
    final t = TextEditingController(), b = TextEditingController(), l = TextEditingController(), c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Envoyer un message à ce client'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: t, decoration: const InputDecoration(labelText: 'Titre')),
            TextField(controller: b, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
            TextField(controller: l, decoration: const InputDecoration(labelText: 'Lien https:// (optionnel)')),
            TextField(controller: c, decoration: const InputDecoration(labelText: 'Code coupon (optionnel)')),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Envoyer'))],
      ),
    );
    if (ok != true) return;
    await run(() => _db.rpc('admin_notify_user', params: {'p_user': widget.userId, 'p_title': t.text, 'p_body': b.text, 'p_link': l.text, 'p_coupon': c.text}), 'Message envoyé.');
  }

  Future<void> resetPassword(String email) async {
    if (!await _confirm(context, 'Réinitialiser le mot de passe ?', 'Un e-mail de réinitialisation sera envoyé à $email.')) return;
    await run(() => _db.auth.resetPasswordForEmail(email), 'E-mail de réinitialisation envoyé.');
  }

  Future<void> softDelete() async {
    final r = await askText(context, 'Supprimer ce compte (irréversible)', hint: 'Motif obligatoire');
    if (r == null || r.length < 3 || !mounted) return;
    if (!await _confirm(context, 'Confirmer la suppression ?', 'Le compte sera anonymisé et bloqué. Les historiques financiers sont conservés.')) return;
    await run(() => Repo.adminManageUser(widget.userId, 'soft_delete', r), 'Compte supprimé.');
  }

  Future<void> run(Future<void> Function() a, String ok) async {
    try {
      await a();
      if (mounted) toast(context, ok);
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> edit(Map<String, dynamic> p) async {
    final name = TextEditingController(text: '${p['display_name'] ?? ''}');
    final phone = TextEditingController(text: '${p['phone'] ?? ''}');
    final wa = TextEditingController(text: '${p['whatsapp'] ?? ''}');
    final city = TextEditingController(text: '${p['city'] ?? ''}');
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Modifier le profil'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
            TextField(controller: wa, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp')),
            TextField(controller: city, decoration: const InputDecoration(labelText: 'Ville')),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (obligatoire)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true) return;
    await run(() => _db.rpc('admin_update_user_profile', params: {'p_user': widget.userId, 'p_display_name': name.text, 'p_phone': phone.text, 'p_whatsapp': wa.text, 'p_city': city.text, 'p_reason': reason.text}), 'Profil mis à jour.');
  }

  Future<void> setRole(String role, bool grant) async {
    final reason = await askText(context, grant ? 'Donner le rôle « $role »' : 'Retirer le rôle « $role »', hint: 'Motif obligatoire');
    if (reason == null || reason.length < 3) return;
    await run(() => _db.rpc('admin_set_role', params: {'p_user': widget.userId, 'p_role': role, 'p_grant': grant, 'p_reason': reason}), 'Rôle mis à jour.');
  }

  Future<void> ban(bool ban) async {
    var reason = 'Rétablissement administratif';
    if (ban) {
      final r = await askText(context, 'Motif du blocage', hint: 'Obligatoire');
      if (r == null || r.length < 3) return;
      reason = r;
    }
    await run(() => Repo.adminManageUser(widget.userId, ban ? 'ban' : 'unban', reason), ban ? 'Compte bloqué.' : 'Compte réactivé.');
  }

  Widget section(String title, List<Widget> children) => Card(
        color: C.card,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: C.ink, fontSize: 16)),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  Widget kv(String k, Object? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: C.muted))),
          Expanded(child: SelectableText('${v ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Fiche client 360°', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: FutureBuilder<Map<String, dynamic>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return EmptyState(title: 'Erreur', text: Repo.err(s.error!));
            final d = s.data!;
            final p = Map<String, dynamic>.from(d['profile'] as Map);
            final roles = List<String>.from((d['roles'] as List).map((e) => '$e'));
            final isAdmin = roles.contains('admin');
            final blocked = p['account_status'] != 'active' || p['suspended'] == true;
            final selfAccount = _db.auth.currentUser?.id == widget.userId;
            final label = '${p['display_name'] ?? d['email']}';
            final phone = '${p['phone'] ?? ''}';
            final wa = '${p['whatsapp'] ?? ''}'.isEmpty ? phone : '${p['whatsapp']}';
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(padding: const EdgeInsets.all(14), children: [
                  Text(label, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.ink)),
                  Text('${d['email']}', style: TextStyle(color: C.muted)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(onPressed: (isAdmin || selfAccount) ? null : () => AdminImpersonation.start(context, widget.userId, label), icon: const Icon(Icons.login), label: Text(blocked ? 'Prendre le contrôle (accès temporaire 20 min)' : 'Prendre le contrôle'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E))),
                    OutlinedButton.icon(onPressed: () => edit(p), icon: const Icon(Icons.edit_outlined), label: const Text('Modifier')),
                    OutlinedButton.icon(onPressed: selfAccount ? null : () => ban(!blocked), icon: Icon(blocked ? Icons.lock_open : Icons.block), label: Text(blocked ? 'Réactiver' : 'Bloquer')),
                    OutlinedButton.icon(onPressed: phone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: phone)), icon: const Icon(Icons.call), label: const Text('Appeler')),
                    OutlinedButton.icon(onPressed: wa.isEmpty ? null : () { final n = wa.replaceAll(RegExp(r'[^0-9]'), ''); launchUrl(Uri.parse('https://wa.me/${n.length == 8 ? '509$n' : n}'), mode: LaunchMode.externalApplication); }, icon: const Icon(Icons.chat), label: const Text('WhatsApp')),
                    OutlinedButton.icon(onPressed: notifyUser, icon: const Icon(Icons.notifications_active_outlined), label: const Text('Message')),
                    OutlinedButton.icon(onPressed: () => resetPassword('${d['email']}'), icon: const Icon(Icons.lock_reset), label: const Text('Mot de passe')),
                    OutlinedButton.icon(onPressed: selfAccount ? null : softDelete, icon: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent), label: const Text('Supprimer')),
                    OutlinedButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: widget.userId)).then((_) { if (mounted) toast(context, 'Identifiant copié.'); }), icon: const Icon(Icons.copy), label: const Text('ID')),
                  ]),
                  const SizedBox(height: 10),
                  if (selfAccount || isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        selfAccount
                            ? 'C’est VOTRE compte administrateur : prise de contrôle, blocage et suppression sont désactivés (sécurité). Ouvrez la fiche d’un autre client pour les utiliser.'
                            : 'Ce compte est administrateur : la prise de contrôle est interdite (retirez d’abord son rôle admin ci-dessous). Le blocage reste possible.',
                        style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w700),
                      ),
                    ),
                  section('Identité', [
                    kv('Statut', blocked ? 'BLOQUÉ — ${p['suspended_reason'] ?? p['account_status_reason'] ?? ''}' : 'Actif'),
                    kv('Téléphone', p['phone']),
                    kv('WhatsApp', p['whatsapp']),
                    kv('Ville', p['city']),
                    kv('Inscrit le', _date(p['created_at'])),
                    kv('Dernière activité', '${_date(p['last_seen_at'])} (${_ago(p['last_seen_at'])})'),
                    kv('Dernière connexion', _date(d['last_sign_in_at'])),
                    kv('E-mail confirmé', d['email_confirmed'] == true ? 'Oui' : 'Non'),
                    kv('Rôles', roles.isEmpty ? 'client' : roles.join(', ')),
                  ]),
                  section('Rôles administrateur', [
                    Wrap(spacing: 8, children: [
                      OutlinedButton(onPressed: () => setRole('support', !roles.contains('support')), child: Text(roles.contains('support') ? 'Retirer « support »' : 'Donner « support »')),
                      OutlinedButton(onPressed: () => setRole('admin', !isAdmin), child: Text(isAdmin ? 'Retirer « admin »' : 'Donner « admin »')),
                    ]),
                  ]),
                  FutureBuilder<Map<String, dynamic>>(
                    future: fx,
                    builder: (_, xs) {
                      final x = xs.data ?? const <String, dynamic>{};
                      if (x.isEmpty) return const SizedBox.shrink();
                      final addr = (x['addresses'] as List?) ?? [];
                      final tickets = (x['tickets'] as List?) ?? [];
                      final audit = (x['audit'] as List?) ?? [];
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        section('Vérification et activité', [
                          kv('Identité (KYC)', x['identity_status'] ?? 'aucun dossier'),
                          kv('Signalements reçus', x['reports_against']),
                          kv('Avis donnés', x['reviews_given']),
                          kv('Favoris', x['favorites']),
                          kv('Filleuls parrainés', x['referred_count']),
                        ]),
                        section('Adresses (${addr.length})', [
                          for (final a in addr) Text('• ${a['label']} — ${a['recipient']}, ${a['street'] ?? ''} ${a['quarter'] ?? ''}, ${a['commune']} ${a['phone'] ?? ''}'),
                          if (addr.isEmpty) Text('Aucune.', style: TextStyle(color: C.muted)),
                        ]),
                        section('Tickets support (${tickets.length})', [
                          for (final t in tickets) Text('• ${_date(t['created_at'])} — ${t['status']} — ${t['subject']}'),
                          if (tickets.isEmpty) Text('Aucun.', style: TextStyle(color: C.muted)),
                        ]),
                        section('Journal admin concernant ce compte', [
                          for (final l in audit) Text('• ${_date(l['created_at'])} — ${l['action']} ${l['reason'] ?? ''}'),
                          if (audit.isEmpty) Text('Aucune action.', style: TextStyle(color: C.muted)),
                        ]),
                      ]);
                    },
                  ),
                  section('Portefeuilles', [
                    if ((d['wallets'] as List).isEmpty) Text('Aucun portefeuille.', style: TextStyle(color: C.muted)),
                    for (final w in d['wallets'] as List) kv('${w['currency']}', money(_n(w['balance_minor']), '${w['currency']}')),
                    kv('Dépensé HTG', money(_n(d['spent_htg']), 'HTG')),
                    kv('Dépensé USD', money(_n(d['spent_usd']), 'USD')),
                  ]),
                  section('Boutiques (${(d['shops'] as List).length})', [
                    for (final sh in d['shops'] as List) Text('• ${sh['name']} — ${sh['status']} (${sh['city'] ?? '—'})'),
                    if ((d['shops'] as List).isEmpty) Text('Aucune.', style: TextStyle(color: C.muted)),
                    kv('Produits actifs', d['listings_count']),
                  ]),
                  if (d['courier'] != null)
                    section('Livreur', [
                      kv('Statut', (d['courier'] as Map)['status']),
                      kv('Nom', (d['courier'] as Map)['full_name']),
                      kv('Téléphone', (d['courier'] as Map)['phone']),
                      kv('Transport', (d['courier'] as Map)['transport']),
                      kv('Zone', (d['courier'] as Map)['zone']),
                    ]),
                  section('Commandes passées (${d['orders_count']})', [
                    for (final o in d['orders'] as List) Text('• ${_date(o['created_at'])} — ${o['status']} — ${money(_n(o['total_minor']), '${o['currency']}')} (${o['delivery_mode']})'),
                    if ((d['orders'] as List).isEmpty) Text('Aucune.', style: TextStyle(color: C.muted)),
                  ]),
                  section('Ventes de ses boutiques', [
                    for (final o in d['sales'] as List) Text('• ${_date(o['created_at'])} — ${o['status']} — ${money(_n(o['total_minor']), '${o['currency']}')}'),
                    if ((d['sales'] as List).isEmpty) Text('Aucune.', style: TextStyle(color: C.muted)),
                  ]),
                  section('Dernières écritures portefeuille', [
                    for (final t in d['transactions'] as List) Text('• ${_date(t['created_at'])} — ${t['kind']} — ${t['status']} — ${money(_n(t['amount_minor']), '${t['currency']}')}'),
                    if ((d['transactions'] as List).isEmpty) Text('Aucune.', style: TextStyle(color: C.muted)),
                  ]),
                ]),
              ),
            );
          },
        ),
      );
}

// ---------------------------------------------------------------------------
// 3. Commandes
// ---------------------------------------------------------------------------
class _OrdersPage extends StatefulWidget {
  const _OrdersPage();
  @override
  State<_OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<_OrdersPage> {
  final q = TextEditingController();
  String status = 'all';
  late Future<List<Map<String, dynamic>>> f = load();
  static const _statuses = ['all', 'PENDING_PAYMENT', 'PAID', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'IN_TRANSIT', 'DELIVERED', 'COMPLETED', 'CANCELLED', 'DISPUTED', 'REFUNDED'];

  Future<List<Map<String, dynamic>>> load() => _rows('admin_search_orders', {'p_q': q.text.trim(), 'p_status': status, 'p_limit': 60});
  void reload() => setState(() => f = load());

  Future<void> orderMenu(Map<String, dynamic> o, String v) async {
    final id = '${o['id']}';
    if (v == 'copy') {
      await Clipboard.setData(ClipboardData(text: id));
      if (mounted) toast(context, 'N° de commande copié.');
      return;
    }
    final force = v == 'force';
    final reopen = v == 'reopen';
    final reason = await askText(context, force ? 'Motif de la remise forcée' : (reopen ? 'Motif de la réaffectation' : 'Motif du déblocage'), hint: force ? '10 caractères minimum' : '5 caractères minimum');
    if (reason == null || !mounted) return;
    if (force && !await _confirm(context, 'Forcer la remise ?', 'La commande passera à « livrée/terminée » et le règlement vendeur/livreur sera déclenché. Action tracée dans le journal admin.')) return;
    try {
      final r = await _db.rpc(force ? 'admin_force_handover' : (reopen ? 'admin_reopen_job' : 'admin_reset_order_code'), params: {'p_order': id, 'p_reason': reason});
      if (mounted) toast(context, force ? 'Remise forcée : $r.' : (reopen ? 'Mission rouverte : le client choisira un nouveau livreur (ancien livreur remboursé côté client).' : 'Code débloqué : le livreur/vendeur peut réessayer.'));
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        Row(children: [
          Expanded(child: TextField(controller: q, onSubmitted: (_) => reload(), decoration: InputDecoration(labelText: 'N° de commande, client, boutique ou livreur', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: reload)))),
          const SizedBox(width: 10),
          DropdownButton<String>(value: status, items: [for (final s in _statuses) DropdownMenuItem(value: s, child: Text(s == 'all' ? 'Tous statuts' : s))], onChanged: (v) { status = v ?? 'all'; reload(); }),
        ]),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return EmptyState(title: 'Erreur', text: Repo.err(s.error!));
            final l = s.data ?? [];
            if (l.isEmpty) return const EmptyState(title: 'Aucune commande', text: 'Aucun résultat.');
            return Column(children: [
              for (final o in l)
                Card(
                  color: C.card,
                  child: ListTile(
                    title: Text('${money(_n(o['total_minor']), '${o['currency']}')} · ${o['status']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${o['shop_name']} ← ${o['customer_name'] ?? 'client'}\n${o['delivery_mode'] == 'delivery' ? 'Livraison ${money(_n(o['delivery_minor']), '${o['currency']}')} · livreur : ${o['courier_name'] ?? 'non affecté'}' : 'Retrait'} · ${_date(o['created_at'])}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => orderMenu(o, v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'copy', child: Text('Copier le n° de commande')),
                        PopupMenuItem(value: 'reset', child: Text('Débloquer le code (5 erreurs)')),
                        PopupMenuItem(value: 'force', child: Text('Forcer la remise (livrée / terminée)')),
                        PopupMenuItem(value: 'reopen', child: Text('Rouvrir la mission (nouveau livreur)')),
                      ],
                    ),
                  ),
                ),
            ]);
          },
        ),
      ]);
}

// ---------------------------------------------------------------------------
// 4. Catalogue : produits + catégories (créer / modifier / supprimer)
// ---------------------------------------------------------------------------
class _CatalogPage extends StatelessWidget {
  const _CatalogPage();
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(children: [
          TabBar(labelColor: C.ink, indicatorColor: C.terracotta, tabs: [Tab(text: 'Produits & annonces'), Tab(text: 'Catégories')]),
          Expanded(child: TabBarView(children: [_ProductsAdmin(), _CategoriesAdmin()])),
        ]),
      );
}

class _ProductsAdmin extends StatefulWidget {
  const _ProductsAdmin();
  @override
  State<_ProductsAdmin> createState() => _ProductsAdminState();
}

class _ProductsAdminState extends State<_ProductsAdmin> {
  final q = TextEditingController();
  String status = 'all';
  late Future<List<Map<String, dynamic>>> f = load();
  Future<List<Map<String, dynamic>>> load() => _rows('admin_search_products', {'p_q': q.text.trim(), 'p_status': status, 'p_limit': 60});
  void reload() => setState(() => f = load());

  Future<void> setStatus(Map<String, dynamic> p, String st) async {
    final reason = await askText(context, 'Motif', hint: 'Obligatoire');
    if (reason == null || reason.length < 3) return;
    try {
      await _db.rpc('admin_set_product_status', params: {'p_product': p['id'], 'p_status': st, 'p_reason': reason});
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        Row(children: [
          Expanded(child: TextField(controller: q, onSubmitted: (_) => reload(), decoration: InputDecoration(labelText: 'Produit, boutique ou identifiant', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: reload)))),
          const SizedBox(width: 10),
          DropdownButton<String>(value: status, items: [for (final s in const ['all', 'published', 'paused', 'draft', 'removed']) DropdownMenuItem(value: s, child: Text(s == 'all' ? 'Tous' : s))], onChanged: (v) { status = v ?? 'all'; reload(); }),
        ]),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return EmptyState(title: 'Erreur', text: Repo.err(s.error!));
            final l = s.data ?? [];
            if (l.isEmpty) return const EmptyState(title: 'Aucun produit', text: 'Aucun résultat.');
            return Column(children: [
              for (final p in l)
                Card(
                  color: p['status'] == 'removed' ? C.soft : C.card,
                  child: ListTile(
                    title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${p['shop_name']} · ${money(_n(p['price_minor']), '${p['currency']}')} · stock ${p['stock']} · ${p['status']}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => setStatus(p, v),
                      itemBuilder: (_) => [
                        if (p['status'] != 'removed') ...[
                          const PopupMenuItem(value: 'published', child: Text('Publier')),
                          const PopupMenuItem(value: 'paused', child: Text('Masquer (pause)')),
                          const PopupMenuItem(value: 'removed', child: Text('Supprimer du catalogue')),
                        ] else
                          const PopupMenuItem(enabled: false, child: Text('Supprimé : non republiable')),
                      ],
                    ),
                  ),
                ),
            ]);
          },
        ),
      ]);
}

class _CategoriesAdmin extends StatefulWidget {
  const _CategoriesAdmin();
  @override
  State<_CategoriesAdmin> createState() => _CategoriesAdminState();
}

class _CategoriesAdminState extends State<_CategoriesAdmin> {
  late Future<List<Map<String, dynamic>>> f = load();
  Future<List<Map<String, dynamic>>> load() async {
    final r = await _db.from('categories').select('id,name,parent_id,active').order('name');
    return List<Map<String, dynamic>>.from(r);
  }

  void reload() => setState(() => f = load());

  Future<void> edit(Map<String, dynamic>? c, List<Map<String, dynamic>> all) async {
    final name = TextEditingController(text: '${c?['name'] ?? ''}');
    var active = c?['active'] != false;
    String? parent = c?['parent_id'] as String?;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text(c == null ? 'Nouvelle catégorie' : 'Modifier la catégorie'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
            DropdownButtonFormField<String?>(
              value: parent,
              decoration: const InputDecoration(labelText: 'Catégorie parente'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('— Aucune (principale)')), for (final x in all) if (x['id'] != c?['id']) DropdownMenuItem<String?>(value: x['id'] as String, child: Text('${x['name']}'))],
              onChanged: (v) => setD(() => parent = v),
            ),
            SwitchListTile(value: active, onChanged: (v) => setD(() => active = v), title: const Text('Active')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('admin_upsert_category', params: {'p_id': c?['id'], 'p_name': name.text, 'p_parent': parent, 'p_active': active});
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> remove(Map<String, dynamic> c) async {
    if (!await _confirm(context, 'Supprimer « ${c['name']} » ?', 'Si elle est utilisée, elle sera seulement désactivée.')) return;
    try {
      final r = await _db.rpc('admin_delete_category', params: {'p_id': c['id']});
      if (mounted) toast(context, r == 'deactivated' ? 'Catégorie utilisée : désactivée.' : 'Catégorie supprimée.');
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return EmptyState(title: 'Erreur', text: Repo.err(s.error!));
          final l = s.data ?? [];
          final names = {for (final c in l) c['id']: c['name']};
          return ListView(padding: const EdgeInsets.all(14), children: [
            FilledButton.icon(onPressed: () => edit(null, l), icon: const Icon(Icons.add), label: const Text('Ajouter une catégorie')),
            const SizedBox(height: 8),
            for (final c in l)
              Card(
                color: C.card,
                child: ListTile(
                  title: Text('${c['name']}${c['active'] == false ? '  (inactive)' : ''}', style: TextStyle(fontWeight: FontWeight.w800, color: c['active'] == false ? C.muted : C.ink)),
                  subtitle: c['parent_id'] == null ? null : Text('Sous-catégorie de ${names[c['parent_id']] ?? '—'}'),
                  trailing: Wrap(children: [IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => edit(c, l)), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => remove(c))]),
                ),
              ),
          ]);
        },
      );
}

// ---------------------------------------------------------------------------
// 5. Diffusion : message à tous (image, lien, coupon, notification + bandeau)
// ---------------------------------------------------------------------------
class _BroadcastPage extends StatefulWidget {
  const _BroadcastPage();
  @override
  State<_BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<_BroadcastPage> {
  final title = TextEditingController(), body = TextEditingController(), image = TextEditingController(), link = TextEditingController();
  String audience = 'all';
  String? coupon;
  bool banner = false, busy = false;
  late Future<List<Map<String, dynamic>>> history = _rows('admin_list_broadcasts');
  late Future<List<Map<String, dynamic>>> coupons = Repo.adminCoupons();

  static const _audiences = <(String, String)>[
    ('all', 'Tous les utilisateurs'), ('customers', 'Clients ayant déjà commandé'), ('sellers', 'Vendeurs / boutiques'),
    ('couriers', 'Livreurs approuvés'), ('active30', 'Actifs depuis 30 jours'), ('inactive30', 'Inactifs depuis 30 jours (relance)'),
  ];

  Future<void> pickImage() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final ext = MediaFormats.ext(x.name).isEmpty ? 'jpg' : MediaFormats.ext(x.name);
      final mime = MediaFormats.imageMimes[ext];
      if (mime == null) throw 'Format non pris en charge (${MediaFormats.imageHelp}).';
      final url = await Repo.uploadImage(bytes, ext, mime);
      setState(() => image.text = url);
    } catch (e) {
      if (mounted) toast(context, 'Téléversement impossible (${Repo.err(e)}). Collez plutôt une adresse https:// d’image.');
    }
  }

  Future<void> send() async {
    final ok = await _confirm(context, 'Envoyer à « ${_audiences.firstWhere((a) => a.$1 == audience).$2} » ?', 'Une notification sera créée dans l’application de chaque destinataire. Cette action est définitive.');
    if (!ok) return;
    setState(() => busy = true);
    try {
      final n = await _db.rpc('admin_send_broadcast', params: {'p_title': title.text, 'p_body': body.text, 'p_image': image.text, 'p_link': link.text, 'p_coupon': coupon, 'p_audience': audience, 'p_banner': banner});
      if (mounted) toast(context, 'Message envoyé à $n destinataire(s).');
      title.clear(); body.clear(); image.clear(); link.clear();
      setState(() { coupon = null; history = _rows('admin_list_broadcasts'); });
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        Text('Envoyer un message à vos utilisateurs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink)),
        Text('Le message apparaît dans la cloche de notifications (image, lien et coupon inclus). Les notifications « push » système (téléphone verrouillé) nécessitent Firebase, non configuré dans ce projet.', style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: audience, decoration: const InputDecoration(labelText: 'Destinataires'), items: [for (final a in _audiences) DropdownMenuItem(value: a.$1, child: Text(a.$2))], onChanged: (v) => setState(() => audience = v ?? 'all')),
        TextField(controller: title, maxLength: 100, decoration: const InputDecoration(labelText: 'Titre')),
        TextField(controller: body, maxLines: 4, maxLength: 1200, decoration: const InputDecoration(labelText: 'Message')),
        Row(children: [
          Expanded(child: TextField(controller: image, decoration: const InputDecoration(labelText: 'Image (https://…)'))),
          IconButton(tooltip: 'Choisir une image', icon: const Icon(Icons.image_outlined), onPressed: pickImage),
        ]),
        TextField(controller: link, decoration: const InputDecoration(labelText: 'Lien à ouvrir (https://…)')),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: coupons,
          builder: (_, s) {
            final l = (s.data ?? []).where((c) => c['active'] == true).toList();
            return DropdownButtonFormField<String?>(
              value: coupon,
              decoration: const InputDecoration(labelText: 'Coupon à offrir (optionnel)'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('— Aucun')), for (final c in l) DropdownMenuItem<String?>(value: '${c['code']}', child: Text('${c['code']}  (${c['kind'] == 'percent' ? '${c['value']} %' : '${c['value']}'})'))],
              onChanged: (v) => setState(() => coupon = v),
            );
          },
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: banner, onChanged: (v) => setState(() => banner = v), title: const Text('Afficher aussi en bandeau global dans l’application')),
        const SizedBox(height: 6),
        PrimaryButton(label: busy ? 'Envoi…' : 'Envoyer le message', icon: Icons.send, onPressed: busy ? null : send),
        const Divider(height: 32),
        const Text('Historique des envois', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: history,
          builder: (_, s) {
            final l = s.data ?? [];
            if (s.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            if (l.isEmpty) return Text('Aucun envoi.', style: TextStyle(color: C.muted));
            return Column(children: [for (final b in l) Card(color: C.card, child: ListTile(title: Text('${b['title']}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${b['recipients']} destinataires · ${b['audience']}${b['coupon_code'] != null ? ' · coupon ${b['coupon_code']}' : ''} · ${_date(b['created_at'])}')))]);
          },
        ),
      ]);
}

// ---------------------------------------------------------------------------
// 6. Réglages : tous les paramètres, modifiables / ajoutables sans toucher à la base
// ---------------------------------------------------------------------------
class _SettingsPage extends StatefulWidget {
  const _SettingsPage();
  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late Future<List<Map<String, dynamic>>> f = _rows('admin_list_settings');
  void reload() => setState(() => f = _rows('admin_list_settings'));

  static const _help = <String, String>{
    'commission_bps': 'Commission HAITIKET en points de base (200 = 2 %).',
    'reservation_minutes': 'Durée de réservation du stock avant paiement (minutes).',
    'delivery_flat_minor': 'Frais de livraison forfaitaires en centimes. 0 = le livreur fixe son prix (recommandé).',
    'delivery_offer_expiry_minutes': 'Durée de validité d’une offre de livreur (1 à 60 minutes).',
    'usd_htg_rate': 'Taux USD → HTG.',
    'usd_htg_topup_rate': 'Taux appliqué aux recharges USD.',
    'usd_htg_withdraw_rate': 'Taux appliqué aux retraits USD.',
    'bazar_fee_usd': 'Prix d’une annonce Bazar (USD, 14 jours).',
    'shop_fee_usd': 'Abonnement boutique mensuel (USD).',
    'shop_fee_yearly_usd': 'Abonnement boutique annuel (USD).',
    'enforce_shop_plan': '1 = abonnement obligatoire pour vendre.',
    'referral_reward_minor': 'Récompense de parrainage (centimes).',
    'usd_htg_convert_rate': 'Taux de conversion entre portefeuilles HTG/USD (HTG pour 1 USD). À défaut : usd_htg_rate.',
    'wallet_conversion_fee_bps': 'Frais de conversion entre portefeuilles (points de base : 100 = 1 %). 0 = gratuit.',
    'seller_rate_max_deviation_pct': 'Écart maximal (en %) entre le taux USD d’une boutique et celui de la plateforme.',
    'pin_validity_hours': 'Durée de validité des codes PIN/QR de remise (heures). Un code expiré est renouvelé.',
    'reassign_after_minutes': 'Minutes avant qu’un client puisse demander un autre livreur (si le livreur reste joignable).',
    'late_immediate_hours': 'Heures avant remboursement automatique d’une commande IMMÉDIATE en retard.',
    'delivery_no_courier_minutes': 'Minutes sans livreur avant d’alerter le client (moitié pour l’immédiat).',
    'courier_gps_max_minutes': 'Ancienneté maximale de la position GPS d’un livreur pour voir les missions (minutes).',
    'delivery_urban_speed_kmh': 'Vitesse urbaine moyenne utilisée pour estimer le trajet (km/h).',
  };

  Future<void> edit(String key, String current) async {
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(key),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_help[key] != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_help[key]!, style: TextStyle(color: C.muted))),
          TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Valeur')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Enregistrer'))],
      ),
    );
    if (v == null) return;
    try {
      await _db.rpc('admin_set_setting_any', params: {'p_key': key, 'p_value': v});
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> add() async {
    final k = await askText(context, 'Nom du réglage', hint: 'minuscules, chiffres et _ (ex. delivery_max_km)');
    if (k == null || k.isEmpty) return;
    await edit(k, '');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return EmptyState(title: 'Erreur', text: Repo.err(s.error!));
          final l = s.data ?? [];
          return ListView(padding: const EdgeInsets.all(14), children: [
            FilledButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Ajouter un réglage')),
            const SizedBox(height: 8),
            for (final r in l)
              Card(
                color: C.card,
                child: ListTile(
                  title: Text('${r['key']} = ${r['value']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${_help['${r['key']}'] ?? 'Réglage personnalisé'}\nModifié : ${_date(r['updated_at'])}'),
                  isThreeLine: true,
                  trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => edit('${r['key']}', '${r['value']}')),
                ),
              ),
          ]);
        },
      );
}
