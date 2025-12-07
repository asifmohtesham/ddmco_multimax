import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';

class PurchaseOrderFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PurchaseOrderFormController>(() => PurchaseOrderFormController());
  }
}