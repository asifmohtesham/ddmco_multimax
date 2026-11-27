import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

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

  /// Shows a blue informational snackbar with an action button (omitted when
  /// [onPressed] is null). Stays up longer so there is time to tap it.
  static void withAction(
    String message, {
    required String label,
    VoidCallback? onPressed,
  }) =>
      _show(message, _infoColor, Icons.notifications_active_outlined,
          action: onPressed == null
              ? null
              : SnackBarAction(
                  label: label,
                  textColor: Colors.white,
                  onPressed: onPressed,
                ),
          duration: const Duration(seconds: 8));

  static void _show(
    String message,
    Color bg,
    IconData icon, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
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
          action: action,
          duration: duration,
        ),
      );
  }

  // x700 status-ramp fills (see AppColors): every one carries white text at
  // ≥4.9:1. The previous material shades failed — white-on-#F57C00 was 2.9:1.
  static const _successColor = AppColors.green700;
  static const _errorColor   = AppColors.red700;
  static const _warningColor = AppColors.orange700;
  static const _infoColor    = AppColors.blue700;
}
