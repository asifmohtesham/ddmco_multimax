// app/modules/batch/form/batch_form_binding.dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';

class BatchFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BatchProvider>(() => BatchProvider());
    Get.lazyPut<BatchFormController>(() => BatchFormController());
  }
}