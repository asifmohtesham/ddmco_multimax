import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/services/scan_service.dart';

class MaterialRequestFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MaterialRequestProvider>(() => MaterialRequestProvider());
    Get.lazyPut<ScanService>(() => ScanService());
    Get.lazyPut<MaterialRequestFormController>(() => MaterialRequestFormController());
  }
}