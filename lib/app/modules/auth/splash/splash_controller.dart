import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
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

  /// Re-arms the digest schedule on every launch (Android: WorkManager
  /// chain; iOS: the weekly reminder set). Fire-and-forget.
  void _selfHealSchedules() {
    if (kIsWeb || !_authController.isAuthenticated.value) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    unawaited(DigestScheduler().rearm().catchError((_) {}));
    if (Platform.isAndroid) {
      unawaited(AttendanceNotifyScheduler().rearm().catchError((_) {}));
    }
  }

  Future<void> _openApp() async {
    await _authController.checkAuthenticationStatus();
    _slowTimer?.cancel();
    _selfHealSchedules();
    Get.offAllNamed(
      _authController.isAuthenticated.value ? AppRoutes.HOME : AppRoutes.LOGIN,
    );
  }
}
