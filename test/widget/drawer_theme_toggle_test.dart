import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

void main() {
  testWidgets('cycleThemeMode advances the controller mode', (tester) async {
    final controller = ThemeController(
      persist: (_, __) async {},
      restore: (_) async => null,
    );
    expect(controller.themeMode.value, ThemeMode.system);

    controller.cycleThemeMode();
    expect(controller.themeMode.value, ThemeMode.light);

    Get.reset();
  });
}
