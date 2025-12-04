
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/item/form/item_form_controller.dart';

class ItemFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ItemFormController>(() => ItemFormController());
  }
}
