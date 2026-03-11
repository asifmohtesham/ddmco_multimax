import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/bom/bom_controller.dart';

class BomBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BomController>(
      () => BomController(),
    );
  }
}