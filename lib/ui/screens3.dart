import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'screens5.dart';
import 'widgets.dart';
import 'mascot.dart';
import '../i18n.dart';

Future<void> openChat(BuildContext context, String kind, String ref) async {
  if (currentUser() == null) return toast(context, 'Connectez-vous pour envoyer un message.');
  try {
    final id = await Repo.startConversation(kind, ref);
    if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(id)));
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}


/// Pastille ronde : photo de la personne ou logo de la boutique, sinon initiale.
class ChatAvatar extends StatelessWidget {
  final String? url;
  final String label;
  final double radius;
  final bool shop;
  const ChatAvatar({super.key, this.url, required this.label, this.radius = 22, this.shop = false});
  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: shop ? C.yellow.withValues(alpha: .35) : C.mint,
      backgroundImage: hasUrl ? NetworkImage(url!) : null,
      onBackgroundImageError: hasUrl ? (_, __) {} : null,
      child: hasUrl
          ? null
          : (label.trim().isEmpty
              ? Icon(shop ? Icons.storefront : Icons.person, size: radius, color: C.green)
              : Text(label.trim().substring(0, 1).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, color: C.green, fontSize: radius * .8))),
    );
  }
}

String _chatWhen(dynamic v) {
  final d = DateTime.tryParse('$v')?.toLocal();
  if (d == null) return '';
  final n = DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  final today = d.year == n.year && d.month == n.month && d.day == n.day;
  return today ? '${two(d.hour)}:${two(d.minute)}' : '${two(d.day)}/${two(d.month)}';
}

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});
  @override
  State<ConversationsScreen> createState() => _ConversationsState();
}

class _ConversationsState extends State<ConversationsScreen> {
  late Future<List<Map<String, dynamic>>> f = Repo.myConversationsV67();
  void reload() => setState(() => f = Repo.myConversationsV67());

  Future<void> hide(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Retirer cette discussion ?'),
        content: const Text('Elle disparaît de votre boîte de réception. L\'autre personne la garde, et les échanges liés à une commande restent conservés en cas de litige. Un nouveau message la fera réapparaître.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Retirer'))],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.hideConversation(c['id'] as String);
      reload();
      if (mounted) toast(context, 'Discussion retirée de votre boîte.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        MascotHeader(mascot: Mascot.messages, title: tr('Messages'), subtitle: 'Vendeurs, clients et livreurs, tout est ici.'),
        if (currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour voir vos conversations.')
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: f,
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) return ErrorState(s.error);
              final items = s.data ?? [];
              if (items.isEmpty) return const EmptyState(title: 'Aucune conversation', text: 'Contactez un vendeur depuis une fiche produit, une annonce ou une commande.');
              return Column(children: [
                for (final c in items)
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                      leading: ChatAvatar(url: c['other_avatar'] as String?, label: '${c['other_name'] ?? ''}', shop: c['other_is_shop'] == true),
                      title: Row(children: [
                        Expanded(child: Text('${c['other_name'] ?? c['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text(_chatWhen(c['last_at']), style: const TextStyle(color: C.muted, fontSize: 12)),
                      ]),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.green, fontSize: 12, fontWeight: FontWeight.w700)),
                        Text(c['last_deleted'] == true ? 'Message supprimé' : (c['last_body'] == null ? 'Aucun message' : '${c['last_body']}'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Options',
                        onSelected: (v) { if (v == 'hide') hide(c); },
                        itemBuilder: (_) => const [PopupMenuItem(value: 'hide', child: Text('Retirer de ma boîte'))],
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(c['id'] as String)));
                        if (mounted) reload();
                      },
                    ),
                  ),
              ]);
            },
          ),
      ]);
}

class ChatScreen extends StatefulWidget {
  final String cid;
  const ChatScreen(this.cid, {super.key});
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  final input = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> stream = Repo.messageStream(widget.cid);
  String title = 'Conversation';
  Map<String, Map<String, dynamic>> people = {};
  Set<String> hidden = <String>{};

