// app/modules/batch/batch_binding.dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';

class BatchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BatchProvider>(() => BatchProvider());
    Get.lazyPut<BatchController>(() => BatchController());
  }
}