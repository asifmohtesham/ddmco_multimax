import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A context-safe notification utility that uses [ScaffoldMessenger]
/// instead of [Get.snackbar], eliminating LateInitializationError crashes
/// caused by GetX's SnackbarController overlay lifecycle.
///
/// All methods silently no-op when [Get.context] is null (e.g. during
/// background operations or after widget disposal).
abstract class AppNotification {
  /// Shows a green success snackbar.
  static void success(String message) =>
      _show(message, _successColor, Icons.check_circle_outline);

  /// Shows a red error snackbar.
  static void error(String message) =>
      _show(message, _errorColor, Icons.error_outline);

  /// Shows an orange warning snackbar.
  static void warning(String message) =>
      _show(message, _warningColor, Icons.warning_amber_outlined);

  /// Shows a blue informational snackbar.
  static void info(String message) =>
      _show(message, _infoColor, Icons.info_outline);

  static void _show(String message, Color bg, IconData icon) {
    final ctx = Get.context;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  static const _successColor = Color(0xFF388E3C);
  static const _errorColor   = Color(0xFFD32F2F);
  static const _warningColor = Color(0xFFF57C00);
  static const _infoColor    = Color(0xFF1565C0);
}
