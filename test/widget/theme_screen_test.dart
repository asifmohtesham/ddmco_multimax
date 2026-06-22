import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/app/modules/theme/theme_screen.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('tapping Dark sets ThemeController to dark', (tester) async {
    final tc =
        ThemeController(persist: (_, __) async {}, restore: (_) async => null);
    Get.put<ThemeController>(tc);

    await tester.pumpWidget(GetMaterialApp(home: const ThemeScreen()));
    expect(tc.themeMode.value, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(tc.themeMode.value, ThemeMode.dark);
  });

  testWidgets('tapping an accent swatch sets the accent key', (tester) async {
    final tc =
        ThemeController(persist: (_, __) async {}, restore: (_) async => null);
    Get.put<ThemeController>(tc);

    await tester.pumpWidget(GetMaterialApp(home: const ThemeScreen()));
    expect(tc.accentKey.value, 'brand');

    await tester.tap(find.byKey(const Key('accent-blue')));
    await tester.pumpAndSettle();

    expect(tc.accentKey.value, 'blue');
  });

  testWidgets('tapping Large sets the text size', (tester) async {
    final tc =
        ThemeController(persist: (_, __) async {}, restore: (_) async => null);
    Get.put<ThemeController>(tc);

    await tester.pumpWidget(GetMaterialApp(home: const ThemeScreen()));
    expect(tc.textSize.value, AppTextSize.comfortable);

    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();

    expect(tc.textSize.value, AppTextSize.large);
  });
}
