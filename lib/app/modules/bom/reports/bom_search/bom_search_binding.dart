import 'package:get/get.dart';
import 'package:multimax/app/modules/bom/reports/bom_search/bom_search_controller.dart';

class BomSearchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BomSearchController>(() => BomSearchController());
  }
}
