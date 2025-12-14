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
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();
  Worker? _scanWorker;

  @override
  void initState() {
    super.initState();
    _textController = widget.controller ?? TextEditingController();

    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) {
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
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    // Distinct styling for Embedded mode to prevent camouflage
    final decoration = widget.isEmbedded
        ? BoxDecoration(
      // Light tint background to create a "Section" feel
      color: primaryColor.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
    )
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

    // Add internal padding for embedded mode to frame the input
    final padding = widget.isEmbedded
        ? const EdgeInsets.all(12.0)
        : const EdgeInsets.all(16.0);

    // Remove border for embedded mode input (container acts as border)
    // or keep it subtle
    final inputBorder = widget.isEmbedded
        ? OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
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
        bottom: !widget.isEmbedded,
        child: Row(
          children: [
            // Embedded Mode: Distinct Icon styling
            if(widget.isEmbedded)
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0,2))
                    ]
                ),
                child: Icon(Icons.qr_code_scanner, color: primaryColor, size: 24),
              ),

            Expanded(
              child: TextFormField(
                controller: _textController,
                readOnly: widget.isLoading,
                decoration: InputDecoration(
                  labelText: widget.isLoading
                      ? 'Processing...'
                      : (widget.isSuccess
                      ? 'Scan Validated'
                      : (widget.hasError ? 'Scan Failed' : widget.hintText)),
                  labelStyle: TextStyle(
                    color: widget.isEmbedded ? Colors.grey.shade700 : null,
                    fontWeight: widget.isEmbedded ? FontWeight.w500 : null,
                  ),
                  border: inputBorder,
                  enabledBorder: widget.isEmbedded
                      ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: widget.hasError ? Colors.red : Colors.transparent))
                      : (widget.hasError
                      ? OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.red))
                      : null),
                  focusedBorder: widget.isEmbedded
                      ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: widget.hasError ? Colors.red : primaryColor, width: 1.5))
                      : (widget.hasError
                      ? OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.red, width: 2))
                      : null),
                  contentPadding: contentPadding,
                  // Hide standard prefix icon in embedded mode as we added a custom one above
                  prefixIcon: widget.isEmbedded
                      ? null
                      : Icon(Icons.qr_code_scanner, color: Colors.grey),
                  filled: widget.isEmbedded,
                  // White background inside the tinted container makes it pop
                  fillColor: Colors.white,
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
                    icon: Icon(
                        widget.isEmbedded ? Icons.arrow_forward : Icons.send,
                        color: widget.isEmbedded ? primaryColor : null
                    ),
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
          ],
        ),
      ),
    );
  }
}