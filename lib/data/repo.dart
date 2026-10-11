import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

SupabaseClient get _c => Supabase.instance.client;
User? currentUser() => Config.configured ? _c.auth.currentUser : null;
String money(num minor, String cur) => '${(minor / 100).toStringAsFixed(2)} $cur';

class CartLine {
  final String id, name, currency;
  final int priceMinor;
  int qty;
  CartLine(this.id, this.name, this.priceMinor, this.currency, this.qty);
}

class CartStore {
  static final lines = ValueNotifier<Map<String, CartLine>>({});
  static int get count => lines.value.values.fold(0, (a, l) => a + l.qty);
  static void add(Map<String, dynamic> p) {
    final m = Map<String, CartLine>.from(lines.value);
    final id = p['id'] as String;
    if (m.containsKey(id)) {
      m[id]!.qty++;
    } else {
      m[id] = CartLine(id, p['name'] as String, (p['price_minor'] as num).toInt(), (p['currency'] ?? 'HTG') as String, 1);
    }
    lines.value = m;
  }

  static void change(String id, int delta) {
    final m = Map<String, CartLine>.from(lines.value);
    final l = m[id];
    if (l == null) return;
    l.qty += delta;
    if (l.qty <= 0) m.remove(id);
    lines.value = m;
  }
}

class Repo {
  static final search = ValueNotifier<String>('');

  static Future<List<Map<String, dynamic>>> products({String q = '', int limit = 24, String? categoryId, int? minMinor, int? maxMinor, String sort = 'recent', String? shopId, String? source}) async {
    if (!Config.configured) return [];
    var f = _c.from('products').select('id,name,price_minor,currency,description,image_url,stock,source,paid_until,unit_label,attributes,category_id,categories(name),shop_id,shops(id,name,lat,lng,kind)').eq('status', 'published').gt('stock', 0);
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
    if (e is PostgrestException) return e.message;
    if (e is FunctionException) {
      final d = e.details;
      if (d is Map && d['error'] != null) return d['error'].toString();
      return 'Service de paiement indisponible pour le moment.';
    }
    return '$e';
  }

  static Future<List<Map<String, dynamic>>> myShops() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('shops').select('id,name,status,city,kind,lat,lng,plan_paid_until,logo_url,banner_url,slogan,color_primary,color_accent').eq('owner_id', u.id).order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> shopProducts(String shopId) async {
    final rows = await _c.from('products').select('id,name,price_minor,currency,stock,status,image_url,source,paid_until').eq('shop_id', shopId).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<String> addProduct(String shopId, String name, int priceMinor, int stock, String? imageUrl, bool publish,
      {String? description, String? categoryId, String source = 'marketplace', Map<String, dynamic>? attributes, String unitLabel = 'unité'}) async {
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

  static Future<void> updateProduct(String id, Map<String, dynamic> patch) async {
    await _c.from('products').update(patch).eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> shopOrders(String shopId) async {
    final rows = await _c.from('orders').select('id,status,total_minor,items_minor,commission_minor,seller_net_minor,currency,delivery_mode,created_at,order_items(name,qty)').eq('shop_id', shopId).order('created_at', ascending: false).limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> myOrders() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('orders').select('id,status,total_minor,items_minor,delivery_minor,currency,delivery_mode,reserved_until,created_at,shops(name),order_items(name,qty,unit_minor)').eq('customer_id', u.id).order('created_at', ascending: false).limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> createOrders(List<CartLine> lines, String mode, String address, [String? coupon]) async {
    final res = await _c.rpc('create_orders', params: {
      'p_items': [for (final l in lines) {'product_id': l.id, 'qty': l.qty}],
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
    final rows = await _c.from('profiles').select('display_name,phone,avatar_url').eq('id', u.id);
    final l = List<Map<String, dynamic>>.from(rows);
    return l.isEmpty ? null : l.first;
  }

  static Future<void> saveProfile(String name, String phone, String? avatar) async {
    final u = currentUser();
    if (u == null) throw 'Connexion requise';
    await _c.from('profiles').upsert({'id': u.id, 'display_name': name, 'phone': phone, 'avatar_url': avatar});
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

  static Future<void> signIn(String email, String pass) => _c.auth.signInWithPassword(email: email, password: pass);
  static Future<void> signUp(String email, String pass) => _c.auth.signUp(email: email, password: pass);
  static Future<void> signOut() => _c.auth.signOut();
}
