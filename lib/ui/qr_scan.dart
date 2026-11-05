import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme.dart';

/// Scanne un QR HAITIKET (format HKT1:<commande>:<code>) et renvoie son contenu brut ; la validation est faite par le serveur.
class QrScanScreen extends StatefulWidget {
  final String title;
  const QrScanScreen({super.key, this.title = 'Scanner le QR code'});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool done = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: Stack(children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (done) return;
              final v = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
              if (v == null || !v.startsWith('HKT1:')) return;
              done = true;
              Navigator.of(context).pop(v);
            },
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Placez le QR code du client (ou du vendeur) dans le cadre.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)])),
            ),
          ),
        ]),
      );
}
