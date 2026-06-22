import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/database_service.dart';

/// User-selectable text size. Maps to a [TextScaler] factor applied app-wide.
enum AppTextSize { compact, comfortable, large }

extension AppTextSizeX on AppTextSize {
  double get factor => switch (this) {
        AppTextSize.compact => 0.9,
        AppTextSize.comfortable => 1.0,
        AppTextSize.large => 1.12,
      };

  String get label => switch (this) {
        AppTextSize.compact => 'Compact',
        AppTextSize.comfortable => 'Comfortable',
        AppTextSize.large => 'Large',
      };
}

/// Holds the user's appearance choices ([ThemeMode], primary [AppAccent], and
/// [AppTextSize]) and persists them via [DatabaseService].
///
/// [persist]/[restore] are injectable seams so the controller is unit-testable
/// without a real SQLite database. In production they default to the registered
/// [DatabaseService].
class ThemeController extends GetxController {
  static const String storageKey = 'theme_mode';
  static const String accentStorageKey = 'theme_accent';
  static const String textSizeStorageKey = 'text_scale';

  final Future<void> Function(String key, String value) _persist;
  final Future<String?> Function(String key) _restore;

  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;

  /// Selected accent key (see [AppAccent.key]); 'brand' (maroon) by default.
  final RxString accentKey = AppAccent.brand.key.obs;

  /// Selected text size; comfortable (1.0×) by default.
  final Rx<AppTextSize> textSize = AppTextSize.comfortable.obs;

  ThemeController({
    Future<void> Function(String, String)? persist,
    Future<String?> Function(String)? restore,
  })  : _persist = persist ??
            ((k, v) => Get.find<DatabaseService>().saveConfig(k, v)),
        _restore = restore ??
            ((k) => Get.find<DatabaseService>().getConfig(k));

  static String themeModeToName(ThemeMode m) => m.name; // 'system' | 'light' | 'dark'

  static ThemeMode themeModeFromName(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static AppTextSize textSizeFromName(String? name) => switch (name) {
        'compact' => AppTextSize.compact,
        'large' => AppTextSize.large,
        _ => AppTextSize.comfortable,
      };

  Future<void> loadPersisted() async {
    final mode = await _restore(storageKey);
    themeMode.value = themeModeFromName(mode);
    Get.changeThemeMode(themeMode.value);

    final accent = await _restore(accentStorageKey);
    if (accent != null && accent.isNotEmpty) {
      accentKey.value = AppAccent.byKey(accent).key;
    }

    final size = await _restore(textSizeStorageKey);
    textSize.value = textSizeFromName(size);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
    await _persist(storageKey, themeModeToName(mode));
  }

  Future<void> setAccent(String key) async {
    final resolved = AppAccent.byKey(key).key;
    accentKey.value = resolved;
    await _persist(accentStorageKey, resolved);
  }

  Future<void> setTextSize(AppTextSize size) async {
    textSize.value = size;
    await _persist(textSizeStorageKey, size.name);
  }

  void cycleThemeMode() {
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final next = order[(order.indexOf(themeMode.value) + 1) % order.length];
    unawaited(setThemeMode(next));
  }
}
