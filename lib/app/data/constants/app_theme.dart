import 'package:flutter/material.dart';

/// ERPNext v15 design tokens — see docs/design_handoff_global_components/ds.css.
/// NOTE: the app keeps its maroon brand primary; only the neutral/status/
/// spacing/radius ramps and dark-mode surfaces come from ERPNext v15.
class AppColors {
  AppColors._();

  // Neutral ramp (Frappe gray scale)
  static const gray50 = Color(0xFFF9FAFA);
  static const gray100 = Color(0xFFF4F5F6);
  static const gray200 = Color(0xFFEBEEF0);
  static const gray300 = Color(0xFFD8DEE3);
  static const gray400 = Color(0xFFBCC4CB);
  static const gray500 = Color(0xFF98A1A9);
  static const gray600 = Color(0xFF74808B);
  static const gray700 = Color(0xFF525C66);
  static const gray800 = Color(0xFF323A45);
  static const gray900 = Color(0xFF1F272E);

  // Status ramps — 300 = dark-mode text, 500 = base/dot, 700 = light-mode text.
  static const blue300 = Color(0xFF7CC0F7);
  static const blue500 = Color(0xFF2490EF);
  static const blue600 = Color(0xFF1F75C9);
  static const blue700 = Color(0xFF18599A);
  static const green300 = Color(0xFF8FD3A8);
  static const green500 = Color(0xFF38A160);
  static const green700 = Color(0xFF1F5E34);
  static const red300 = Color(0xFFF09494);
  static const red500 = Color(0xFFE03636);
  static const red700 = Color(0xFF9A2222);
  static const orange300 = Color(0xFFF7B67A);
  static const orange500 = Color(0xFFF0851B);
  static const orange700 = Color(0xFF9E5409);
  static const yellow300 = Color(0xFFFAD08C);
  static const yellow500 = Color(0xFFE0A93A);
  static const yellow700 = Color(0xFF946817);
  static const purple300 = Color(0xFFB6A0FF);
  static const purple500 = Color(0xFF7C4DFF);
  static const purple700 = Color(0xFF4E29AB);
  static const cyan300 = Color(0xFF7FD3DF);
  static const cyan500 = Color(0xFF1AAFC4);
  static const cyan700 = Color(0xFF0D6675);
}

/// Semantic palette resolved per brightness (light / Timeless Night dark).
class AppScheme {
  final Color bg;
  final Color fg;
  final Color subtle;
  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color border;
  final Color borderStrong;
  final Color primary;
  final Color onPrimary;
  final Color secondary;

  const AppScheme({
    required this.bg,
    required this.fg,
    required this.subtle,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
  });

  static const light = AppScheme(
    bg: AppColors.gray100,
    fg: Color(0xFFFFFFFF),
    subtle: AppColors.gray50,
    text: AppColors.gray900,
    textMuted: AppColors.gray600,
    textSubtle: AppColors.gray500,
    border: AppColors.gray200,
    borderStrong: AppColors.gray300,
    primary: Color(0xFF870E18), // maroon brand — kept
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF25286F), // indigo
  );

  static const dark = AppScheme(
    bg: Color(0xFF15191D),
    fg: Color(0xFF1F262C),
    subtle: Color(0xFF262D34),
    text: Color(0xFFEEF1F4),
    textMuted: Color(0xFF9AA5AF),
    textSubtle: Color(0xFF6F7C87),
    border: Color(0xFF2E353C),
    borderStrong: Color(0xFF3A424A),
    primary: Color(0xFFD9707C), // lightened maroon for dark surfaces
    onPrimary: Color(0xFF2A0509),
    secondary: Color(0xFF8C8FE0), // lightened indigo
  );

  static AppScheme of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

class AppRadius {
  AppRadius._();
  static const double xs = 4, sm = 6, md = 8, lg = 12, xl = 16, full = 999;
}

class AppSpace {
  AppSpace._();
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 20, s6 = 24, s8 = 32, s10 = 40;
}

/// `context.scheme` → the active [AppScheme] for the current brightness.
extension AppSchemeX on BuildContext {
  AppScheme get scheme => AppScheme.of(Theme.of(this).brightness);
}
