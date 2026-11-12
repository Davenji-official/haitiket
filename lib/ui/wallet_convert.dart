import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'widgets.dart';

String _uuid4() {
  final r = math.Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

/// Conversion entre ses propres portefeuilles HTG et USD, au taux fixé par l'administration.
Future<bool?> showWalletConvert(BuildContext context, {required int htgMinor, required int usdMinor}) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ConvertSheet(htgMinor: htgMinor, usdMinor: usdMinor),
      ),
    );

class _ConvertSheet extends StatefulWidget {
  final int htgMinor, usdMinor;
  const _ConvertSheet({required this.htgMinor, required this.usdMinor});
  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  String from = 'HTG';
  final amount = TextEditingController();
  Map<String, dynamic>? quote;
  String? error;
  bool busy = false;
  Timer? debounce;
  final String request = _uuid4(); // identifiant unique : un double clic ne convertit qu'une fois

  int get available => from == 'HTG' ? widget.htgMinor : widget.usdMinor;
  int? get minor {
    final v = double.tryParse(amount.text.trim().replaceAll(',', '.'));
    return v == null ? null : (v * 100).round();
  }

  @override
  void dispose() {
    debounce?.cancel();
    amount.dispose();
    super.dispose();
  }

  void changed() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), refreshQuote);
  }

  Future<void> refreshQuote() async {
    final m = minor;
    if (m == null || m <= 0) {
      if (mounted) setState(() { quote = null; error = null; });
      return;
    }
    try {
      final q = await Repo.walletConversionQuote(from, m);
      if (mounted) setState(() { quote = q; error = null; });
    } catch (e) {
      if (mounted) setState(() { quote = null; error = Repo.err(e); });
    }
  }

  Future<void> submit() async {
    final m = minor;
    if (m == null || m <= 0) return toast(context, 'Entrez un montant.');
    if (m > available) return toast(context, 'Solde $from insuffisant.');
    setState(() => busy = true);
    try {
      await Repo.walletConvert(from, m, request);
      if (mounted) {
        toast(context, 'Conversion effectuée.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        toast(context, Repo.err(e));
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final to = from == 'HTG' ? 'USD' : 'HTG';
    final q = quote;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Convertir entre mes portefeuilles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink)),
          Text('Taux fixé par HAITIKET. Aucune conversion implicite : vous voyez le résultat avant de confirmer.', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('HTG → USD'), selected: from == 'HTG', onSelected: (_) => setState(() { from = 'HTG'; quote = null; amount.clear(); error = null; })),
            ChoiceChip(label: const Text('USD → HTG'), selected: from == 'USD', onSelected: (_) => setState(() { from = 'USD'; quote = null; amount.clear(); error = null; })),
          ]),
          const SizedBox(height: 6),
          Text('Solde $from disponible : ${money(available, from)}', style: TextStyle(color: C.green, fontWeight: FontWeight.w800)),
          TextField(controller: amount, onChanged: (_) => changed(), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Montant à convertir en $from')),
          const SizedBox(height: 8),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          if (q != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vous recevrez ${money((q['to_minor'] as num), to)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink)),
                Text('Taux : 1 USD = ${(q['rate'] as num).toStringAsFixed(2)} HTG${((q['fee_minor'] as num?) ?? 0) > 0 ? ' · frais ${money(q['fee_minor'] as num, to)}' : ' · sans frais'}', style: TextStyle(color: C.muted)),
              ]),
            ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: busy || q == null ? null : submit, child: Text(busy ? 'Conversion…' : 'Confirmer la conversion'))),
        ]),
      ),
    );
  }
}
