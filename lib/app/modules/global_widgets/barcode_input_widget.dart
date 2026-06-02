import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/camera_scan_overlay.dart';

/// BarcodeInputWidget
///
/// Renders the scanner text field and handles MANUAL keyboard / send-button
/// input. Hardware-scan routing (DataWedge EventChannel) is now handled by
/// each consuming Controller's own persistent Worker, so this widget no longer
/// attaches a GetX `ever()` worker to [DataWedgeService.scannedCode].
///
/// The only path that still calls [onScan] from here is:
///   • [onFieldSubmitted]  — user types a barcode and presses Enter
///   • suffix IconButton   — user taps the send icon
///
/// Controllers that need hardware-scan events (e.g. DeliveryNoteFormController)
/// subscribe directly in `onInit` via:
///   ```dart
///   _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
///   ```
class BarcodeInputWidget extends StatefulWidget {
  final TextEditingController? controller;
  final Function(String) onScan;
  final bool isLoading;
  final bool isSuccess;
  final bool hasError;
  /// Accepted for API compatibility. Not currently rendered; wire to
  /// [InputDecoration.hintText] in the future if a placeholder is desired.
  final String hintText;
  final String? activeRoute;
  final bool isEmbedded;

  const BarcodeInputWidget({
    super.key,
    required this.onScan,
    this.controller,
    this.isLoading = false,
    this.isSuccess = false,
    this.hasError = false,
    this.hintText = 'Scan or enter barcode',
    this.activeRoute,
    this.isEmbedded = false,
  });

  @override
  State<BarcodeInputWidget> createState() => _BarcodeInputWidgetState();
}

class _BarcodeInputWidgetState extends State<BarcodeInputWidget> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = widget.controller ?? TextEditingController();
    log('[BarcodeInputWidget] initState — manual-input-only mode (no ever worker)',
        name: 'Scan');
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _textController.dispose();
    }
    super.dispose();
  }

  Widget _buildSuffixIcon(BuildContext context, Color primaryColor) {
    if (widget.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (widget.isSuccess) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (widget.hasError) {
      return const Icon(Icons.error, color: Colors.red);
    }

    final sendButton = IconButton(
      icon: const Icon(Icons.send),
      onPressed: () {
        if (_textController.text.trim().isNotEmpty) {
          widget.onScan(_textController.text.trim());
        }
      },
    );

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!isMobile) return sendButton;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.camera_alt_outlined, color: primaryColor),
          tooltip: 'Scan with camera',
          onPressed: () async {
            final result = await CameraScanOverlay.show(context);
            if (!mounted) return;
            if (result != null && result.isNotEmpty) {
              widget.onScan(result);
            }
          },
        ),
        sendButton,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    final decoration = BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 4,
          offset: const Offset(0, -2),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: decoration,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: !widget.isEmbedded,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _textController,
                readOnly: widget.isLoading,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30)),
                  enabledBorder: widget.hasError
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.red))
                      : null,
                  focusedBorder: widget.hasError
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                              color: Colors.red, width: 2))
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 0),
                  prefixIcon: const Icon(Icons.qr_code_scanner,
                      color: Colors.grey),
                  suffixIcon: _buildSuffixIcon(context, primaryColor),
                ),
                onFieldSubmitted: (value) {
                  if (value.trim().isNotEmpty && !widget.isLoading) {
                    widget.onScan(value.trim());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
