import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/database_service.dart';

/// Holds the user's [ThemeMode] choice and persists it via [DatabaseService].
///
/// [persist]/[restore] are injectable seams so the controller is unit-testable
/// without a real SQLite database. In production they default to the registered
/// [DatabaseService].
class ThemeController extends GetxController {
  static const String storageKey = 'theme_mode';

  final Future<void> Function(String key, String value) _persist;
  final Future<String?> Function(String key) _restore;

  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;

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

  Future<void> loadPersisted() async {
    final stored = await _restore(storageKey);
    themeMode.value = themeModeFromName(stored);
    Get.changeThemeMode(themeMode.value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
    await _persist(storageKey, themeModeToName(mode));
  }

  void cycleThemeMode() {
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final next = order[(order.indexOf(themeMode.value) + 1) % order.length];
    setThemeMode(next);
  }
}
