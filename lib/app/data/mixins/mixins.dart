/// Barrel export for all GetxController mixins.
///
/// Import this file to get both mixins in a single line:
///
/// ```dart
/// import 'package:multimax/app/data/mixins/mixins.dart';
///
/// class MyFormController extends GetxController
///     with OptimisticLockingMixin, ControllerFeedbackMixin {
///   @override
///   void onClose() {
///     disposeFeedback();
///     super.onClose();
///   }
/// }
/// ```
///
/// [BannerType] is re-exported transitively via [ControllerFeedbackMixin],
/// so callers do not need a separate import for the enum.
export 'optimistic_locking_mixin.dart';
export 'controller_feedback_mixin.dart';
