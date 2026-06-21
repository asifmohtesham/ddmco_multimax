import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

void main() {
  group('AppScheme', () {
    test('light uses maroon primary and white surface', () {
      expect(AppScheme.light.primary, const Color(0xFF870E18));
      expect(AppScheme.light.onPrimary, const Color(0xFFFFFFFF));
      expect(AppScheme.light.fg, const Color(0xFFFFFFFF));
      expect(AppScheme.light.bg, const Color(0xFFF4F5F6));
      expect(AppScheme.light.text, const Color(0xFF1F272E));
    });

    test('dark uses lightened maroon primary and dark surfaces', () {
      expect(AppScheme.dark.primary, const Color(0xFFD9707C));
      expect(AppScheme.dark.onPrimary, const Color(0xFF2A0509));
      expect(AppScheme.dark.fg, const Color(0xFF1F262C));
      expect(AppScheme.dark.bg, const Color(0xFF15191D));
      expect(AppScheme.dark.text, const Color(0xFFEEF1F4));
    });

    test('of() resolves by brightness', () {
      expect(AppScheme.of(Brightness.light), same(AppScheme.light));
      expect(AppScheme.of(Brightness.dark), same(AppScheme.dark));
    });
  });

  group('tokens', () {
    test('radius and spacing scales match the design system', () {
      expect(AppRadius.md, 8.0);
      expect(AppRadius.full, 999.0);
      expect(AppSpace.s4, 16.0);
      expect(AppSpace.s10, 40.0);
    });

    test('neutral ramp anchors match ds.css', () {
      expect(AppColors.gray50, const Color(0xFFF9FAFA));
      expect(AppColors.gray900, const Color(0xFF1F272E));
    });

    test('status ramp anchors match ds.css', () {
      expect(AppColors.blue500, const Color(0xFF2490EF));
      expect(AppColors.green500, const Color(0xFF38A160));
      expect(AppColors.red500, const Color(0xFFE03636));
      expect(AppColors.yellow300, const Color(0xFFF3D08C));
      expect(AppColors.orange500, const Color(0xFFF0851B));
      expect(AppColors.purple500, const Color(0xFF7C4DFF));
      expect(AppColors.cyan500, const Color(0xFF1AAFC4));
    });
  });
}
