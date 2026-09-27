import 'dart:async';

import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

/// Runs the startup session check once the app is on screen, then opens
/// home or login. Keeping this out of main() means a slow server shows a
/// progress screen instead of holding the launch image.
class SplashController extends GetxController {
  final AuthenticationController _authController =
      Get.find<AuthenticationController>();

  static const _slowAfter = Duration(seconds: 4);

  /// True once the check has run long enough to deserve an explanation.
  final isSlow = false.obs;

  Timer? _slowTimer;

  @override
  void onReady() {
    super.onReady();
    _slowTimer = Timer(_slowAfter, () => isSlow.value = true);
    _openApp();
  }

  @override
  void onClose() {
    _slowTimer?.cancel();
    super.onClose();
  }

  Future<void> _openApp() async {
    await _authController.checkAuthenticationStatus();
    _slowTimer?.cancel();
    Get.offAllNamed(
      _authController.isAuthenticated.value ? AppRoutes.HOME : AppRoutes.LOGIN,
    );
  }
}
