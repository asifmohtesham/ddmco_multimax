// app/modules/batch/form/batch_form_binding.dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';

/// GetX dependency binding for the **Batch form** route.
///
/// [BatchProvider] is guarded with [Get.isRegistered] before registering.
/// When the user navigates List → Form, [BatchBinding] has already
/// registered [BatchProvider]; re-running [Get.lazyPut] without the guard
/// would create a second instance and leak the first.  The guard is a
/// no-op when the Form is opened cold (deep-link / push notification) —
/// both paths remain safe.
///
/// Registration order is intentional:
/// 1. [BatchProvider]       — must exist before [BatchFormController.onInit].
/// 2. [BatchFormController] — registered second.
class BatchFormBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<BatchProvider>()) {
      Get.lazyPut<BatchProvider>(() => BatchProvider());
    }
    Get.lazyPut<BatchFormController>(() => BatchFormController());
  }
}
