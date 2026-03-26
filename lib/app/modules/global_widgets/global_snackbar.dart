import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';

class GlobalSnackbar {
  static void success({String title = 'Success', required String message}) {
    final cs = _colorScheme();
    _show(
      title: title,
      message: message,
      icon: Icons.check_circle_rounded,
      color: cs.tertiary,
      shouldVibrate: true,
    );
  }

  static void error({String title = 'Error', required String message}) {
    final cs = _colorScheme();
    _show(
      title: title,
      message: message,
      icon: Icons.error_rounded,
      color: cs.error,
      shouldVibrate: true,
    );
  }

  static void warning({String title = 'Warning', required String message}) {
    final cs = _colorScheme();
    _show(
      title: title,
      message: message,
      icon: Icons.warning_amber_rounded,
      color: cs.secondary,
    );
  }

  static void info({String title = 'Info', required String message}) {
    final cs = _colorScheme();
    _show(
      title: title,
      message: message,
      icon: Icons.info_outline_rounded,
      color: cs.primary,
    );
  }

  static ColorScheme _colorScheme() =>
      Theme.of(Get.context!).colorScheme;

  static void _show({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    bool shouldVibrate = false,
  }) {
    if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
    if (shouldVibrate) HapticFeedback.lightImpact();

    final cs = _colorScheme();

    Get.snackbar(
      title,
      message,
      titleText: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      messageText: Text(
        message,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 14,
        ),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: cs.surface,
      icon: Icon(icon, color: color, size: 28),
      shouldIconPulse: true,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      borderWidth: 1,
      borderColor: cs.outlineVariant,
      boxShadows: [
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          offset: const Offset(0, 4),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ],
      duration: const Duration(seconds: 4),
      isDismissible: true,
      leftBarIndicatorColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }
}
