import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';

class BatchFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BatchFormController>(
          () => BatchFormController(),
    );
  }
}