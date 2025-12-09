import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

class BarcodeInputWidget extends StatefulWidget {
  final TextEditingController? controller;
  final Function(String) onScan;
  final bool isLoading;
  final bool isSuccess;
  final String hintText;

  /// The named route (e.g., AppRoutes.HOME) where this widget is valid.
  /// If provided, the scanner will ignore broadcasts when Get.currentRoute differs.
  final String? activeRoute;

  const BarcodeInputWidget({
    super.key,
    required this.onScan,
    this.controller,
    this.isLoading = false,
    this.isSuccess = false,
    this.hintText = 'Scan or enter barcode',
    this.activeRoute,
  });

  @override
  State<BarcodeInputWidget> createState() => _BarcodeInputWidgetState();
}

class _BarcodeInputWidgetState extends State<BarcodeInputWidget> {
  late TextEditingController _textController;
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();
  Worker? _scanWorker;

  @override
  void initState() {
    super.initState();
    _textController = widget.controller ?? TextEditingController();

    // Listen to DataWedge scans via the Service
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      log('Scanned Code: $code', name: 'EAN');

      if (code.isNotEmpty) {
        // --- Context Awareness Check ---
        // If an activeRoute is defined, ensure we are currently on that route.
        // This prevents background screens (like Home) from reacting to scans
        // meant for the top-most screen (like a Form).
        if (widget.activeRoute != null && Get.currentRoute != widget.activeRoute) {
          log('Ignoring scan on ${widget.activeRoute} because current route is ${Get.currentRoute}', name: 'BarcodeInput');
          return;
        }

        // "Send ENTER key" in DataWedge Intent Output adds a newline character (or \r).
        // We trim the string to ensure the text field doesn't show the newline
        // and the regex/logic matches correctly.
        final cleanCode = code.trim();

        // 1. Set the Intent output data as the TextInputField value
        _textController.text = cleanCode;

        // Update cursor position to the end of the text
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );

        // 2. Trigger the onScan function automatically
        widget.onScan(cleanCode);
      }
    });
  }

  @override
  void dispose() {
    _scanWorker?.dispose(); // Prevent memory leaks from the ever listener

    // Only dispose _textController if it was created locally
    if (widget.controller == null) {
      _textController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: TextFormField(
          controller: _textController,
          readOnly: widget.isLoading,
          decoration: InputDecoration(
            labelText: widget.isLoading
                ? 'Processing...'
                : (widget.isSuccess ? 'Scan Validated' : widget.hintText),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            prefixIcon: const Icon(Icons.qr_code_scanner),
            suffixIcon: widget.isLoading
                ? const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5)
              ),
            )
                : (widget.isSuccess
                ? const Icon(Icons.check_circle, color: Colors.green)
                : IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {
                // Manual entry trigger works regardless of route check
                // because the user physically interacts with this specific widget.
                if (_textController.text.trim().isNotEmpty) {
                  widget.onScan(_textController.text.trim());
                }
              },
            )
            ),
          ),
          // Handle keyboard "Done" or "Go" action
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty && !widget.isLoading) {
              widget.onScan(value.trim());
            }
          },
        ),
      ),
    );
  }
}