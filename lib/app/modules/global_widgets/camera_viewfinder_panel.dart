// lib/app/modules/global_widgets/camera_viewfinder_panel.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Collapsible live-viewfinder panel for item sheets.
///
/// Does NOT own [controller] — the caller is responsible for its lifecycle.
/// Each successful scan triggers [onBarcode] and flashes the view green.
class CameraViewfinderPanel extends StatefulWidget {
  final MobileScannerController controller;
  final void Function(String barcode) onBarcode;

  const CameraViewfinderPanel({
    super.key,
    required this.controller,
    required this.onBarcode,
  });

  @override
  State<CameraViewfinderPanel> createState() => _CameraViewfinderPanelState();
}

class _CameraViewfinderPanelState extends State<CameraViewfinderPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;
  late final Animation<double>   _flashOpacity;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashOpacity = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _flash, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;
    _flash.forward(from: 0);
    widget.onBarcode(barcode);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _flashOpacity,
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (_flashOpacity.value > 0)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.green.withValues(alpha: _flashOpacity.value),
                  ),
                ),
            ],
          ),
          child: MobileScanner(
            controller: widget.controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
                return const _InlinePermissionMessage();
              }
              return const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Icon(Icons.error_outline, color: Colors.white54, size: 32),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Inline permission message (shown instead of viewfinder) ──────────────────

class _InlinePermissionMessage extends StatelessWidget {
  const _InlinePermissionMessage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt, color: Colors.white54, size: 40),
            SizedBox(height: 8),
            Text(
              'Camera permission required',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
