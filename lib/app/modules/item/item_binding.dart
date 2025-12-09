
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/data/providers/item_provider.dart';

class ItemBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ItemProvider>(() => ItemProvider());
    Get.lazyPut<ItemController>(() => ItemController());
  }
}
