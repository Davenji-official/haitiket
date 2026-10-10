import 'package:flutter/material.dart';
import '../config.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'widgets.dart';

Future<void> openChat(BuildContext context, String kind, String ref) async {
  if (currentUser() == null) return toast(context, 'Connectez-vous pour envoyer un message.');
  try {
    final id = await Repo.startConversation(kind, ref);
    if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(id)));
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}

Widget _h(String t) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Text(t, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1)));

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        _h('Messages'),
        if (currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour voir vos conversations.')
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Repo.myConversations(),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) return const EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.');
              final items = s.data ?? [];
              if (items.isEmpty) return const EmptyState(title: 'Aucune conversation', text: 'Contactez un vendeur depuis une fiche produit, une annonce ou une commande.');
              return Column(children: [
                for (final c in items)
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      title: Text('${c['subject']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_last(c)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(c['id'] as String))),
                    ),
                  ),
              ]);
            },
          ),
      ]);

  String _last(Map<String, dynamic> c) {
    final m = List<Map<String, dynamic>>.from(c['messages'] as List);
    if (m.isEmpty) return 'Aucun message';
    m.sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String));
    return m.last['body'] as String;
  }
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

  @override
  void initState() {
    super.initState();
    Repo.conversationSubject(widget.cid).then((t) {
      if (mounted) setState(() => title = t);
    }).catchError((_) {});
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

  @override
  Widget build(BuildContext context) {
    final me = currentUser()?.id;
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, s) {
              final msgs = (s.data ?? []).reversed.toList();
              if (msgs.isEmpty) return const Center(child: Text('Écrivez le premier message.', style: TextStyle(color: C.muted)));
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(14),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  final mine = m['sender_id'] == me;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      constraints: const BoxConstraints(maxWidth: 300),
                      decoration: BoxDecoration(color: mine ? C.ink : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
                      child: Text('${m['body']}', style: TextStyle(color: mine ? Colors.white : C.ink, fontSize: 16)),
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

class _CourierState extends State<CourierScreen> {
  late Future<Map<String, dynamic>> f = load();

  Future<Map<String, dynamic>> load() async {
    final app = await Repo.myCourierApplication();
    if (app == null || app['status'] != 'approved') return {'app': app};
    final avail = await Repo.courierAvailable();
    final open = avail ? await Repo.openJobs() : <Map<String, dynamic>>[];
    final mine = await Repo.myJobs();
    return {'app': app, 'avail': avail, 'open': open, 'mine': mine};
  }

  void reload() => setState(() => f = load());

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
        _h('Espace livreur'),
        if (!Config.configured || currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour accéder à vos missions.')
        else
          FutureBuilder<Map<String, dynamic>>(
            future: f,
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) return const EmptyState(title: 'Chargement impossible', text: 'Réessayez dans un instant.');
              final d = s.data!;
              final app = d['app'] as Map<String, dynamic>?;
              if (app == null) return const EmptyState(title: 'Aucune candidature', text: "Déposez votre candidature dans « HAITIKET Network » pour devenir livreur.");
              if (app['status'] != 'approved') return EmptyState(title: 'Candidature en cours', text: 'Statut : ${app['status']}. Vous recevrez des missions après approbation.');
              final avail = d['avail'] as bool;
              final open = List<Map<String, dynamic>>.from(d['open'] as List);
              final mine = List<Map<String, dynamic>>.from(d['mine'] as List);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(avail ? 'Disponible pour les livraisons' : 'Indisponible', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  value: avail,
                  onChanged: (v) => run(() => Repo.setCourierAvailable(v)),
                ),
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
                        subtitle: Text('Rémunération : ${money(j['pay_minor'] as num, j['currency'] as String)}', style: const TextStyle(color: C.green, fontWeight: FontWeight.w800)),
                        trailing: FilledButton(onPressed: () => run(() => Repo.acceptJob(j['id'] as String)), child: const Text('Accepter')),
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
                      ),
                    ),
              ]);
            },
          ),
      ]);
}
