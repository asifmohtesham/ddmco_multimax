import 'package:get/get.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'package:multimax/app/modules/bom/reports/bom_search/bom_search_controller.dart';

class BomSearchBinding extends Bindings {
  @override
  void dependencies() {
    // Self-register BomProvider so the report route works whether or
    // not the user has previously visited the BOM list screen.
    // lazyPut is a no-op if BomProvider is already in the registry.
    Get.lazyPut<BomProvider>(() => BomProvider());
    Get.lazyPut<BomSearchController>(() => BomSearchController());
  }
}
