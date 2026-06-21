import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('serialization', () {
    test('round-trips every ThemeMode by name', () {
      for (final m in ThemeMode.values) {
        expect(
          ThemeController.themeModeFromName(ThemeController.themeModeToName(m)),
          m,
        );
      }
    });

    test('unknown / null name falls back to system', () {
      expect(ThemeController.themeModeFromName(null), ThemeMode.system);
      expect(ThemeController.themeModeFromName('garbage'), ThemeMode.system);
    });
  });

  group('state + persistence', () {
    test('defaults to system', () {
      final c = ThemeController();
      expect(c.themeMode.value, ThemeMode.system);
    });

    test('setThemeMode updates Rx and persists the name', () async {
      String? savedKey;
      String? savedValue;
      final c = ThemeController(
        persist: (k, v) async {
          savedKey = k;
          savedValue = v;
        },
        restore: (_) async => null,
      );

      await c.setThemeMode(ThemeMode.dark);

      expect(c.themeMode.value, ThemeMode.dark);
      expect(savedKey, ThemeController.storageKey);
      expect(savedValue, 'dark');
    });

    test('loadPersisted restores a saved mode', () async {
      final c = ThemeController(
        persist: (_, __) async {},
        restore: (_) async => 'light',
      );

      await c.loadPersisted();

      expect(c.themeMode.value, ThemeMode.light);
    });

    test('cycleThemeMode advances system -> light -> dark -> system', () async {
      final c = ThemeController(persist: (_, __) async {}, restore: (_) async => null);
      expect(c.themeMode.value, ThemeMode.system);
      c.cycleThemeMode();
      expect(c.themeMode.value, ThemeMode.light);
      c.cycleThemeMode();
      expect(c.themeMode.value, ThemeMode.dark);
      c.cycleThemeMode();
      expect(c.themeMode.value, ThemeMode.system);
    });
  });
}
