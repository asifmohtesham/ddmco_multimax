import 'package:get/get.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';

class ItemPriceFormBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ItemPriceProvider>()) {
      Get.lazyPut<ItemPriceProvider>(() => ItemPriceProvider(), fenix: true);
    }
    Get.lazyPut<ItemPriceFormController>(() => ItemPriceFormController());
  }
}
