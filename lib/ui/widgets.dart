import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../ui/product_detail.dart';
import '../data/repo.dart';
import '../theme.dart';

class EmptyState extends StatelessWidget {
  final String title, text;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.title, required this.text, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: C.mint.withValues(alpha: .5), borderRadius: BorderRadius.circular(28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontSize: 16, color: C.muted, height: 1.4)),
          if (action != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ]),
      );
}

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> p;
  const ProductCard(this.p, {super.key});
  @override
  Widget build(BuildContext context) {
    final shop = (p['shops'] as Map?)?['name'] ?? '';
    final img = p['image_url'] as String?;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(p))),
      child: Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: C.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            img == null || img.isEmpty
                ? Container(color: C.mint, child: const Icon(Icons.shopping_basket_outlined, size: 40, color: C.green))
                : Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: C.mint)),
            Positioned(
              right: 6,
              top: 6,
              child: IconButton.filledTonal(
                onPressed: () async {
                  try {
                    await Repo.toggleFavorite(p['id'] as String);
                    if (context.mounted) toast(context, 'Favoris mis à jour');
                  } catch (e) {
                    if (context.mounted) toast(context, '$e');
                  }
                },
                icon: const Icon(Icons.favorite_border, size: 20),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 16)),
            Text('$shop', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(money(p['price_minor'] as num, (p['currency'] ?? 'HTG') as String), style: const TextStyle(fontWeight: FontWeight.w800, color: C.green))),
              InkWell(
                onTap: () {
                  CartStore.add(p);
                  toast(context, 'Ajouté au panier');
                },
                child: const CircleAvatar(radius: 16, backgroundColor: C.ink, child: Icon(Icons.add, size: 18, color: Colors.white)),
              ),
            ]),
          ]),
        ),
      ]),
    ));
  }
}

class ProductGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const ProductGrid(this.items, {super.key});
  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: .74,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (final p in items) ProductCard(p)],
      );
}

class Field extends StatelessWidget {
  final TextEditingController c;
  final String label;
  final bool obscure;
  final TextInputType? type;
  const Field(this.c, this.label, {super.key, this.obscure = false, this.type});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, obscureText: obscure, keyboardType: type, decoration: InputDecoration(labelText: label)),
      );
}


class ImageUploadField extends StatefulWidget {
  final void Function(String? url) onUrl;
  const ImageUploadField({super.key, required this.onUrl});
  @override
  State<ImageUploadField> createState() => _ImageUploadState();
}

class _ImageUploadState extends State<ImageUploadField> {
  String? url;
  bool busy = false;

  Future<void> pick() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
      if (x == null) return;
      final ext = x.name.contains('.') ? x.name.split('.').last.toLowerCase() : 'jpg';
      const mimes = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp'};
      final mime = mimes[ext];
      if (mime == null) throw 'Format non pris en charge (JPEG, PNG ou WebP).';
      setState(() => busy = true);
      final bytes = await x.readAsBytes();
      if (bytes.length > 3 * 1024 * 1024) throw 'Photo trop lourde (3 Mo maximum).';
      final u = await Repo.uploadImage(bytes, ext, mime);
      setState(() => url = u);
      widget.onUrl(u);
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 72,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)),
            child: url == null ? const Icon(Icons.image_outlined, color: C.green) : Image.network(url!, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: busy ? null : pick, icon: const Icon(Icons.photo_library_outlined), label: Text(busy ? 'Envoi…' : (url == null ? 'Ajouter une photo' : 'Changer la photo'))),
        ]),
      );
}
