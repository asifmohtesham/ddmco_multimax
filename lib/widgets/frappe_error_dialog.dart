import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/frappe_theme.dart';

class FrappeErrorDialog extends StatelessWidget {
  final String title;
  final String message;

  const FrappeErrorDialog({
    super.key,
    this.title = "Error",
    required this.message,
  });

  static void show({String title = "Error", required dynamic error}) {
    String msg = error.toString().replaceAll("Exception:", "").trim();

    Get.dialog(
      FrappeErrorDialog(title: title, message: msg),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(Icons.error_outline, color: FrappeTheme.danger, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: Get.height * 0.6,
          minWidth: Get.width * 0.8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fallback to simple text stripping tags to avoid package errors
              Text(
                message.replaceAll(RegExp(r'<[^>]*>'), ''),
                style: const TextStyle(
                  fontSize: 14,
                  color: FrappeTheme.textBody,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text(
            "Close",
            style: TextStyle(
              color: FrappeTheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
