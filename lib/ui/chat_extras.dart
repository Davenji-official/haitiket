import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import '../media_formats.dart';
import '../theme.dart';
import 'product_detail.dart';
import 'specs.dart';
import 'widgets.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Pièces jointes de messagerie : fichiers privés (bucket « chat-media »), accessibles uniquement aux membres de la conversation.
class ChatMedia {
  static final Map<String, (String, DateTime)> _cache = {};

  static Future<String> url(String path) async {
    final hit = _cache[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    final u = await _db.storage.from('chat-media').createSignedUrl(path, 3600);
    _cache[path] = (u, DateTime.now().add(const Duration(minutes: 50)));
    return u;
  }

  static Future<void> sendAttachment({
    required String cid,
    required String kind,
    required Uint8List bytes,
    required String name,
    required String mime,
  }) async {
    final me = _db.auth.currentUser;
    if (me == null) throw 'Connexion requise';
    if (bytes.length > 50 * 1024 * 1024) throw 'Fichier trop lourd (50 Mo maximum).';
    final ext = MediaFormats.ext(name);
    final path = '$cid/${DateTime.now().microsecondsSinceEpoch}${ext.isEmpty ? '' : '.$ext'}';
    await _db.storage.from('chat-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    final label = kind == 'image' ? '📷 Photo' : (kind == 'video' ? '🎬 Vidéo' : '📎 $name');
    await _db.from('messages').insert({
      'conversation_id': cid,
      'sender_id': me.id,
      'body': label,
      'kind': kind,
      'attachment_path': path,
      'attachment_name': name,
      'attachment_mime': mime,
      'attachment_size': bytes.length,
    });
  }

  static Future<void> sendProduct(String cid, String productId, String name) async {
    final me = _db.auth.currentUser;
    if (me == null) throw 'Connexion requise';
    await _db.from('messages').insert({
      'conversation_id': cid,
      'sender_id': me.id,
      'body': '🛍 ${name.length > 80 ? name.substring(0, 80) : name}',
      'kind': 'product',
      'product_id': productId,
    });
  }

  /// Contexte de la conversation : produit, commande ou annonce concernée.
  static Future<({String kind, String id})?> context(String cid) async {
    try {
      final c = await _db.from('conversations').select('context_kind,context_id').eq('id', cid).maybeSingle();
      if (c == null) return null;
      return (kind: '${c['context_kind']}', id: '${c['context_id']}');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> shopId(String cid) async {
    final ctx = await context(cid);
    if (ctx == null) return null;
    try {
      if (ctx.kind == 'product' || ctx.kind == 'listing') {
        final r = await _db.from('products').select('shop_id').eq('id', ctx.id).maybeSingle();
        return r?['shop_id'] as String?;
      }
      if (ctx.kind == 'order') {
        final r = await _db.from('orders').select('shop_id').eq('id', ctx.id).maybeSingle();
        return r?['shop_id'] as String?;
      }
    } catch (_) {}
    return null;
  }
}

/// Menu « pièce jointe » de la messagerie : photo, caméra, vidéo, fichier, produit.
Future<void> chatAttach(BuildContext context, String cid) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_outlined), title: const Text('Photo de la galerie'), subtitle: Text(MediaFormats.imageHelp), onTap: () => Navigator.pop(c, 'photo')),
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Prendre une photo'), onTap: () => Navigator.pop(c, 'camera')),
        ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Vidéo'), subtitle: const Text('MP4, WebM ou MOV · 50 Mo max'), onTap: () => Navigator.pop(c, 'video')),
        ListTile(leading: const Icon(Icons.attach_file), title: const Text('Fichier'), subtitle: const Text('PDF, Word, Excel, texte, audio'), onTap: () => Navigator.pop(c, 'file')),
        ListTile(leading: const Icon(Icons.shopping_bag_outlined), title: const Text('Partager un produit de la boutique'), onTap: () => Navigator.pop(c, 'product')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    if (choice == 'photo' || choice == 'camera') {
      final x = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
      if (x == null) return;
      final mime = MediaFormats.image(x.name) ?? (choice == 'camera' ? 'image/jpeg' : null);
      if (mime == null) throw 'Format non pris en charge (${MediaFormats.imageHelp}).';
      final bytes = await x.readAsBytes();
      if (bytes.length > 25 * 1024 * 1024) throw 'Photo trop lourde (25 Mo maximum).';
      await ChatMedia.sendAttachment(cid: cid, kind: 'image', bytes: bytes, name: x.name, mime: mime);
    } else if (choice == 'video') {
      final x = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
      if (x == null) return;
      final mime = MediaFormats.video(x.name) ?? 'video/mp4';
      final bytes = await x.readAsBytes();
      await ChatMedia.sendAttachment(cid: cid, kind: 'video', bytes: bytes, name: x.name, mime: mime);
    } else if (choice == 'file') {
      final r = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: MediaFormats.docMimes.keys.toList());
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      final bytes = f.bytes;
      final mime = MediaFormats.doc(f.name);
      if (bytes == null || mime == null) throw 'Fichier illisible ou format non pris en charge.';
      await ChatMedia.sendAttachment(cid: cid, kind: 'file', bytes: bytes, name: f.name, mime: mime);
    } else if (choice == 'product') {
      final shop = await ChatMedia.shopId(cid);
      if (shop == null) throw 'Aucune boutique liée à cette conversation.';
      if (!context.mounted) return;
      final p = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (c) => _ProductPicker(shopId: shop),
      );
      if (p == null) return;
      await ChatMedia.sendProduct(cid, '${p['id']}', '${p['name']}');
    }
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}

