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

  testWidgets(
      'MultimaxApp.build wraps GetMaterialApp in an Obx (reactive themeMode wiring)',
      (tester) async {
    Get.put(ThemeController(
      persist: (_, __) async {},
      restore: (_) async => null,
    ));

    // Exercise the REAL MultimaxApp.build. We assert it returns an Obx (the
    // reactive wrapper that feeds ThemeController.themeMode into
    // GetMaterialApp.themeMode). We do NOT render the returned GetMaterialApp:
    // that would resolve the initial route and require service bindings that
    // unit tests don't register. This still catches the regression of the Obx
    // wrapper being removed from MultimaxApp.build.
    late Widget built;
    await tester.pumpWidget(
      Builder(builder: (context) {
        built = const MultimaxApp(initialRoute: '/').build(context);
        return const SizedBox.shrink();
      }),
    );

    expect(built, isA<Obx>());

    Get.reset();
  });

  testWidgets('tabBarTheme matches ds.css tab spec', (tester) async {
    final t = buildAppTheme(AppScheme.light, Brightness.light);
    final tb = t.tabBarTheme;
    expect(tb.labelColor, AppScheme.light.primary);
    expect(tb.unselectedLabelColor, AppScheme.light.textMuted);
    expect(tb.indicatorColor, AppScheme.light.primary);
    expect(tb.indicatorSize, TabBarIndicatorSize.tab);
    expect(tb.dividerColor, AppScheme.light.border);
    expect(tb.labelStyle?.fontWeight, FontWeight.w500);
  });
}
