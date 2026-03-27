import 'package:get/get.dart';
import 'package:multimax/app/data/providers/bom_provider.dart';
import 'package:multimax/app/modules/bom/bom_controller.dart';

/// Binding for the BOM **list** route (`AppRoutes.BOM`).
///
/// The BOM **form** route (`AppRoutes.BOM_FORM`) uses its own
/// [BomFormBinding] and re-registers [BomProvider] independently,
/// so there is no shared dependency between the two routes.
class BomBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BomProvider>(() => BomProvider());
    Get.lazyPut<BomController>(() => BomController());
  }
}
