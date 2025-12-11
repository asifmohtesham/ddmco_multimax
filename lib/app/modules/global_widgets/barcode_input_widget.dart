import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

class BarcodeInputWidget extends StatefulWidget {
  final TextEditingController? controller;
  final Function(String) onScan;
  final bool isLoading;
  final bool isSuccess;
  final bool hasError; // Added
  final String hintText;
  final String? activeRoute;

  const BarcodeInputWidget({
    super.key,
    required this.onScan,
    this.controller,
    this.isLoading = false,
    this.isSuccess = false,
    this.hasError = false, // Added default false
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
                : (widget.isSuccess
                ? 'Scan Validated'
                : (widget.hasError ? 'Scan Failed' : widget.hintText)), // Update Label on Error
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            prefixIcon: const Icon(Icons.qr_code_scanner),
            suffixIcon: widget.isLoading
                ? const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
                : (widget.isSuccess
                ? const Icon(Icons.check_circle, color: Colors.green)
                : (widget.hasError
                ? const Icon(Icons.error, color: Colors.red) // Error Icon
                : IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {
                if (_textController.text.trim().isNotEmpty) {
                  widget.onScan(_textController.text.trim());
                }
              },
            ))),
            // Highlight border on error
            enabledBorder: widget.hasError
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.red))
                : null,
            focusedBorder: widget.hasError
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.red, width: 2))
                : null,
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