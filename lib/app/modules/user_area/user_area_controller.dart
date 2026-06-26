import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

class UserAreaController extends GetxController {
  final AuthenticationController _auth = Get.find<AuthenticationController>();
  final StorageService _storage = Get.find<StorageService>();
  final ThemeController _theme = Get.find<ThemeController>();

  Rx<User?> get user => _auth.currentUser;
  Rx<ThemeMode> get themeMode => _theme.themeMode;
  String get company => _storage.getCompany();

  final version = ''.obs;
  final build = ''.obs;

  static String labelForMode(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  String get themeModeLabel => labelForMode(_theme.themeMode.value);

  @override
  void onInit() {
    super.onInit();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version.value = info.version;
      build.value = info.buildNumber;
    } catch (_) {
      // Plugin unavailable (e.g. tests) — leave blank.
    }
  }

  /// Logout funnels through AuthenticationController, which shows its own
  /// confirm dialog + spinner and routes to LOGIN. Single source of truth.
  void logout() => _auth.logoutUser();
}