class _ProductPicker extends StatelessWidget {
  final String shopId;
  const _ProductPicker({required this.shopId});

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await _db.from('products').select('id,name,price_minor,currency,image_url,stock').eq('shop_id', shopId).eq('status', 'published').order('created_at', ascending: false).limit(40);
    return List<Map<String, dynamic>>.from(r);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .7,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(14), child: Text('Choisir un produit à partager', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: C.ink))),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _load(),
                builder: (_, s) {
                  if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  final l = s.data ?? [];
                  if (l.isEmpty) return const Center(child: Text('Aucun produit publié dans cette boutique.'));
                  return ListView(children: [
                    for (final p in l)
                      ListTile(
                        leading: _Thumb('${p['image_url'] ?? ''}', 48),
                        title: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(money(p['price_minor'] as num, '${p['currency']}')),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ]);
                },
              ),
            ),
          ]),
        ),
      );
}

class _Thumb extends StatelessWidget {
  final String url;
  final double size;
  const _Thumb(this.url, this.size);
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: url.startsWith('http')
              ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: C.mint, child: Icon(Icons.image_not_supported_outlined, color: C.muted)))
              : Container(color: C.mint, child: Icon(Icons.shopping_bag_outlined, color: C.green)),
        ),
      );
}

/// Carte produit dans la messagerie : photo, prix, stock, caractéristiques et bouton « Voir le produit ».
class ChatProductCard extends StatefulWidget {
  final String productId;
  final bool banner;
  final bool onDark;
  const ChatProductCard({super.key, required this.productId, this.banner = false, this.onDark = false});
  @override
  State<ChatProductCard> createState() => _ChatProductCardState();
}

