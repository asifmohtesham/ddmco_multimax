import 'package:get/get.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_tab_controller.dart';

class ItemFormBinding extends Bindings {
  @override
  void dependencies() {
    // ItemTabController MUST be registered before ItemFormController
    // because ItemFormScreen.build() calls Get.find<ItemTabController>()
    // synchronously during the first frame.
    Get.lazyPut<ItemTabController>(() => ItemTabController(), fenix: true);
    Get.lazyPut<ItemFormController>(() => ItemFormController(), fenix: true);
  }
}
