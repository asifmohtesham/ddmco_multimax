import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';

class MaterialRequestFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MaterialRequestFormController>(
          () => MaterialRequestFormController(),
    );
  }
}