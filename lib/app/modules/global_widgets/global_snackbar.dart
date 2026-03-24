import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Overlay-safe snackbar helper.
///
/// Uses [ScaffoldMessenger] via [Get.context] so notifications are
/// always shown on the root navigator's scaffold — never on a
/// bottom-sheet overlay that may already be unmounted.
class GlobalSnackbar {
  static void success({String title = 'Success', required String message}) {
    _show(
      title: title,
      message: message,
      icon: Icons.check_circle_rounded,
      color: Colors.green.shade600,
      shouldVibrate: true,
    );
  }

  static void error({String title = 'Error', required String message}) {
    _show(
      title: title,
      message: message,
      icon: Icons.error_rounded,
      color: Colors.red.shade600,
      shouldVibrate: true,
    );
  }

  static void warning({String title = 'Warning', required String message}) {
    _show(
      title: title,
      message: message,
      icon: Icons.warning_amber_rounded,
      color: Colors.orange.shade700,
    );
  }

  static void info({String title = 'Info', required String message}) {
    _show(
      title: title,
      message: message,
      icon: Icons.info_outline_rounded,
      color: Colors.blue.shade600,
    );
  }

  // ---------------------------------------------------------------------------

  static void _show({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    bool shouldVibrate = false,
  }) {
    final context = Get.context;
    if (context == null) {
      // Controller called this before any UI is present – log and bail.
      debugPrint('[GlobalSnackbar] no context – $title: $message');
      return;
    }

    if (shouldVibrate) HapticFeedback.lightImpact();

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          backgroundColor: Colors.white,
          elevation: 4,
          duration: const Duration(seconds: 4),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}