  Map<String, dynamic>? get other {
    final me = currentUser()?.id;
    for (final e in people.entries) {
      if (e.key != me) return e.value;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    Repo.conversationSubject(widget.cid).then((t) {
      if (mounted) setState(() => title = t);
    }).catchError((_) {});
    loadPeople();
  }

  Future<void> loadPeople() async {
    final p = await Repo.conversationPeople(widget.cid);
    final h = await Repo.hiddenMessageIds(widget.cid);
    if (mounted) setState(() { people = p; hidden = h; });
  }

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    try {
      await Repo.sendMessage(widget.cid, t);
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> messageMenu(Map<String, dynamic> m, bool mine) async {
    final id = '${m['id']}';
    final deleted = m['deleted_at'] != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.visibility_off_outlined), title: const Text('Supprimer pour moi'), subtitle: const Text('Les autres personnes le voient toujours'), onTap: () => Navigator.pop(c, 'me')),
          if (mine && !deleted) ListTile(leading: const Icon(Icons.delete_outline, color: C.terracotta), title: const Text('Supprimer pour tous'), subtitle: const Text('Possible pendant 15 minutes après l\'envoi'), onTap: () => Navigator.pop(c, 'all')),
        ]),
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'me') {
        await Repo.hideMessage(id);
        if (mounted) setState(() => hidden = {...hidden, id});
      } else {
        await Repo.deleteMessageForAll(id);
        if (mounted) toast(context, 'Message supprimé pour tous.');
      }
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Widget avatarFor(String? senderId) {
    final p = senderId == null ? null : people[senderId];
    return ChatAvatar(url: p?['avatar_url'] as String?, label: '${p?['name'] ?? ''}', radius: 15, shop: p?['is_shop'] == true);
  }

  @override
  Widget build(BuildContext context) {
    final me = currentUser()?.id;
    final o = other;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          ChatAvatar(url: o?['avatar_url'] as String?, label: '${o?['name'] ?? ''}', radius: 18, shop: o?['is_shop'] == true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o?['name'] ?? title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink, fontSize: 17)),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, s) {
              final msgs = (s.data ?? []).where((m) => !hidden.contains('${m['id']}')).toList().reversed.toList();
              if (msgs.isEmpty) return const Center(child: Text('Écrivez le premier message.', style: TextStyle(color: C.muted)));
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(14),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  final mine = m['sender_id'] == me;
                  final senderId = m['sender_id']?.toString();
                  final deleted = m['deleted_at'] != null;
                  final senderName = '${people[senderId]?['name'] ?? ''}';
                  return GestureDetector(
                    onLongPress: () => messageMenu(m, mine),
                    child: Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!mine) Padding(padding: const EdgeInsets.only(right: 7, bottom: 5), child: avatarFor(senderId)),
                          Flexible(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: const BoxConstraints(maxWidth: 300),
                              decoration: BoxDecoration(color: mine ? C.ink : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                if (!mine && senderName.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(senderName, style: const TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 12))),
                                Text(deleted ? 'Message supprimé' : '${m['body']}', style: TextStyle(color: mine ? Colors.white : C.ink, fontSize: 16, fontStyle: deleted ? FontStyle.italic : FontStyle.normal)),
                                Padding(padding: const EdgeInsets.only(top: 3), child: Text(_chatWhen(m['created_at']), style: TextStyle(color: mine ? Colors.white60 : C.muted, fontSize: 10))),
                              ]),
                            ),
                          ),
                          if (mine) Padding(padding: const EdgeInsets.only(left: 7, bottom: 5), child: avatarFor(senderId)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(child: TextField(controller: input, maxLength: 2000, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Votre message'))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: send, style: IconButton.styleFrom(backgroundColor: C.ink), icon: const Icon(Icons.send, color: Colors.white)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class CourierScreen extends StatefulWidget {
  const CourierScreen({super.key});
  @override
  State<CourierScreen> createState() => _CourierState();
}

class _CourierState extends State<CourierScreen> with WidgetsBindingObserver {
  late Future<Map<String, dynamic>> f = load();
  StreamSubscription<Position>? _positionSubscription;
  bool _gpsStarting = false;
  bool _gpsActive = false;
  bool _availabilityChecked = false;
  DateTime? _lastGpsWrite;
  Timer? _missionPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Limite la collecte en arrière-plan : ce sprint ne revendique pas un service GPS natif permanent.
    if (state == AppLifecycleState.resumed) {
      if (_availabilityChecked) _startGps();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _stopGps();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _missionPoll?.cancel();
    super.dispose();
  }

  Future<void> _stopGps() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _gpsActive = false;
  }

  Future<void> _startGps() async {
    if (_gpsStarting || _gpsActive || !mounted) return;
    _gpsStarting = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) toast(context, 'Activez la localisation GPS pour partager votre position pendant les missions.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'Autorisez la localisation pour publier votre position de coursier.');
        return;
      }
      final settings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15);
      // Activer avant de s'abonner pour ne pas ignorer la première position émise immédiatement.
      _gpsActive = true;
      _positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen((position) async {
        if (!mounted || !_gpsActive || !_availabilityChecked) return;
        final now = DateTime.now();
        if (_lastGpsWrite != null && now.difference(_lastGpsWrite!) < const Duration(seconds: 12)) return;
        _lastGpsWrite = now;
        try {
          await Repo.publishCourierLocation(position.latitude, position.longitude, accuracyM: position.accuracy);
        } catch (e) {
          // Ne pas interrompre le flux GPS sur une erreur réseau ponctuelle.
          debugPrint('HAITIKET GPS publish failed: ${Repo.err(e)}');
        }
      }, onError: (Object e) {
        if (mounted) debugPrint('HAITIKET GPS stream error: $e');
      });
    } catch (e) {
      if (mounted) toast(context, 'GPS indisponible : ${Repo.err(e)}');
    } finally {
      _gpsStarting = false;
    }
  }

  Future<void> _setAvailability(bool available) async {
    await Repo.setCourierAvailable(available);
    _availabilityChecked = available;
    if (available) {
      await _startGps();
    } else {
      await _stopGps();
    }
  }

  Future<Map<String, dynamic>> load() async {
    final app = await Repo.myCourierApplication();
    if (app == null || app['status'] != 'approved') return {'app': app};
    final avail = await Repo.courierAvailable();
    _availabilityChecked = avail;
    if (avail && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      // La disponibilité peut avoir été conservée côté serveur après fermeture de l'écran.
      await _startGps();
      // Actualise les missions ouvertes en premier plan; ce polling n'est pas une notification push.
      _missionPoll ??= Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed && _availabilityChecked) {
          reload();
        }
      });
    } else if (!avail) {
      _missionPoll?.cancel();
      _missionPoll = null;
      await _stopGps();
    }
    final open = avail ? await Repo.openJobs() : <Map<String, dynamic>>[];
    final mine = await Repo.myJobs();
    return {'app': app, 'avail': avail, 'open': open, 'mine': mine};
  }

  void reload() {
    if (!mounted) return;
    setState(() => f = load());
  }

  Future<void> proposePrice(Map<String, dynamic> job) async {
    final currency = (job['currency'] ?? 'HTG').toString();
    final amountText = await askText(context, 'Votre prix de livraison ($currency)', hint: 'Montant en $currency, ex. 250', type: TextInputType.numberWithOptions(decimal: true));
    if (amountText == null || amountText.trim().isEmpty || !mounted) return;
    final etaText = await askText(context, 'Délai estimé en minutes', hint: 'Ex. 35', type: TextInputType.number);
    if (etaText == null || !mounted) return;
    final note = await askText(context, 'Note au client (facultatif)', hint: 'Ex. circulation dense');
    if (!mounted) return;
    final amount = double.tryParse(amountText.trim().replaceAll(',', '.'));
    final eta = int.tryParse(etaText.trim());
    if (amount == null || !amount.isFinite || amount <= 0 || eta == null || eta < 1 || eta > 1440) {
      toast(context, 'Vérifiez le prix et le délai (1 à 1440 minutes).');
      return;
    }
    await run(() async {
      await Repo.proposeDeliveryPrice(job['id'].toString(), (amount * 100).round(), currency, eta, note: note);
      if (mounted) toast(context, 'Offre envoyée. Le client pourra la comparer pendant la durée configurée.');
    });
  }

  Future<void> reportTrafficDelay(Map<String, dynamic> job) async {
    final choice = await showDialog<int>(context: context, builder: (d) => AlertDialog(
      title: const Text('Retard dû à la circulation'),
      content: const Text('Choisissez une prolongation réaliste. Le client sera informé. Cette déclaration doit correspondre à la situation réelle.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(d, 120), child: const Text('+ 2 heures')),
        FilledButton(onPressed: () => Navigator.pop(d, 240), child: const Text('+ 4 heures')),
      ],
    ));
    if (choice == null || !mounted) return;
    final reason = await askText(context, 'Expliquez le retard', hint: 'Ex. embouteillage important sur le trajet');
    if (reason == null || reason.trim().length < 10 || !mounted) {
      if (mounted && reason != null) toast(context, 'Le motif doit contenir au moins 10 caractères.');
      return;
    }
    await run(() async {
      await Repo.reportDeliveryTrafficDelay(job['id'].toString(), choice, reason.trim());
      if (mounted) toast(context, 'Retard signalé. Le client peut maintenant voir le motif et la prolongation.');
    });
  }

  Future<void> confirm(Map<String, dynamic> j, bool pickup) async {
    final pin = await askText(context, pickup ? 'Code donné par le vendeur' : 'Code donné par le client', type: TextInputType.number);
    if (pin == null || pin.isEmpty) return;
    try {
      final ok = pickup ? await Repo.confirmPickup(j['id'] as String, pin) : await Repo.confirmDelivery(j['id'] as String, pin);
      if (mounted) toast(context, ok ? (pickup ? 'Collecte confirmée.' : 'Remise confirmée.') : 'Code incorrect.');
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> withdrawCourierRole() async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Arrêter définitivement les livraisons ?'),
      content: const Text('Votre candidature sera marquée comme retirée et l’historique sera conservé. Vous pourrez contacter le support si vous souhaitez revenir plus tard.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Retirer ma candidature'))],
    ));
    if (ok != true) return;
    try {
      await _stopGps();
      await Repo.withdrawCourier();
      if (!mounted) return;
      toast(context, 'Candidature livreur retirée.');
      reload();
    } catch (e) { if (mounted) toast(context, 'Impossible de retirer la candidature : ${Repo.err(e)}'); }
  }

  Future<void> run(Future<void> Function() a) async {
    try {
      await a();
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        MascotHeader(mascot: Mascot.orders, title: tr('Espace livreur'), subtitle: 'Vos missions et votre position de livraison.'),
        if (!Config.configured || currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour accéder à vos missions.')
        else
          FutureBuilder<Map<String, dynamic>>(
            future: f,
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) return ErrorState(s.error);
              final d = s.data!;
              final app = d['app'] as Map<String, dynamic>?;
              if (app == null) return const EmptyState(title: 'Aucune candidature', text: "Déposez votre candidature dans « HAITIKET Network » pour devenir livreur.");
              if (app['status'] != 'approved') return EmptyState(title: 'Candidature en cours', text: 'Statut : ${app['status']}. Vous recevrez des missions après approbation.');
              final avail = d['avail'] as bool;
              if (!_availabilityChecked) {
                _availabilityChecked = true;
                WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && avail) _startGps(); });
              }
              final open = List<Map<String, dynamic>>.from(d['open'] as List);
              final mine = List<Map<String, dynamic>>.from(d['mine'] as List);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (app['verified_at'] != null) const Chip(avatar: Icon(Icons.verified, color: Colors.white, size: 16), label: Text('Livreur vérifié'), backgroundColor: C.green, labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(avail ? 'Disponible pour les livraisons' : 'Indisponible', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  value: avail,
                  onChanged: (v) => run(() => _setAvailability(v)),
                ),
                Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: withdrawCourierRole, icon: const Icon(Icons.person_remove_alt_1_outlined), label: const Text('Je ne souhaite plus être livreur'))),
                const SizedBox(height: 12),
                const Text('Missions proposées', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
                const SizedBox(height: 8),
                if (!avail)
                  const Text('Activez votre disponibilité pour voir les missions.', style: TextStyle(color: C.muted))
                else if (open.isEmpty)
                  const Text('Aucune mission disponible pour le moment.', style: TextStyle(color: C.muted))
                else
                  for (final j in open)
                    Card(
                      color: Colors.white,
                      child: ListTile(
                        title: Text('Départ : ${j['pickup_area']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('Proposez votre tarif · ${j['currency'] ?? 'HTG'}', style: const TextStyle(color: C.green, fontWeight: FontWeight.w800)),
                        trailing: FilledButton(onPressed: () => proposePrice(j), child: const Text('Proposer un prix')),
                      ),
                    ),
                const SizedBox(height: 20),
                const Text('Mes missions', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
                const SizedBox(height: 8),
                if (mine.isEmpty)
                  const Text('Aucune mission acceptée.', style: TextStyle(color: C.muted))
                else
                  for (final j in mine)
                    Card(
                      color: Colors.white,
                      child: ListTile(
                        title: Text('${j['pickup_area']} → ${j['dropoff_address']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${money(j['pay_minor'] as num, j['currency'] as String)} · ${j['status']}'),
                        trailing: (j['status'] == 'assigned' || j['status'] == 'picked_up')
                            ? PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'traffic') reportTrafficDelay(j);
                                  if (action == 'pickup') confirm(j, true);
                                  if (action == 'delivery') confirm(j, false);
                                },
                                itemBuilder: (_) => [
                                  if (j['status'] == 'assigned') const PopupMenuItem(value: 'pickup', child: Text('Confirmer la collecte')),
                                  if (j['status'] == 'picked_up') const PopupMenuItem(value: 'delivery', child: Text('Confirmer la remise')),
                                  const PopupMenuItem(value: 'traffic', child: Text('Signaler un retard de circulation')),
                                ],
                                child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.more_vert)),
                              )
                            : null,
                      ),
                    ),
              ]);
            },
          ),
      ]);
}
