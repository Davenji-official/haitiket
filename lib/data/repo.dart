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

  static Future<List<Map<String, dynamic>>> products({String q = '', int limit = 24}) async {
    if (!Config.configured) return [];
    var f = _c.from('products').select('id,name,price_minor,currency,description,image_url,stock,shops(name)').eq('status', 'published').gt('stock', 0);
    final t = q.trim().replaceAll(RegExp(r'[%,()]'), ' ');
    if (t.isNotEmpty) f = f.ilike('name', '%$t%');
    final rows = await f.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
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
    final rows = await _c.from('favorites').select('products(id,name,price_minor,currency,description,image_url,stock,shops(name))').eq('user_id', u.id);
    return [for (final r in rows) if (r['products'] != null) Map<String, dynamic>.from(r['products'] as Map)];
  }

  static Future<void> toggleFavorite(String productId) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour utiliser les favoris.';
    final ex = await _c.from('favorites').select('product_id').eq('user_id', u.id).eq('product_id', productId);
    if ((ex as List).isEmpty) {
      await _c.from('favorites').insert({'user_id': u.id, 'product_id': productId});
    } else {
      await _c.from('favorites').delete().eq('user_id', u.id).eq('product_id', productId);
    }
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


  static String err(Object e) => e is PostgrestException ? e.message : '$e';

  static Future<List<Map<String, dynamic>>> myShops() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('shops').select('id,name,status,city').eq('owner_id', u.id).order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> shopProducts(String shopId) async {
    final rows = await _c.from('products').select('id,name,price_minor,currency,stock,status,image_url').eq('shop_id', shopId).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> addProduct(String shopId, String name, int priceMinor, int stock, String? imageUrl, bool publish, {String? description}) async {
    await _c.from('products').insert({'shop_id': shopId, 'description': (description ?? '').trim().isEmpty ? null : description!.trim(), 'name': name, 'price_minor': priceMinor, 'currency': 'HTG', 'stock': stock, 'image_url': (imageUrl ?? '').trim().isEmpty ? null : imageUrl!.trim(), 'status': publish ? 'published' : 'draft'});
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

  static Future<List<Map<String, dynamic>>> createOrders(List<CartLine> lines, String mode, String address) async {
    final res = await _c.rpc('create_orders', params: {
      'p_items': [for (final l in lines) {'product_id': l.id, 'qty': l.qty}],
      'p_mode': mode,
      'p_address': address,
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
      'listing': ['listings', 'id,title,price_minor,currency,city,status,image_url'],
    }[kind]!;
    final rows = await _c.from(cfg[0]).select(cfg[1]).order('created_at', ascending: false).limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> adminSet(String kind, String id, String status, String reason) async {
    await _c.rpc('admin_set_status', params: {'p_kind': kind, 'p_id': id, 'p_status': status, 'p_reason': reason});
  }

  static Future<void> signIn(String email, String pass) => _c.auth.signInWithPassword(email: email, password: pass);
  static Future<void> signUp(String email, String pass) => _c.auth.signUp(email: email, password: pass);
  static Future<void> signOut() => _c.auth.signOut();
}
