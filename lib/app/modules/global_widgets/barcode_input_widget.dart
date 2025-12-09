import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/services/data_wedge_service.dart';

class BarcodeInputWidget extends StatefulWidget {
  final TextEditingController? controller;
  final Function(String) onScan;
  final bool isLoading;
  final bool isSuccess;
  final String hintText;

  const BarcodeInputWidget({
    super.key,
    required this.onScan,
    this.controller,
    this.isLoading = false,
    this.isSuccess = false,
    this.hintText = 'Scan or enter barcode',
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

    // Listen to DataWedge scans
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) {
        // "Send ENTER key" in DataWedge Intent Output adds a newline character.
        // We trim the string to ensure regex matches and clean display.
        final cleanCode = code.trim();

        // Update visual controller
        _textController.text = cleanCode;

        // Trigger callback (Same behavior as onPressed)
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
            color: Colors.black.withOpacity(0.1),
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
                if (_textController.text.trim().isNotEmpty) {
                  widget.onScan(_textController.text.trim());
                }
              },
            )
            ),
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