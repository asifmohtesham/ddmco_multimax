import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';

class ItemVariantDetailsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ItemVariantDetailsController>(
      () => ItemVariantDetailsController(),
    );
  }
}
