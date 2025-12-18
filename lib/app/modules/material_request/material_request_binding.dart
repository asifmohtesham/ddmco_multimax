import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';

class MaterialRequestBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MaterialRequestProvider>(() => MaterialRequestProvider());
    Get.lazyPut<MaterialRequestController>(() => MaterialRequestController());
  }
}