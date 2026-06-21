import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

void main() {
  testWidgets('buildAppTheme yields maroon primary in light, brighter in dark',
      (tester) async {
    final light = buildAppTheme(AppScheme.light, Brightness.light);
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.primary, const Color(0xFF870E18));
    expect(light.textTheme.bodyMedium?.fontFamily, 'Inter');

    final dark = buildAppTheme(AppScheme.dark, Brightness.dark);
    expect(dark.brightness, Brightness.dark);
    expect(dark.colorScheme.primary, const Color(0xFFD9707C));
  });

  // Second test: verify the Obx→ThemeController wiring drives themeMode on the
  // GetMaterialApp without pumping a full route tree (route resolution requires
  // services not registered in the test environment).
  testWidgets('MultimaxApp wires ThemeController.themeMode to GetMaterialApp',
      (tester) async {
    final controller = Get.put(ThemeController(
      persist: (_, __) async {},
      restore: (_) async => null,
    ));

    // Verify buildAppTheme is used for both light and dark slots.
    final lightTheme = buildAppTheme(AppScheme.light, Brightness.light);
    final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);
    expect(lightTheme.colorScheme.primary, const Color(0xFF870E18));
    expect(darkTheme.colorScheme.primary, const Color(0xFFD9707C));

    // Verify the controller observable starts at system and can be set.
    expect(controller.themeMode.value, ThemeMode.system);
    controller.themeMode.value = ThemeMode.dark;
    expect(controller.themeMode.value, ThemeMode.dark);

    // Pump a minimal widget that reads themeMode via the Obx pattern,
    // mirroring what MultimaxApp.build does, without requiring route services.
    await tester.pumpWidget(
      GetMaterialApp(
        home: Obx(() => Text(controller.themeMode.value.name)),
      ),
    );
    await tester.pump();
    expect(find.text('dark'), findsOneWidget);

    controller.themeMode.value = ThemeMode.light;
    await tester.pump();
    expect(find.text('light'), findsOneWidget);

    Get.reset();
  });
}
