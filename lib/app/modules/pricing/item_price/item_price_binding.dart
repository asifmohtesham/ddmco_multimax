import 'package:get/get.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';

class ItemPriceBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ItemPriceProvider>()) {
      Get.lazyPut<ItemPriceProvider>(() => ItemPriceProvider(), fenix: true);
    }
    Get.lazyPut<ItemPriceController>(() => ItemPriceController());
  }
}
