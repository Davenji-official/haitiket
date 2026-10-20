import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

SupabaseClient get _c => Supabase.instance.client;
User? currentUser() => Config.configured ? _c.auth.currentUser : null;
String money(num minor, String cur) => '${(minor / 100).toStringAsFixed(2)} $cur';

class CartLine {
  final String key, productId, name, currency;
  final String? variantId, variantLabel;
  final int basePrice;
  final List<Map<String, dynamic>> tiers;
  int qty;
  CartLine({required this.key, required this.productId, required this.name, required this.currency, required this.basePrice, required this.tiers, this.variantId, this.variantLabel, this.qty = 1});
}

class CartStore {
  static final lines = ValueNotifier<Map<String, CartLine>>({});
  static int get count => lines.value.values.fold(0, (a, l) => a + l.qty);
  static int totalQtyOf(String productId) => lines.value.values.where((l) => l.productId == productId).fold(0, (a, l) => a + l.qty);

  /// Prix unitaire estimé selon les paliers (le serveur recalcule le prix final).
  static int unitFor(CartLine l) {
    final tq = totalQtyOf(l.productId);
    var price = l.basePrice;
    var best = 0;
    for (final t in l.tiers) {
      final m = (t['min_qty'] as num).toInt();
      if (m <= tq && m >= best) {
        best = m;
        price = (t['unit_price_minor'] as num).toInt();
      }
    }
    return price;
  }

  static int get totalMinor => lines.value.values.fold(0, (a, l) => a + unitFor(l) * l.qty);
  static bool hasVariants(Map<String, dynamic> p) => ((p['product_variants'] as List?) ?? const []).isNotEmpty;

  static void add(Map<String, dynamic> p, {Map<String, dynamic>? variant, int quantity = 1}) {
    if (quantity < 1) return;
    final m = Map<String, CartLine>.from(lines.value);
    final id = p['id'] as String;
    final key = variant == null ? id : '$id|${variant['id']}';
    if (m.containsKey(key)) {
      m[key]!.qty += quantity;
    } else {
      final label = variant == null ? null : [variant['size'], variant['color_name'], variant['audience'], variant['unit_label']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
      m[key] = CartLine(
        key: key,
        productId: id,
        name: p['name'] as String,
        currency: (p['currency'] ?? 'HTG') as String,
        basePrice: ((variant?['price_minor'] as num?) ?? (p['price_minor'] as num)).toInt(),
        tiers: List<Map<String, dynamic>>.from(((p['product_tiers'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map))),
        variantId: variant?['id'] as String?,
        variantLabel: label,
      );
    }
    lines.value = m;
  }

  static void change(String key, int delta) {
    final m = Map<String, CartLine>.from(lines.value);
    final l = m[key];
    if (l == null) return;
    l.qty += delta;
    if (l.qty <= 0) m.remove(key);
    lines.value = m;
  }
}

/// Traduit une erreur technique en message compréhensible (et indique quand la base n'est pas à jour).
String friendlyError(Object? e) {
  if (e is PostgrestException) {
    final m = e.message;
    if (e.code == 'PGRST205' || e.code == '42P01' || m.contains('Could not find the table')) {
      return "La base de données n'est pas à jour : une table est manquante. Exécutez dans Supabase (SQL Editor) les fichiers SQL de migration manquants, dans l'ordre. Détail : $m";
    }
    if (e.code == 'PGRST202' || m.contains('Could not find the function')) {
      return "La base de données n'est pas à jour : une fonction est manquante. Exécutez les fichiers SQL de migration manquants. Détail : $m";
    }
    if (e.code == '42703' || e.code == 'PGRST200' || e.code == 'PGRST204' || (m.contains('column') && m.contains('does not exist'))) {
      return "La base de données n'est pas à jour : une colonne ou une relation est manquante. Exécutez les fichiers SQL de migration manquants. Détail : $m";
    }
    if (e.code == '42501' || m.toLowerCase().contains('permission denied') || m.toLowerCase().contains('row-level security')) {
      return 'Accès refusé par les règles de sécurité de la base.';
    }
    return m;
  }
  if (e is AuthException) return e.message;
  final s = '$e';
  if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup') || s.contains('XMLHttpRequest')) {
    return 'Connexion impossible : vérifiez votre connexion Internet.';
  }
  return s.length > 220 ? s.substring(0, 220) : s;
}

class Repo {
  static final search = ValueNotifier<String>('');

