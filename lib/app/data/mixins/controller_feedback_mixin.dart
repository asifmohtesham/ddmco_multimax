import 'dart:async';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';

// Re-export BannerType so callers only need one import.
export 'package:multimax/app/modules/global_widgets/inline_banner.dart'
    show BannerType;

/// Mixin that provides a zero-overlay, in-scaffold feedback banner
/// lifecycle for any [GetxController].
///
/// ## Usage
///
/// ```dart
/// class MyFormController extends GetxController
///     with OptimisticLockingMixin, ControllerFeedbackMixin {
///
///   @override
///   void onClose() {
///     disposeFeedback();   // ← must be called
///     super.onClose();
///   }
///
///   Future<void> save() async {
///     // ... API call ...
///     showBanner('Document saved', type: BannerType.success);
///   }
/// }
/// ```
///
/// ## View binding
///
/// ```dart
/// Obx(() => InlineBanner(
///   visible: controller.bannerVisible.value,
///   message: controller.bannerMessage.value,
///   type:    controller.bannerType.value,
/// ))
/// ```
///
/// ## Why not GlobalSnackbar?
///
/// `SnackbarController.configureOverlay()` calls `Overlay.of()`
/// synchronously. When triggered on the same frame a bottom-sheet route
/// is popped, the Theater widget has already deactivated its overlay
/// subtree and `Overlay.of()` throws *"No Overlay widget found"*.
/// [InlineBanner] lives inside the route's own Scaffold tree and is
/// therefore immune to that lifecycle hazard.
mixin ControllerFeedbackMixin on GetxController {
  // ── Observable state ───────────────────────────────────────────────────
  // Naming follows the `var field = value.obs` convention used throughout
  // the codebase (see OptimisticLockingMixin: `var isStale = false.obs`).

  /// Whether the banner is currently visible.
  var bannerVisible = false.obs;

  /// The message currently shown in the banner.
  var bannerMessage = ''.obs;

  /// The semantic type of the banner (controls colour + icon).
  var bannerType = BannerType.info.obs;

  // ── Private timer ────────────────────────────────────────────────────────
  Timer? _feedbackTimer;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Shows the banner with [message] and auto-dismisses after [duration].
  ///
  /// Calling [showBanner] again before the timer fires cancels the
  /// previous timer and restarts the countdown, so rapid successive calls
  /// always result in only the latest message being shown.
  ///
  /// Pass `duration: null` to show the banner indefinitely until
  /// [dismissBanner] is called explicitly.
  void showBanner(
    String message, {
    BannerType type                = BannerType.success,
    Duration?  duration            = const Duration(seconds: 3),
  }) {
    _feedbackTimer?.cancel();
    bannerMessage.value = message;
    bannerType.value    = type;
    bannerVisible.value = true;

    if (duration != null) {
      _feedbackTimer = Timer(duration, () {
        bannerVisible.value = false;
      });
    }
  }

  /// Immediately hides the banner and cancels any pending auto-dismiss timer.
  void dismissBanner() {
    _feedbackTimer?.cancel();
    bannerVisible.value = false;
  }

  /// Cancels the auto-dismiss timer and resets all banner state.
  ///
  /// **Must be called from the controller's `onClose()` method** to
  /// prevent the timer from firing after the controller is deleted from
  /// GetX memory, which would attempt to mutate a closed Rx stream.
  ///
  /// ```dart
  /// @override
  /// void onClose() {
  ///   disposeFeedback();
  ///   super.onClose();
  /// }
  /// ```
  void disposeFeedback() {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
  }
}
