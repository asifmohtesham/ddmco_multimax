import 'package:flutter/material.dart';

class ScannerInput extends StatelessWidget {
  final Function(String) onScan;
  final String hintText;
  final bool enabled;

  const ScannerInput({
    Key? key,
    required this.onScan,
    this.hintText = "Scan Serial/Batch No...",
    this.enabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final TextEditingController _controller = TextEditingController();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: _controller,
        enabled: enabled,
        textInputAction: TextInputAction.go,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.qr_code_scanner),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => _controller.clear(),
          ),
          hintText: hintText,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          isDense: true,
        ),
        onSubmitted: (val) {
          if (val.trim().isNotEmpty) {
            onScan(val.trim());
            _controller.clear(); // Auto-clear after scan for rapid entry
          }
        },
      ),
    );
  }
}