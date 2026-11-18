import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/camera_scan_overlay.dart';

/// Asks for a barcode or item code to replace what the photo gave. [onSubmit]
/// returns an error to show inline, or null on success (the sheet then closes).
/// [scan] reads a code with the camera.
Future<void> showFixCodeSheet(
  BuildContext context, {
  required Future<String?> Function(String code) onSubmit,
  Future<String?> Function(BuildContext context) scan = CameraScanOverlay.show,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _FixCodeSheet(onSubmit: onSubmit, scan: scan),
  );
}

class _FixCodeSheet extends StatefulWidget {
  const _FixCodeSheet({required this.onSubmit, required this.scan});

  final Future<String?> Function(String) onSubmit;
  final Future<String?> Function(BuildContext) scan;

  @override
  State<_FixCodeSheet> createState() => _FixCodeSheetState();
}

class _FixCodeSheetState extends State<_FixCodeSheet> {
  final _text = TextEditingController();
  final _busy = false.obs;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy.value) return;
    final code = _text.text.trim();
    if (code.isEmpty) return;
    _busy.value = true;
    setState(() => _error = null);
    try {
      final error = await widget.onSubmit(code);
      if (!mounted) return;
      if (error == null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _error = error);
      }
    } finally {
      _busy.value = false;
    }
  }

  Future<void> _scan() async {
    if (_busy.value) return;
    final code = await widget.scan(context);
    if (!mounted || code == null || code.trim().isEmpty) return;
    _text.text = code.trim();
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        color: s.fg,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '✎ Type or scan code',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: s.text,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _text,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  // The error was about the text before this edit.
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  style: TextStyle(color: s.text),
                  decoration: InputDecoration(
                    labelText: 'Barcode or item code',
                    errorText: _error,
                    errorStyle: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.red300
                          : AppColors.red700,
                    ),
                    errorMaxLines: 2,
                    filled: true,
                    fillColor: s.subtle,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan'),
                    ),
                    const Spacer(),
                    AsyncFilledButton(
                      busy: _busy,
                      onPressed: _submit,
                      icon: const Icon(Icons.check),
                      label: 'Use code',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
