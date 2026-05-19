// lib/app/modules/global_widgets/camera_scan_overlay.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScanOverlay extends StatefulWidget {
  const CameraScanOverlay._();

  /// Opens a full-screen camera scanner. Returns the scanned barcode string,
  /// or null if the user cancelled or permission was denied.
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (_) => const CameraScanOverlay._(),
    );
  }

  @override
  State<CameraScanOverlay> createState() => _CameraScanOverlayState();
}

class _CameraScanOverlayState extends State<CameraScanOverlay> {
  late final MobileScannerController _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;
    _scanned = true;
    _controller.stop();
    if (mounted) Navigator.of(context).pop(barcode);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
                return _PermissionDeniedView(
                  onClose: () => Navigator.of(context).pop(),
                );
              }
              return const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Icon(Icons.error_outline, color: Colors.white54, size: 48),
                ),
              );
            },
          ),
          const _ScanWindowOverlay(),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Text(
              'Point at barcode',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan-window overlay (dark mask + corner brackets) ─────────────────────────

class _ScanWindowOverlay extends StatelessWidget {
  const _ScanWindowOverlay();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ScanWindowPainter());
}

class _ScanWindowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const windowSize   = 240.0;
    const cornerLength = 28.0;
    const cornerWidth  = 4.0;

    final cx     = size.width / 2;
    final cy     = size.height / 2;
    final left   = cx - windowSize / 2;
    final top    = cy - windowSize / 2;
    final right  = cx + windowSize / 2;
    final bottom = cy + windowSize / 2;

    final mask = Paint()..color = Colors.black54;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), mask);
    canvas.drawRect(
        Rect.fromLTWH(0, bottom, size.width, size.height - bottom), mask);
    canvas.drawRect(Rect.fromLTWH(0, top, left, windowSize), mask);
    canvas.drawRect(
        Rect.fromLTWH(right, top, size.width - right, windowSize), mask);

    final bracket = Paint()
      ..color      = Colors.white
      ..strokeWidth = cornerWidth
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.square;

    // Top-left
    canvas.drawLine(Offset(left, top + cornerLength), Offset(left, top), bracket);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), bracket);
    // Top-right
    canvas.drawLine(Offset(right - cornerLength, top), Offset(right, top), bracket);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLength), bracket);
    // Bottom-left
    canvas.drawLine(
        Offset(left, bottom - cornerLength), Offset(left, bottom), bracket);
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLength, bottom), bracket);
    // Bottom-right
    canvas.drawLine(
        Offset(right - cornerLength, bottom), Offset(right, bottom), bracket);
    canvas.drawLine(
        Offset(right, bottom), Offset(right, bottom - cornerLength), bracket);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Permission-denied view ────────────────────────────────────────────────────

class _PermissionDeniedView extends StatelessWidget {
  final VoidCallback onClose;
  const _PermissionDeniedView({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Camera permission required',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Allow camera access in Settings to scan barcodes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: onClose,
                child: const Text('Close',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
