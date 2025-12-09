
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';

class ItemFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ItemFormController>(() => ItemFormController());
  }
}
