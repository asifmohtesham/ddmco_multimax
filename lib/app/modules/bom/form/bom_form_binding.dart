import 'package:get/get.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'bom_form_controller.dart';

class BomFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BomProvider>(() => BomProvider());
    Get.lazyPut<BomFormController>(() => BomFormController());
  }
}