class _ChatProductCardState extends State<ChatProductCard> {
  late final Future<Map<String, dynamic>> f = Repo.productById(widget.productId, requireStock: false);

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(10), child: LinearProgressIndicator(minHeight: 2));
          if (s.hasError || s.data == null) {
            return Padding(padding: const EdgeInsets.all(10), child: Text('Produit indisponible (retiré ou non publié).', style: TextStyle(color: widget.onDark ? Colors.white70 : C.muted)));
          }
          final p = s.data!;
          final stock = (p['stock'] as num?)?.toInt() ?? 0;
          final cat = (p['categories'] as Map?)?['name'] as String?;
          final attrs = Map<String, dynamic>.from((p['attributes'] as Map?) ?? const {});
          final sizes = attrs.remove('sizes');
          final colors = attrs.remove('colors');
          attrs.remove('public');
          final lines = <String>[
            if (cat != null) 'Catégorie : $cat',
            if (sizes is List && sizes.isNotEmpty) 'Tailles : ${sizes.join(', ')}',
            if (colors is List && colors.isNotEmpty) 'Couleurs : ${colors.map((c) => c is Map ? '${c['name']}' : '$c').join(', ')}',
            for (final e in attrs.entries.take(4)) '${specLabel(cat, e.key)} : ${e.value is List ? (e.value as List).join(', ') : e.value}',
          ];
          final fg = widget.onDark ? Colors.white : C.ink;
          return Container(
            margin: widget.banner ? const EdgeInsets.fromLTRB(12, 8, 12, 0) : EdgeInsets.zero,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: widget.onDark ? Colors.white12 : C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: widget.onDark ? Colors.white24 : C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Thumb('${p['image_url'] ?? ''}', 70),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: fg, fontSize: 15)),
                    Text(money(p['price_minor'] as num, '${p['currency']}'), style: TextStyle(fontWeight: FontWeight.w800, color: widget.onDark ? Colors.white : C.green)),
                    Text(stock > 0 ? 'En stock : $stock${p['unit_label'] != null ? ' ${p['unit_label']}' : ''}' : 'Épuisé', style: TextStyle(color: stock > 0 ? (widget.onDark ? Colors.white70 : C.muted) : C.terracotta, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
              if (lines.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(lines.join('\n'), style: TextStyle(color: widget.onDark ? Colors.white70 : C.muted, fontSize: 12, height: 1.35))),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: widget.onDark ? Colors.white : C.green, side: BorderSide(color: widget.onDark ? Colors.white54 : C.green)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(p))),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Voir le produit'),
                ),
              ),
            ]),
          );
        },
      );
}

/// Contenu d'une bulle de message selon son type (texte, photo, vidéo, fichier, produit).
class ChatMessageBody extends StatelessWidget {
  final Map<String, dynamic> m;
  final bool mine;
  const ChatMessageBody({super.key, required this.m, required this.mine});

  @override
  Widget build(BuildContext context) {
    final kind = '${m['kind'] ?? 'text'}';
    final fg = mine ? Colors.white : C.ink;
    final body = '${m['body']}';
    final style = TextStyle(color: fg, fontSize: 16);
    final isLabel = body.startsWith('📷 ') || body.startsWith('🎬 ') || body.startsWith('📎 ') || body.startsWith('🛍 ');
    switch (kind) {
      case 'image':
        return _ChatImage(path: '${m['attachment_path']}');
      case 'video':
      case 'file':
        return _ChatFile(m: m, mine: mine, video: kind == 'video');
      case 'product':
        final id = m['product_id'];
        if (id == null) return Text(body, style: style);
        return SizedBox(width: 270, child: ChatProductCard(productId: '$id', onDark: mine));
      default:
        return Text(isLabel ? body : body, style: style);
    }
  }
}

class _ChatImage extends StatelessWidget {
  final String path;
  const _ChatImage({required this.path});
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: ChatMedia.url(path),
        builder: (_, s) {
          if (!s.hasData) return const SizedBox(width: 220, height: 140, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          final url = s.data!;
          return GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, actions: [IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication))]),
                body: Center(child: InteractiveViewer(child: Image.network(url, errorBuilder: (_, __, ___) => const Text('Image non affichable sur cet appareil', style: TextStyle(color: Colors.white))))),
              ),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(url, width: 230, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 230, height: 120, color: C.mint, alignment: Alignment.center, child: Text('Image non affichable\n(format non pris en charge)', textAlign: TextAlign.center, style: TextStyle(color: C.muted)))),
            ),
          );
        },
      );
}

class _ChatFile extends StatelessWidget {
  final Map<String, dynamic> m;
  final bool mine;
  final bool video;
  const _ChatFile({required this.m, required this.mine, required this.video});
  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : C.ink;
    final size = (m['attachment_size'] as num?)?.toInt();
    return InkWell(
      onTap: () async {
        try {
          final url = await ChatMedia.url('${m['attachment_path']}');
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (e) {
          if (context.mounted) toast(context, Repo.err(e));
        }
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(video ? Icons.play_circle_fill : Icons.insert_drive_file_outlined, color: fg, size: 34),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m['attachment_name'] ?? (video ? 'Vidéo' : 'Fichier')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
            Text('${video ? 'Lire la vidéo' : 'Ouvrir'}${size == null ? '' : ' · ${MediaFormats.size(size)}'}', style: TextStyle(color: mine ? Colors.white70 : C.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}
