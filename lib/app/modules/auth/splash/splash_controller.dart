import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/push_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

/// Runs startup verification on screen and waits for a usable session result.
class SplashController extends GetxController {
  final AuthenticationController _authController =
      Get.find<AuthenticationController>();

  static const _slowAfter = Duration(seconds: 4);

  /// True once the initial check has run long enough to deserve an explanation.
  final isSlow = false.obs;

  RxBool get isSessionVerificationPending =>
      _authController.isSessionVerificationPending;
  RxBool get isCheckingSession => _authController.isCheckingSession;

  Timer? _slowTimer;
  Worker? _verificationWorker;
  bool _hasNavigated = false;

  @override
  void onReady() {
    super.onReady();
    _slowTimer = Timer(_slowAfter, () => isSlow.value = true);
    unawaited(_checkAtStartup());
  }

  @override
  void onClose() {
    _slowTimer?.cancel();
    _verificationWorker?.dispose();
    super.onClose();
  }

  Future<void> _checkAtStartup() async {
    await _authController.checkAuthenticationStatus();
    _slowTimer?.cancel();
    if (isClosed) return;
    if (isSessionVerificationPending.value) {
      _verificationWorker = ever(isSessionVerificationPending, (pending) {
        if (!pending) _openVerifiedRoute();
      });
    } else {
      _openVerifiedRoute();
    }
  }

  void retry() {
    if (_hasNavigated || isCheckingSession.value) return;
    unawaited(_authController.checkAuthenticationStatus());
  }

  void openLogin() {
    if (_hasNavigated || isCheckingSession.value) return;
    _hasNavigated = true;
    _authController.stopStartupRecheck();
    Get.offAllNamed(AppRoutes.LOGIN);
  }

  void _openVerifiedRoute() {
    if (_hasNavigated || isClosed) return;
    _hasNavigated = true;
    _selfHealSchedules();
    final signedIn = _authController.isAuthenticated.value;
    Get.offAllNamed(signedIn ? AppRoutes.HOME : AppRoutes.LOGIN);
    // A tapped alert that launched the app opens its POS Upload over home.
    if (signedIn && Get.isRegistered<PushService>()) {
      Get.find<PushService>().homeReady();
    }
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
}
