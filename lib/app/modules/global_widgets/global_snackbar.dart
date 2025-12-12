import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';

class GlobalSnackbar {
  // ... (success, warning, info methods same as before) ...
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

  static void _show({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    bool shouldVibrate = false,
  }) {
    if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();

    if (shouldVibrate) HapticFeedback.lightImpact();

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
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
        ),
        maxLines: 4, // Prevents overflow
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: Colors.white,
      icon: Icon(icon, color: color, size: 28),
      shouldIconPulse: true,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      borderWidth: 1,
      borderColor: Colors.grey.shade200,
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