import 'package:flutter/material.dart';

class FrappeTheme {
  // Brand Colours
  static const Color primary = Color(0xFF0089FF); // Blue
  static const Color secondary = Color(0xFF5E64FF);

  // State Colours (FIX: Added these missing members)
  static const Color danger = Color(0xFFE02B2B); // Red for errors
  static const Color success = Color(0xFF28A745); // Green for success
  static const Color warning = Color(0xFFFFC107); // Amber for warnings

  // UI Colours
  static const Color surface = Color(0xFFF4F5F7);
  static const Color textBody = Color(0xFF1F272E);
  static const Color textLabel = Color(0xFF6C7680);
  static const Color border = Color(0xFFD1D8DD);

  // Measurements
  static const double radius = 10.0;
  static const double spacing = 16.0;

  static InputDecoration inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textLabel, fontSize: 13),
    );
  }
}
