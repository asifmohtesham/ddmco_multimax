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

    test('loadPersisted falls back to system on null/garbage', () async {
      final cNull = ThemeController(
        persist: (_, __) async {},
        restore: (_) async => null,
      );
      await cNull.loadPersisted();
      expect(cNull.themeMode.value, ThemeMode.system);

      final cGarbage = ThemeController(
        persist: (_, __) async {},
        restore: (_) async => 'nonsense',
      );
      await cGarbage.loadPersisted();
      expect(cGarbage.themeMode.value, ThemeMode.system);
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

  group('accent + text size', () {
    test('defaults: brand accent, comfortable text size', () {
      final c = ThemeController();
      expect(c.accentKey.value, 'brand');
      expect(c.textSize.value, AppTextSize.comfortable);
    });

    test('setAccent updates Rx and persists the key', () async {
      final saved = <String, String>{};
      final c = ThemeController(
        persist: (k, v) async => saved[k] = v,
        restore: (_) async => null,
      );

      await c.setAccent('blue');
      expect(c.accentKey.value, 'blue');
      expect(saved[ThemeController.accentStorageKey], 'blue');

      // Unknown keys fall back to brand.
      await c.setAccent('chartreuse');
      expect(c.accentKey.value, 'brand');
    });

    test('setTextSize updates Rx and persists the name', () async {
      final saved = <String, String>{};
      final c = ThemeController(
        persist: (k, v) async => saved[k] = v,
        restore: (_) async => null,
      );

      await c.setTextSize(AppTextSize.large);
      expect(c.textSize.value, AppTextSize.large);
      expect(saved[ThemeController.textSizeStorageKey], 'large');
    });

    test('loadPersisted restores accent + text size', () async {
      final store = {
        ThemeController.storageKey: 'dark',
        ThemeController.accentStorageKey: 'cyan',
        ThemeController.textSizeStorageKey: 'compact',
      };
      final c = ThemeController(
        persist: (_, __) async {},
        restore: (k) async => store[k],
      );

      await c.loadPersisted();

      expect(c.themeMode.value, ThemeMode.dark);
      expect(c.accentKey.value, 'cyan');
      expect(c.textSize.value, AppTextSize.compact);
    });

    test('textSizeFromName maps names and falls back to comfortable', () {
      expect(ThemeController.textSizeFromName('compact'), AppTextSize.compact);
      expect(ThemeController.textSizeFromName('large'), AppTextSize.large);
      expect(ThemeController.textSizeFromName(null), AppTextSize.comfortable);
      expect(
          ThemeController.textSizeFromName('xl'), AppTextSize.comfortable);
    });
  });
}
