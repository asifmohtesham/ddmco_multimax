import 'package:flutter/material.dart';
import 'package:get/get.dart';

class GlobalSnackbar {
  static void show({
    required String title,
    required String message,
    bool isError = false,
  }) {
    // Close existing snackbars to prevent stacking
    if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();

    Get.snackbar(
      title,
      message,
      backgroundColor: Colors.white,
      colorText: Colors.black87,
      borderWidth: 1,
      borderColor: Colors.grey.shade300,
      icon: Icon(
        isError ? Icons.error_outline : Icons.check_circle_outline,
        color: isError ? Colors.red : Colors.green,
      ),
      shouldIconPulse: true,
      barBlur: 20,
      isDismissible: true,
      duration: const Duration(seconds: 4),
      mainButton: TextButton(
        onPressed: () {
          if (Get.isSnackbarOpen) Get.back();
        },
        child: Text(
          'DISMISS',
          style: TextStyle(
            color: isError ? Colors.red : Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}