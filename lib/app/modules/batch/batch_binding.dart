// app/modules/batch/batch_binding.dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';

/// GetX dependency binding for the **Batch list** route.
///
/// Registration order is intentional:
/// 1. [BatchProvider] — registered first because [BatchController.onInit]
///    calls `Get.find<BatchProvider>()` synchronously.
/// 2. [BatchController] — registered second.
///
/// Both use [Get.lazyPut] so instances are created on first access, not
/// at route-push time, keeping startup cost minimal.
class BatchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BatchProvider>(() => BatchProvider());
    Get.lazyPut<BatchController>(() => BatchController());
  }
}
