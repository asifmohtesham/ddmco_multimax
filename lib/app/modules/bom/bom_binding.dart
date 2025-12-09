import 'package:get/get.dart';
import 'package:multimax/app/modules/bom/bom_controller.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';

class BomBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BomProvider>(() => BomProvider());
    Get.lazyPut<BomController>(() => BomController());
  }
}