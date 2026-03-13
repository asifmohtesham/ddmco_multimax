import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';

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

  static void _show({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    bool shouldVibrate = false,
  }) {
    // Do NOT call Get.closeCurrentSnackbar() here.
    //
    // GetX's _SnackBarQueue already serialises entries: a new snackbar is
    // held until the current one finishes.  Calling closeCurrentSnackbar()
    // manually is therefore unnecessary, and it is actively harmful when a
    // SnackbarController has been pushed onto the queue but its internal
    // `late AnimationController _controller` has not yet been initialised
    // (i.e. before the snackbar enters the Overlay).  Calling close() on
    // such a controller throws LateInitializationError and aborts _show()
    // before Get.snackbar() is ever reached, swallowing the message entirely.
    //
    // Removing the call means snackbars queue naturally and every message
    // is guaranteed to be shown.

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
        maxLines: 4,
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
