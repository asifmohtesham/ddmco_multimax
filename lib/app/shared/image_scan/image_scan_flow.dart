// lib/app/shared/image_scan/image_scan_flow.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/shared/image_scan/barcode_highlight_painter.dart';
import 'package:multimax/app/shared/image_scan/image_scan_controller.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';
import 'package:multimax/app/shared/image_scan/item_scan_result_sheet.dart';

/// Entry point for the search-by-image flow.
///
/// Call [run] from any context that has a valid [BuildContext]. It opens the
/// gallery, displays a full-screen scan dialog, and returns the resolved
/// [ImageScanResult], or `null` if the user cancelled at any point.
class ImageScanFlow {
  static Future<ImageScanResult?> run(BuildContext context) async {
    final file =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    if (!context.mounted) return null;

    return showDialog<ImageScanResult>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (_) => _ImageScanDialog(initialImagePath: file.path),
    );
  }
}

// ── Full-screen dialog ─────────────────────────────────────────────────────────

class _ImageScanDialog extends StatefulWidget {
  final String initialImagePath;
  const _ImageScanDialog({required this.initialImagePath});

  @override
  State<_ImageScanDialog> createState() => _ImageScanDialogState();
}

class _ImageScanDialogState extends State<_ImageScanDialog> {
  late final ImageScanController _ctrl;
  late final MobileScannerController _scanner;
  late Worker _stateWorker;
  late String _currentPath;
  final _manualFieldCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialImagePath;
    _scanner = MobileScannerController();
    _ctrl = Get.put(ImageScanController(), tag: 'image_scan_dialog');
    // Use ever() to react to state changes outside the build phase.
    // This is the only safe way to trigger showModalBottomSheet in response
    // to Rx state changes inside a StatefulWidget.
    _stateWorker = ever(_ctrl.scanState, _onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.analyzeImage(_currentPath, _scanner);
    });
  }

  void _onStateChanged(ImageScanState state) {
    if (!mounted) return;
    if (state == ImageScanState.barcodeFound && _ctrl.barcodes.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showBarcodePickerSheet();
      });
    }
  }

  @override
  void dispose() {
    _stateWorker.dispose();
    _scanner.dispose();
    _manualFieldCtrl.dispose();
    Get.delete<ImageScanController>(tag: 'image_scan_dialog');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: const Text('Search by Image'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _ImageLayer(imagePath: _currentPath, controller: _ctrl),
            Obx(() => _buildOverlay(_ctrl.scanState.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(ImageScanState state) {
    switch (state) {
      case ImageScanState.analyzing:
      case ImageScanState.looking:
        return const _LoadingOverlay();
      case ImageScanState.noBarcode:
        return _FallbackOverlay(
          message: 'No barcode detected in this image.',
          onTryAgain: _tryAnotherImage,
          manualController: _manualFieldCtrl,
          onManualSubmit: _ctrl.lookupManual,
        );
      case ImageScanState.unresolvable:
      case ImageScanState.error:
        return _FallbackOverlay(
          message: _ctrl.errorMessage.value,
          onTryAgain: _tryAnotherImage,
          manualController: _manualFieldCtrl,
          onManualSubmit: _ctrl.lookupManual,
        );
      case ImageScanState.found:
      case ImageScanState.notFound:
        return ItemScanResultSheet(
            controller: _ctrl, imagePath: _currentPath);
      case ImageScanState.idle:
        return const _LoadingOverlay();
      case ImageScanState.barcodeFound:
        return const SizedBox.shrink();
    }
  }

  Future<void> _tryAnotherImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    if (!mounted) return;
    _manualFieldCtrl.clear();
    setState(() => _currentPath = file.path);
    await _ctrl.analyzeImage(file.path, _scanner);
  }

  void _showBarcodePickerSheet() {
    final barcodes = _ctrl.barcodes;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Multiple barcodes detected — pick one:',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: barcodes.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.qr_code),
              title: Text(barcodes[i].rawValue ?? '—'),
              subtitle: Text(barcodes[i].format.name),
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (i < barcodes.length) _ctrl.selectBarcode(i);
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Image + highlight layer ────────────────────────────────────────────────────

class _ImageLayer extends StatelessWidget {
  final String imagePath;
  final ImageScanController controller;

  const _ImageLayer({required this.imagePath, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(imagePath), fit: BoxFit.contain),
            if (controller.barcodes.isNotEmpty &&
                controller.imageNaturalSize.value != Size.zero)
              CustomPaint(
                painter: BarcodeHighlightPainter(
                  barcodes: controller.barcodes,
                  imageSize: controller.imageNaturalSize.value,
                  selectedIndex: controller.selectedBarcodeIndex.value,
                ),
              ),
          ],
        ));
  }
}

// ── Loading overlay ────────────────────────────────────────────────────────────

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

// ── Fallback overlay (no barcode / unresolvable / error) ──────────────────────

class _FallbackOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onTryAgain;
  final TextEditingController manualController;
  final ValueChanged<String> onManualSubmit;

  const _FallbackOverlay({
    required this.message,
    required this.onTryAgain,
    required this.manualController,
    required this.onManualSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_search, color: Colors.white70, size: 64),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onTryAgain,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Try another image'),
          ),
          const SizedBox(height: 20),
          const Text('— or —',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: manualController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter item code',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.white70),
                onPressed: () {
                  final code = manualController.text.trim();
                  if (code.isNotEmpty) onManualSubmit(code);
                },
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              final code = v.trim();
              if (code.isNotEmpty) onManualSubmit(code);
            },
          ),
        ],
      ),
    );
  }
}
