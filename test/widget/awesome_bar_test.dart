import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/common/widgets/awesome_bar.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets('empty AwesomeBar uses theme inks in ${brightness.name} mode', (
      tester,
    ) async {
      final scheme = AppScheme.of(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppScheme.light, Brightness.light),
          darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: Scaffold(body: AwesomeBar()),
        ),
      );
      await tester.tap(find.byTooltip('Search or type a command'));
      await tester.pumpAndSettle();

      for (final finder in [
        find.text('No results found'),
        find.textContaining('Try searching for an ID'),
      ]) {
        expect(tester.widget<Text>(finder).style?.color, scheme.textMuted);
      }
      expect(
        tester.widget<Icon>(find.byIcon(Icons.search_off)).color,
        scheme.textSubtle,
      );
    });
  }
}
