import 'package:flutter/material.dart';

class FrappeTheme {
  static const Color primary = Color(0xFF0089FF);
  static const Color surface = Color(0xFFF3F4F6);
  static const Color textLabel = Color(0xFF374151);
  static const Color textBody = Color(0xFF111827);
  static const double radius = 12.0;
  static const double spacing = 16.0;

  static InputDecoration inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: textLabel, fontWeight: FontWeight.w500),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}