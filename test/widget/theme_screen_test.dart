import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/app/modules/theme/theme_screen.dart';

void main() {
  testWidgets('tapping Dark sets ThemeController to dark', (tester) async {
    final tc =
        ThemeController(persist: (_, __) async {}, restore: (_) async => null);
    Get.put<ThemeController>(tc);

    await tester.pumpWidget(GetMaterialApp(home: const ThemeScreen()));
    expect(tc.themeMode.value, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(tc.themeMode.value, ThemeMode.dark);
    Get.reset();
  });
}
