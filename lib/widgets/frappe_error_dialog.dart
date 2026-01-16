import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart'; // Recommended package
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
          Icon(Icons.error_outline, color: FrappeTheme.danger, size: 28),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
              // Try to render HTML, fallback to Text if package missing or error
              _buildHtmlContent(message),
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

  Widget _buildHtmlContent(String htmlData) {
    try {
      // Renders HTML tags like <b>, <br>, <ul>, etc.
      return HtmlWidget(
        htmlData,
        textStyle: const TextStyle(
          fontSize: 14,
          color: FrappeTheme.textBody,
          height: 1.5,
        ),
        onErrorBuilder: (context, element, error) =>
            Text('$element error: $error'),
        renderMode: RenderMode.column,
      );
    } catch (e) {
      // Fallback if package fails or not installed
      return Text(
        htmlData.replaceAll(RegExp(r'<[^>]*>'), ''),
        // Strip tags for readability
        style: const TextStyle(fontSize: 14, color: FrappeTheme.textBody),
      );
    }
  }
}
