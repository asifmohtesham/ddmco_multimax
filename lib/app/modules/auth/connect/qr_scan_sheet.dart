import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/core/widgets/keyboard_safe_bottom_sheet.dart';

class QRScanSheet extends StatefulWidget {
  const QRScanSheet({super.key, required this.onUrlScanned});

  final void Function(String url) onUrlScanned;

  @override
  State<QRScanSheet> createState() => _QRScanSheetState();
}

class _QRScanSheetState extends State<QRScanSheet> {
  late final MobileScannerController _scannerController;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue ?? '';
      if (value.startsWith('http')) {
        _scanned = true;
        Navigator.of(context).pop();
        widget.onUrlScanned(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Scan Instance QR Code',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Point camera at the QR code for your ERP instance',
          style: TextStyle(color: Colors.grey, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 260,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                ),
                Center(
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Opens the QR scanner sheet. [onUrlScanned] is called with the scanned URL
/// string when a valid http/https QR code is detected.
Future<void> showQRScanSheet(
  BuildContext context, {
  required void Function(String url) onUrlScanned,
}) {
  return showKeyboardSafeBottomSheet(
    context: context,
    child: QRScanSheet(onUrlScanned: onUrlScanned),
    isScrollControlled: true,
  );
}
