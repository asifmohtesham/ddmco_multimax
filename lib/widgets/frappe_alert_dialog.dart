import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/frappe_theme.dart';

enum FrappeAlertType { info, success, warning, error }

class FrappeAlertDialog extends StatelessWidget {
  final String title;
  final String message;
  final FrappeAlertType type;
  final String? positiveLabel;
  final VoidCallback? onPositive;
  final String negativeLabel;
  final VoidCallback? onNegative;

  const FrappeAlertDialog({
    super.key,
    required this.title,
    required this.message,
    this.type = FrappeAlertType.info,
    this.positiveLabel,
    this.onPositive,
    this.negativeLabel = "Dismiss",
    this.onNegative,
  });

  // Static helper for quick usage
  static void show({
    required String title,
    required String message,
    FrappeAlertType type = FrappeAlertType.info,
    String? positiveLabel,
    VoidCallback? onPositive,
  }) {
    Get.dialog(
      FrappeAlertDialog(
        title: title,
        message: message,
        type: type,
        positiveLabel: positiveLabel,
        onPositive: onPositive,
      ),
      barrierDismissible: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                _buildIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: FrappeTheme.textBody,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: FrappeTheme.textLabel,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  _stripHtml(message),
                  style: const TextStyle(
                    fontSize: 14,
                    color: FrappeTheme.textBody,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onPositive != null || positiveLabel != null) ...[
                  TextButton(
                    onPressed: onNegative ?? () => Get.back(),
                    child: Text(
                      negativeLabel,
                      style: const TextStyle(color: FrappeTheme.textLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (onPositive != null) onPositive!();
                      Get.back(); // Auto close on action
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getColor(),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: Text(positiveLabel ?? 'OK'),
                  ),
                ] else
                  // Single Dismiss Button if no action required
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Get.back(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: FrappeTheme.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        negativeLabel,
                        style: const TextStyle(color: FrappeTheme.textBody),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getColor() {
    switch (type) {
      case FrappeAlertType.success:
        return FrappeTheme.success;
      case FrappeAlertType.warning:
        return FrappeTheme.warning;
      case FrappeAlertType.error:
        return FrappeTheme.danger;
      case FrappeAlertType.info:
      default:
        return FrappeTheme.primary;
    }
  }

  Widget _buildIcon() {
    IconData iconData;
    switch (type) {
      case FrappeAlertType.success:
        iconData = Icons.check_circle_outline;
        break;
      case FrappeAlertType.warning:
        iconData = Icons.warning_amber_rounded;
        break;
      case FrappeAlertType.error:
        iconData = Icons.error_outline;
        break;
      case FrappeAlertType.info:
      default:
        iconData = Icons.info_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getColor().withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: _getColor(), size: 24),
    );
  }

  String _stripHtml(String htmlString) {
    // Simple regex to remove tags for basic display
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, '').trim();
  }
}