  static Future<List<Map<String, dynamic>>> products({String q = '', int limit = 24, String? categoryId, int? minMinor, int? maxMinor, String sort = 'recent', String? shopId, String? source}) async {
    if (!Config.configured) return [];
    var f = _c.from('products').select('id,name,price_minor,currency,description,image_url,stock,source,paid_until,unit_label,attributes,category_id,categories(name),shop_id,product_tiers(min_qty,unit_price_minor,label),product_variants(id,size,color_name,color_hex,stock,audience,sku,unit_label,price_minor,attributes),shops(id,name,lat,lng,kind)').eq('status', 'published').gt('stock', 0);
    final t = q.trim().replaceAll(RegExp(r'[%,()]'), ' ');
    if (t.isNotEmpty) f = f.ilike('name', '%$t%');
    if (categoryId != null) f = f.eq('category_id', categoryId);
    if (minMinor != null) f = f.gte('price_minor', minMinor);
    if (maxMinor != null) f = f.lte('price_minor', maxMinor);
    if (shopId != null) f = f.eq('shop_id', shopId);
    if (source != null) f = f.eq('source', source);
    final rows = switch (sort) {
      'price_asc' => await f.order('price_minor', ascending: true).limit(limit),
      'price_desc' => await f.order('price_minor', ascending: false).limit(limit),
      _ => await f.order('created_at', ascending: false).limit(limit),
    };
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<Map<String, dynamic>> shopInfo(String id) async {
    return Map<String, dynamic>.from(await _c.from('shops').select('id,name,city,lat,lng,kind,logo_url,banner_url,slogan,color_primary,color_accent').eq('id', id).single());
  }

  static Future<List<Map<String, dynamic>>> categories() async {
    if (!Config.configured) return [];
    final rows = await _c.from('categories').select('id,name').eq('active', true).order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> shopsGeo({String? kind}) async {
    if (!Config.configured) return [];
    var f = _c.from('shops').select('id,name,city,lat,lng,kind,logo_url,slogan,color_primary,color_accent').eq('status', 'active').not('lat', 'is', null);
    if (kind != null) f = f.eq('kind', kind);
    final rows = await f;
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<Map<String, dynamic>> shopRating(String shopId) async {
    final r = await _c.rpc('shop_rating', params: {'p_shop': shopId});
    final l = List<Map<String, dynamic>>.from(r as List);
    return l.isEmpty ? {'avg_rating': null, 'n': 0} : l.first;
  }

  static Future<List<Map<String, dynamic>>> shopReviews(String shopId) async {
    final rows = await _c.from('reviews').select('rating,comment,created_at').eq('shop_id', shopId).order('created_at', ascending: false).limit(20);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> setShopLocation(String shopId, double lat, double lng) async {
    await _c.rpc('set_shop_location', params: {'p_shop': shopId, 'p_lat': lat, 'p_lng': lng});
  }

  static Future<String?> getOrderPin(String orderId) async {
    final r = await _c.rpc('get_order_pin', params: {'p_order': orderId});
    return r as String?;
  }

  static Future<bool> confirmHandover(String orderId, String pin) async => (await _c.rpc('confirm_handover', params: {'p_order': orderId, 'p_pin': pin})) == true;
  static Future<bool> confirmPickup(String jobId, String pin) async => (await _c.rpc('confirm_pickup', params: {'p_job': jobId, 'p_pin': pin})) == true;
  static Future<bool> confirmDelivery(String jobId, String pin) async => (await _c.rpc('confirm_delivery', params: {'p_job': jobId, 'p_pin': pin})) == true;

  static Future<void> sellerSetOrderStatus(String orderId, String to) async {
    await _c.rpc('seller_set_order_status', params: {'p_order': orderId, 'p_to': to});
  }

  static Future<void> createReview(String orderId, int rating, String comment) async {
    await _c.rpc('create_review', params: {'p_order': orderId, 'p_rating': rating, 'p_comment': comment});
  }

  static Future<List<Map<String, dynamic>>> myNotifications() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('notifications').select('id,kind,title,body,created_at,read_at').eq('user_id', u.id).order('created_at', ascending: false).limit(60);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Stream<List<Map<String, dynamic>>> notificationStream() {
    final u = currentUser();
    if (u == null) return const Stream.empty();
    return _c.from('notifications').stream(primaryKey: ['id']).eq('user_id', u.id);
  }

  static Future<void> markNotificationsRead() async {
    await _c.rpc('mark_notifications_read');
  }

  static Future<Map<String, dynamic>> myReferral() async {
    final r = await _c.rpc('my_referral');
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<void> applyReferral(String code) async {
    await _c.rpc('apply_referral', params: {'p_code': code});
  }

  static Future<List<Map<String, dynamic>>> adminCoupons() async {
    final rows = await _c.from('coupons').select('id,code,kind,value,used_count,max_uses,active,expires_at').order('created_at', ascending: false).limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> adminCreateCoupon(String code, String kind, int value, int minMinor, int? maxUses, int days) async {
    await _c.rpc('admin_create_coupon', params: {'p_code': code, 'p_kind': kind, 'p_value': value, 'p_min': minMinor, 'p_max_uses': maxUses, 'p_days': days});
  }

  static Future<void> adminSetCouponActive(String id, bool active) async {
    await _c.rpc('admin_set_coupon_active', params: {'p_id': id, 'p_active': active});
  }

  static Future<List<Map<String, dynamic>>> listings() async {
    if (!Config.configured) return [];
    final rows = await _c.from('listings').select('id,title,price_minor,currency,city,image_url,condition').eq('status', 'published').order('created_at', ascending: false).limit(40);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<int> activeShops() async {
    if (!Config.configured) return 0;
    final rows = await _c.from('shops').select('id').eq('status', 'active').limit(1000);
    return (rows as List).length;
  }

  static Future<List<Map<String, dynamic>>> favorites() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('favorites').select('products(id,name,price_minor,currency,description,image_url,stock,shop_id,shops(id,name,lat,lng))').eq('user_id', u.id);
    return [for (final r in rows) if (r['products'] != null) Map<String, dynamic>.from(r['products'] as Map)];
  }

  static Future<void> loadFavorites() async {
    final u = currentUser();
    if (u == null) {
      favIds.value = <String>{};
      return;
    }
    try {
      final rows = await _c.from('favorites').select('product_id').eq('user_id', u.id);
      favIds.value = {for (final r in rows) r['product_id'] as String};
    } catch (_) {}
  }

  static Future<bool> toggleFavorite(String productId) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour utiliser les favoris.';
    final now = Set<String>.from(favIds.value);
    if (now.contains(productId)) {
      await _c.from('favorites').delete().eq('user_id', u.id).eq('product_id', productId);
      now.remove(productId);
      favIds.value = now;
      return false;
    }
    await _c.from('favorites').insert({'user_id': u.id, 'product_id': productId});
    now.add(productId);
    favIds.value = now;
    return true;
  }

  static Future<void> createShop(String name, String city) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour ouvrir une boutique.';
    await _c.from('shops').insert({'owner_id': u.id, 'name': name, 'city': city, 'status': 'pending'});
  }

  static Future<void> createListingDraft(String title, int priceMinor, String city, [String? imageUrl]) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour publier une annonce.';
    await _c.from('listings').insert({'seller_id': u.id, 'title': title, 'price_minor': priceMinor, 'currency': 'HTG', 'city': city, 'image_url': imageUrl, 'status': 'draft'});
  }

  static Future<void> applyCourier(String name, String phone, String transport, String zone) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour déposer une candidature.';
    await _c.from('courier_applications').insert({'user_id': u.id, 'full_name': name, 'phone': phone, 'transport': transport, 'zone': zone});
  }


  static final favIds = ValueNotifier<Set<String>>(<String>{});

  static String err(Object e) {
    if (e is FunctionException) {
      final d = e.details;
      if (d is Map && d['error'] != null) return d['error'].toString();
      return 'Service de paiement indisponible pour le moment.';
    }
    return friendlyError(e);
  }

  static Future<List<Map<String, dynamic>>> myShops() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('shops').select('id,name,status,city,kind,lat,lng,plan_paid_until,logo_url,banner_url,slogan,color_primary,color_accent').eq('owner_id', u.id).order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> shopProducts(String shopId) async {
    final rows = await _c.from('products').select('id,name,description,price_minor,currency,stock,status,image_url,source,paid_until,unit_label,audience,attributes,category_id,product_variants(id,size,color_name,color_hex,stock,audience,sku,unit_label,price_minor,attributes)').eq('shop_id', shopId).neq('status', 'removed').order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<String> addProduct(String shopId, String name, int priceMinor, int stock, String? imageUrl, bool publish,
      {String? description, String? categoryId, String source = 'marketplace', Map<String, dynamic>? attributes, String unitLabel = 'unité', String? audience}) async {
    final r = await _c.from('products').insert({
      'shop_id': shopId,
      'source': source,
      'category_id': categoryId,
      'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
      'name': name,
      'price_minor': priceMinor,
      'currency': 'HTG',
      'stock': stock,
      'image_url': (imageUrl ?? '').trim().isEmpty ? null : imageUrl!.trim(),
      'attributes': attributes ?? <String, dynamic>{},
      'unit_label': unitLabel,
      'audience': audience,
      'status': publish ? 'published' : 'draft',
    }).select('id').single();
    return r['id'] as String;
  }

  static Future<void> addProductMedia(String productId, List<Map<String, String>> media) async {
    if (media.isEmpty) return;
    await _c.from('product_media').insert([
      for (var i = 0; i < media.length; i++) {'product_id': productId, 'url': media[i]['url'], 'kind': media[i]['kind'], 'position': i},
    ]);
  }

  static Future<List<Map<String, dynamic>>> productMedia(String productId) async {
    final rows = await _c.from('product_media').select('url,kind,position').eq('product_id', productId).order('position');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> replaceProductVariants(String productId, List<Map<String, dynamic>> variants) async {
    if (variants.length > 100) throw ArgumentError('100 variantes maximum.');
    final existingRows = await _c.from('product_variants').select('id,size,color_name').eq('product_id', productId);
    final existing = List<Map<String, dynamic>>.from(existingRows);
    final usedIds = <String>{};
    final normalized = <String>{};
    String key(Map<String, dynamic> v) => '${(v['size'] ?? '').toString().trim().toLowerCase()}|${(v['color_name'] ?? '').toString().trim().toLowerCase()}';
    for (final v in variants) {
      if ((v['size'] ?? '').toString().trim().isEmpty && (v['color_name'] ?? '').toString().trim().isEmpty) {
        throw ArgumentError('Chaque variante doit avoir une taille ou une couleur.');
      }
      if (!normalized.add(key(v))) throw ArgumentError('Deux variantes ne peuvent pas avoir la même taille et couleur.');
      Map<String, dynamic>? match;
      for (final candidate in existing) { if (key(candidate) == key(v)) { match = candidate; break; } }
      final payload = <String, dynamic>{
        'product_id': productId, 'size': v['size'], 'color_name': v['color_name'], 'color_hex': v['color_hex'], 'stock': v['stock'] ?? 0,
        'audience': v['audience'], 'sku': v['sku'], 'unit_label': v['unit_label'] ?? 'unité', 'price_minor': v['price_minor'], 'attributes': v['attributes'] ?? <String, dynamic>{},
      };
      if (match != null) {
        final id = match['id'] as String; usedIds.add(id);
        await _c.from('product_variants').update(payload).eq('id', id);
      } else {
        final row = await _c.from('product_variants').insert(payload).select('id').single();
        usedIds.add(row['id'] as String);
      }
    }
    // Keep variants referenced by past orders to preserve foreign keys and audit history.
    for (final old in existing) {
      final id = old['id'] as String;
      if (usedIds.contains(id)) continue;
      final refs = await _c.from('order_items').select('id').eq('variant_id', id).limit(1);
      if ((refs as List).isNotEmpty) {
        await _c.from('product_variants').update({'stock': 0}).eq('id', id);
      } else {
        await _c.from('product_variants').delete().eq('id', id);
      }
    }
  }
  static Future<List<Map<String, dynamic>>> productVariants(String productId) async {
    final rows = await _c.from('product_variants').select('id,size,color_name,color_hex,stock,audience,sku,unit_label,price_minor,attributes').eq('product_id', productId).order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }
  static Future<List<Map<String, dynamic>>> productTiers(String productId) async {
    final rows = await _c.from('product_tiers').select('min_qty,unit_price_minor,label').eq('product_id', productId).order('min_qty');
    return List<Map<String, dynamic>>.from(rows);
  }
  static Future<void> replaceProductTiers(String productId, List<Map<String, dynamic>> tiers) async {
    if (tiers.length > 30) throw ArgumentError('30 tarifs dégressifs maximum.');
    await _c.from('product_tiers').delete().eq('product_id', productId);
    if (tiers.isNotEmpty) await _c.from('product_tiers').insert([for (final t in tiers) {'product_id': productId, 'min_qty': t['min_qty'], 'unit_price_minor': t['unit_price_minor'], 'label': t['label']}]);
  }

  /// Remplace la galerie d'un produit après validation des droits par RLS.
  /// La première image devient aussi la couverture principale.
  static Future<void> replaceProductMedia(String productId, List<Map<String, String>> media) async {
    if (media.length > 10) throw ArgumentError('10 médias maximum par produit.');
    await _c.from('product_media').delete().eq('product_id', productId);
    if (media.isNotEmpty) {
      await _c.from('product_media').insert([
        for (var i = 0; i < media.length; i++) {
          'product_id': productId,
          'url': media[i]['url'],
          'kind': media[i]['kind'] ?? 'image',
          'position': i,
        },
      ]);
    }
    Map<String, String>? firstImage;
    for (final item in media) {
      if (item['kind'] == 'image') { firstImage = item; break; }
    }
    await _c.from('products').update({
      'image_url': firstImage?['url'],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', productId);
  }

  static Future<void> updateProduct(String id, Map<String, dynamic> patch) async {
    const allowed = {'name', 'description', 'price_minor', 'stock', 'image_url', 'attributes', 'unit_label', 'audience', 'status', 'category_id', 'currency'};
    final safe = Map<String, dynamic>.fromEntries(patch.entries.where((e) => allowed.contains(e.key)));
    if (safe.isEmpty) throw ArgumentError('Aucune modification valide.');
    safe['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _c.from('products').update(safe).eq('id', id);
  }

  /// Suppression logique : le produit disparaît du catalogue sans casser l'historique des commandes.
  static Future<void> deleteProduct(String id) async {
    await _c.from('products').update({'status': 'removed', 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  static Future<void> deleteNotification(String id) async {
    final u = currentUser();
    if (u == null) throw StateError('Connexion requise.');
    await _c.from('notifications').delete().eq('id', id).eq('user_id', u.id);
  }

  static Future<List<Map<String, dynamic>>> shopOrders(String shopId) async {
    final rows = await _c.from('orders').select('id,status,total_minor,items_minor,commission_minor,seller_net_minor,currency,delivery_mode,created_at,order_items(name,qty,variant_label)').eq('shop_id', shopId).order('created_at', ascending: false).limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> myOrders() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('orders').select('id,status,total_minor,items_minor,delivery_minor,currency,delivery_mode,reserved_until,created_at,shops(name),order_items(name,qty,unit_minor,variant_label)').eq('customer_id', u.id).order('created_at', ascending: false).limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> createOrders(List<CartLine> lines, String mode, String address, [String? coupon]) async {
    final res = await _c.rpc('create_orders', params: {
      'p_items': [for (final l in lines) {'product_id': l.productId, 'variant_id': l.variantId, 'qty': l.qty}],
      'p_mode': mode,
      'p_address': address,
      'p_coupon': (coupon ?? '').trim().isEmpty ? null : coupon!.trim(),
    });
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<void> cancelOrder(String id) async {
    await _c.rpc('cancel_order', params: {'p_order': id});
  }

  static Future<String> uploadImage(Uint8List bytes, String ext, String mime) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour envoyer une photo.';
    final path = '${u.id}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _c.storage.from('media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    return _c.storage.from('media').getPublicUrl(path);
  }

  static Future<bool> adminUnlock(String code) async {
    final r = await _c.rpc('admin_unlock', params: {'p_code': code});
    return r == true;
  }

  static Future<List<Map<String, dynamic>>> adminList(String kind) async {
    final cfg = {
      'shop': ['shops', 'id,name,city,status'],
      'courier': ['courier_applications', 'id,full_name,phone,transport,zone,status'],
      'listing': ['products', 'id,name,price_minor,currency,status,paid_until'],
      'ticket': ['support_tickets', 'id,subject,message,status,admin_reply'],
      'payment': ['payment_attempts', 'id,purpose,amount_minor,status'],
      'dispute': ['order_disputes', 'id,order_id,reason,status'],
      'refund': ['refund_requests', 'id,order_id,amount_minor,status,reason'],
      'report': ['reports', 'id,kind,target_id,reason,status'],
    }[kind]!;
    var q = _c.from(cfg[0]).select(cfg[1]);
    if (kind == 'listing') q = q.eq('source', 'bazar');
    final rows = await q.order('created_at', ascending: false).limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> adminSet(String kind, String id, String status, String reason) async {
    await _c.rpc('admin_set_status', params: {'p_kind': kind, 'p_id': id, 'p_status': status, 'p_reason': reason});
  }

  static Future<String> startConversation(String kind, String ref) async {
    final r = await _c.rpc('start_conversation', params: {'p_kind': kind, 'p_ref': ref});
    return r as String;
  }

  static Future<List<Map<String, dynamic>>> myConversations() async {
    final rows = await _c.from('conversations').select('id,subject,created_at,messages(body,created_at)').order('created_at', ascending: false).limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<String> conversationSubject(String id) async {
    final r = await _c.from('conversations').select('subject').eq('id', id).single();
    return r['subject'] as String;
  }

  static Stream<List<Map<String, dynamic>>> messageStream(String cid) =>
      _c.from('messages').stream(primaryKey: ['id']).eq('conversation_id', cid).order('created_at', ascending: true);

  static Future<void> sendMessage(String cid, String body) async {
    final u = currentUser();
    if (u == null) throw 'Connexion requise';
    await _c.from('messages').insert({'conversation_id': cid, 'sender_id': u.id, 'body': body});
  }

  static Future<Map<String, dynamic>?> myCourierApplication() async {
    final u = currentUser();
    if (u == null) return null;
    final rows = await _c.from('courier_applications').select('status,transport,zone').eq('user_id', u.id).order('created_at', ascending: false).limit(1);
    final l = List<Map<String, dynamic>>.from(rows);
    return l.isEmpty ? null : l.first;
  }

  static Future<bool> courierAvailable() async {
    final u = currentUser();
    if (u == null) return false;
    final rows = await _c.from('courier_status').select('available').eq('user_id', u.id);
    final l = List<Map<String, dynamic>>.from(rows);
    return l.isNotEmpty && l.first['available'] == true;
  }

  static Future<void> setCourierAvailable(bool v) async {
    await _c.rpc('set_courier_available', params: {'p_available': v});
  }

  static Future<List<Map<String, dynamic>>> openJobs() async {
    final r = await _c.rpc('list_open_jobs');
    return List<Map<String, dynamic>>.from(r as List);
  }

  static Future<void> acceptJob(String id) async {
    await _c.rpc('accept_job', params: {'p_job': id});
  }

  static Future<List<Map<String, dynamic>>> myJobs() async {
    if (currentUser() == null) return [];
    final r = await _c.rpc('my_jobs');
    return List<Map<String, dynamic>>.from(r as List);
  }

  static Future<Map<String, dynamic>?> getProfile() async {
    final u = currentUser();
    if (u == null) return null;
    final rows = await _c.from('profiles').select('display_name,phone,city,avatar_url').eq('id', u.id);
    final l = List<Map<String, dynamic>>.from(rows);
    return l.isEmpty ? null : l.first;
  }

  static Future<void> saveProfile(String name, String phone, String city, String? avatar) async {
    final u = currentUser();
    if (u == null) throw 'Connexion requise';
    await _c.from('profiles').upsert({'id': u.id, 'display_name': name, 'phone': phone, 'city': city.isEmpty ? null : city, 'avatar_url': avatar});
  }

  static Future<void> createTicket(String subject, String message) async {
    final u = currentUser();
    if (u == null) throw 'Connexion requise';
    await _c.from('support_tickets').insert({'user_id': u.id, 'subject': subject, 'message': message});
  }

  static Future<List<Map<String, dynamic>>> myTickets() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('support_tickets').select('id,subject,status,admin_reply,created_at').eq('user_id', u.id).order('created_at', ascending: false).limit(30);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> adminReplyTicket(String id, String reply) async {
    await _c.rpc('admin_reply_ticket', params: {'p_id': id, 'p_reply': reply});
  }

  // ===== Paiements Bazik =====
  static Future<String> startPayment(String purpose, String targetId) async {
    final res = await _c.functions.invoke('bazik-pay', body: {'action': 'create', 'purpose': purpose, 'target_id': targetId});
    final d = res.data;
    if (d is Map && d['redirectUrl'] != null) return d['redirectUrl'] as String;
    throw (d is Map && d['error'] != null) ? d['error'].toString() : 'Paiement impossible pour le moment.';
  }

  static Future<void> checkPayment(String purpose, String targetId) async {
    try {
      await _c.functions.invoke('bazik-pay', body: {'action': 'check', 'purpose': purpose, 'target_id': targetId});
    } catch (_) {}
  }

  static Future<int?> quoteFee(String kind) async {
    try {
      final r = await _c.rpc('quote_fee', params: {'p_kind': kind});
      return r == null ? null : (r as num).toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<String> ensurePersonalShop(String city) async {
    final r = await _c.rpc('ensure_personal_shop', params: {'p_city': city});
    return r as String;
  }

  static Future<void> updateBranding(String shopId, String? logo, String? banner, String slogan, String? primary, String? accent) async {
    await _c.rpc('update_shop_branding', params: {'p_shop': shopId, 'p_logo': logo, 'p_banner': banner, 'p_slogan': slogan, 'p_primary': primary, 'p_accent': accent});
  }

  static Future<bool> isFollowing(String shopId) async {
    final u = currentUser();
    if (u == null) return false;
    final rows = await _c.from('shop_follows').select('shop_id').eq('user_id', u.id).eq('shop_id', shopId);
    return (rows as List).isNotEmpty;
  }

  static Future<bool> toggleFollow(String shopId) async => (await _c.rpc('toggle_follow', params: {'p_shop': shopId})) == true;

  static Future<Map<String, dynamic>> shopStats(String shopId) async => Map<String, dynamic>.from(await _c.rpc('shop_stats', params: {'p_shop': shopId}) as Map);
  static Future<Map<String, dynamic>> productStats(String id) async => Map<String, dynamic>.from(await _c.rpc('product_stats', params: {'p_product': id}) as Map);

  static Future<void> trackCart(String productId) async {
    if (currentUser() == null) return;
    try {
      await _c.rpc('track_product_event', params: {'p_product': productId, 'p_kind': 'cart'});
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> myWallet() async => Map<String, dynamic>.from(await _c.rpc('my_wallet') as Map);

  static Future<Map<String, dynamic>> myWalletV2() async => Map<String, dynamic>.from(await _c.rpc('my_wallet_v2') as Map);

  static Future<Map<String, dynamic>> startWalletTopup(int amountMinor, String method, {String? phone}) async {
    final r = await _c.functions.invoke('plopplop-wallet', body: {'action':'topup','amount_minor':amountMinor,'currency':'HTG','method':method,'phone':phone});
    if (r.data is! Map || (r.data as Map)['reference'] == null) throw StateError((r.data is Map ? (r.data as Map)['error'] : null)?.toString() ?? 'Recharge impossible.');
    return Map<String,dynamic>.from(r.data as Map);
  }

  static Future<String> checkWalletTopup(String reference) async {
    final r = await _c.functions.invoke('plopplop-wallet', body: {'action':'check_topup','reference':reference});
    if (r.data is! Map) throw StateError('Réponse de vérification invalide.');
    return (r.data as Map)['status']?.toString() ?? 'pending';
  }

  static Future<Map<String, dynamic>> withdrawWallet(int amountMinor, String method, String phone) async {
    final r = await _c.functions.invoke('plopplop-withdraw', body: {
      'action': 'withdraw', 'amount_minor': amountMinor, 'currency': 'HTG', 'method': method, 'phone': phone,
    });
    if (r.data is! Map) throw StateError('Réponse de retrait invalide.');
    final data = Map<String, dynamic>.from(r.data as Map);
    if (r.status >= 400 && data['status'] != 'processing') throw StateError(data['error']?.toString() ?? 'Retrait refusé.');
    return data;
  }

  static Future<String> checkWalletWithdrawal(String reference) async {
    final r = await _c.functions.invoke('plopplop-withdraw', body: {'action':'check_withdrawal','reference':reference});
    if (r.data is! Map) throw StateError('Réponse de vérification invalide.');
    final data = Map<String, dynamic>.from(r.data as Map);
    if (r.status >= 400) throw StateError(data['error']?.toString() ?? 'Vérification du retrait impossible.');
    return data['status']?.toString() ?? 'processing';
  }

  /// Sélection variée (au plus 2 produits par boutique), renouvelée toutes les 15 minutes par l'accueil.
  static Future<List<Map<String, dynamic>>> discover({int take = 8}) async {
    final all = await products(limit: 80);
    all.shuffle();
    final per = <String, int>{};
    final out = <Map<String, dynamic>>[];
    for (final p in all) {
      final s = (p['shop_id'] ?? '') as String;
      if ((per[s] ?? 0) >= 2) continue;
      per[s] = (per[s] ?? 0) + 1;
      out.add(p);
      if (out.length >= take) break;
    }
    return out;
  }

  // ===== Lot 10 : réglages, tableau de bord, adresses, litiges, signalements, comptes =====
  static Future<Map<String, dynamic>> adminDashboard() async => Map<String, dynamic>.from(await _c.rpc('admin_dashboard') as Map);

  static Future<Map<String, String>> adminSettings() async {
    final rows = await _c.from('platform_settings').select('key,value');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  static Future<void> adminSetSetting(String key, String value) async {
    await _c.rpc('admin_set_setting', params: {'p_key': key, 'p_value': value});
  }

  static Future<List<Map<String, dynamic>>> adminSearchUsers(String q) async {
    final r = await _c.rpc('admin_search_users', params: {'p_q': q});
    return List<Map<String, dynamic>>.from(r as List);
  }

  static Future<void> adminSetUserSuspended(String id, bool suspended, String reason) async {
    await _c.rpc('admin_set_user_suspended', params: {'p_user': id, 'p_suspended': suspended, 'p_reason': reason});
  }

  static Future<void> adminResolveDispute(String id, String outcome, String note) async {
    await _c.rpc('admin_resolve_dispute', params: {'p_id': id, 'p_outcome': outcome, 'p_note': note});
  }

  static Future<void> adminMarkRefund(String id, bool executed, String note) async {
    await _c.rpc('admin_mark_refund', params: {'p_id': id, 'p_executed': executed, 'p_note': note});
  }

  static Future<void> adminQueueRefund(String attemptId) async {
    await _c.rpc('admin_queue_refund', params: {'p_attempt': attemptId});
  }

  static Future<void> adminResolveReport(String id, String status, String note) async {
    await _c.rpc('admin_resolve_report', params: {'p_id': id, 'p_status': status, 'p_note': note});
  }

  static Future<void> openDispute(String orderId, String reason) async {
    await _c.rpc('open_dispute', params: {'p_order': orderId, 'p_reason': reason});
  }

  static Future<void> requestCancellation(String orderId) async {
    await _c.rpc('request_cancellation', params: {'p_order': orderId});
  }

  static Future<void> submitReport(String kind, String target, String reason) async {
    await _c.rpc('submit_report', params: {'p_kind': kind, 'p_target': target, 'p_reason': reason});
  }

  static Future<List<Map<String, dynamic>>> myAddresses() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('addresses').select().eq('user_id', u.id).eq('active', true).order('is_default', ascending: false).order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> saveAddress(Map<String, dynamic> a) async {
    final u = currentUser();
    if (u == null) throw 'Connexion requise';
    await _c.from('addresses').insert({...a, 'user_id': u.id});
  }

  static Future<void> deleteAddress(String id) async {
    await _c.from('addresses').update({'active': false, 'is_default': false}).eq('id', id);
  }

  static Future<void> setDefaultAddress(String id) async {
    await _c.rpc('set_default_address', params: {'p_id': id});
  }

  // ===== Lot 11 : variantes, tarifs par quantité, coupons de boutique =====
  static Future<void> addVariants(String productId, List<Map<String, dynamic>> v) async {
    if (v.isEmpty) return;
    await _c.from('product_variants').insert([
      for (final x in v) {'product_id': productId, 'size': x['size'], 'color_name': x['color_name'], 'color_hex': x['color_hex'], 'stock': x['stock']},
    ]);
  }

  static Future<void> addTiers(String productId, List<Map<String, dynamic>> t) async {
    if (t.isEmpty) return;
    await _c.from('product_tiers').insert([
      for (final x in t) {'product_id': productId, 'min_qty': x['min_qty'], 'unit_price_minor': x['unit_price_minor'], 'label': x['label']},
    ]);
  }

  static Future<void> updateVariantStock(String id, int stock) async {
    await _c.from('product_variants').update({'stock': stock}).eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> shopCoupons(String shopId) async {
    final rows = await _c.from('coupons').select('id,code,kind,value,min_items_minor,max_uses,used_count,expires_at,active,visible,product_ids').eq('shop_id', shopId).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> shopCreateCoupon({required String shopId, required String code, required String kind, required int value, required int minMinor, int? maxUses, required int days, List<String>? productIds, required bool visible}) async {
    await _c.rpc('shop_create_coupon', params: {'p_shop': shopId, 'p_code': code, 'p_kind': kind, 'p_value': value, 'p_min': minMinor, 'p_max_uses': maxUses, 'p_days': days, 'p_products': productIds, 'p_visible': visible});
  }

  static Future<void> shopSetCouponActive(String id, bool active) async {
    await _c.rpc('shop_set_coupon_active', params: {'p_id': id, 'p_active': active});
  }

  static Future<List<Map<String, dynamic>>> productPromos(String productId) async {
    try {
      final r = await _c.rpc('product_promos', params: {'p_product': productId});
      return List<Map<String, dynamic>>.from(r as List);
    } catch (_) {
      return [];
    }
  }

  // ===== Comptes =====
  /// Retourne true si une confirmation par e-mail est requise avant la première connexion.
  static Future<bool> signUpFull({required String email, required String password, required String fullName, required String phone, required String city, required String referral}) async {
    final res = await _c.auth.signUp(email: email, password: password, data: {
      'full_name': fullName,
      'phone': phone,
      'city': city,
      'referral_code': referral,
      'accepted_terms': 'true',
      'terms_version': '2026-10',
    });
    return res.session == null;
  }

  static Future<void> resetPassword(String email) => _c.auth.resetPasswordForEmail(email);
  static Future<void> updatePassword(String password) async {
    await _c.auth.updateUser(UserAttributes(password: password));
  }

  static Future<Map<String, dynamic>> myRoles() async {
    final shops = await myShops();
    final app = await myCourierApplication();
    return {'pro': shops.where((s) => s['kind'] == 'pro').length, 'personal': shops.any((s) => s['kind'] == 'personal'), 'courier': app?['status']};
  }

  static Future<void> deleteAccount() async {
    final res = await _c.functions.invoke('delete-account', body: {'confirm': 'SUPPRIMER'});
    final d = res.data;
    if (d is Map && d['error'] != null) throw d['error'].toString();
    await _c.auth.signOut();
  }

  static Future<void> signIn(String email, String pass) => _c.auth.signInWithPassword(email: email, password: pass);
  static Future<void> signUp(String email, String pass) => _c.auth.signUp(email: email, password: pass);
  static Future<void> signOut() => _c.auth.signOut();
}
