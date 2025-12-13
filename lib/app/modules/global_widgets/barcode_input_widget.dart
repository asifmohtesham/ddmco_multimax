import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

class BarcodeInputWidget extends StatefulWidget {
  final TextEditingController? controller;
  final Function(String) onScan;
  final bool isLoading;
  final bool isSuccess;
  final bool hasError;
  final String hintText;
  final String? activeRoute;
  final bool isEmbedded; // Added for form integration

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
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();
  Worker? _scanWorker;

  @override
  void initState() {
    super.initState();
    _textController = widget.controller ?? TextEditingController();

    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) {
        // Route check: if activeRoute is set, only respond if it matches Get.currentRoute
        if (widget.activeRoute != null && Get.currentRoute != widget.activeRoute) {
          return;
        }

        final cleanCode = code.trim();
        _textController.text = cleanCode;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        widget.onScan(cleanCode);
      }
    });
  }

  @override
  void dispose() {
    _scanWorker?.dispose();
    if (widget.controller == null) {
      _textController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Styling based on isEmbedded flag
    final decoration = widget.isEmbedded
        ? null
        : BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 4,
          offset: const Offset(0, -2),
        ),
      ],
    );

    final padding = widget.isEmbedded
        ? EdgeInsets.zero
        : const EdgeInsets.all(16.0);

    final inputBorder = widget.isEmbedded
        ? OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    )
        : OutlineInputBorder(borderRadius: BorderRadius.circular(30));

    final contentPadding = widget.isEmbedded
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 0);

    return Container(
      padding: padding,
      decoration: decoration,
      child: SafeArea(
        bottom: !widget.isEmbedded, // Only padding for floating mode
        child: TextFormField(
          controller: _textController,
          readOnly: widget.isLoading,
          decoration: InputDecoration(
            labelText: widget.isLoading
                ? 'Processing...'
                : (widget.isSuccess
                ? 'Scan Validated'
                : (widget.hasError ? 'Scan Failed' : widget.hintText)),
            border: inputBorder,
            enabledBorder: widget.isEmbedded
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.hasError ? Colors.red : Colors.grey.shade300))
                : (widget.hasError
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.red))
                : null),
            focusedBorder: widget.isEmbedded
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.hasError ? Colors.red : Theme.of(context).primaryColor, width: 2))
                : (widget.hasError
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.red, width: 2))
                : null),
            contentPadding: contentPadding,
            prefixIcon: Icon(Icons.qr_code_scanner, color: widget.isEmbedded ? Colors.grey : null),
            filled: widget.isEmbedded,
            fillColor: widget.isEmbedded
                ? (widget.hasError ? Colors.red.shade50 : (widget.isSuccess ? Colors.green.shade50 : Colors.white))
                : null,
            suffixIcon: widget.isLoading
                ? const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
                : (widget.isSuccess
                ? const Icon(Icons.check_circle, color: Colors.green)
                : (widget.hasError
                ? const Icon(Icons.error, color: Colors.red)
                : IconButton(
              icon: Icon(widget.isEmbedded ? Icons.arrow_forward : Icons.send),
              onPressed: () {
                if (_textController.text.trim().isNotEmpty) {
                  widget.onScan(_textController.text.trim());
                }
              },
            ))),
          ),
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