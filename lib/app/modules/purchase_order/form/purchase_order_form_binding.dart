import 'package:get/get.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';

class PurchaseOrderFormBinding extends Bindings {
  @override
  void dependencies() {
    // Self-register: the Home actionable strip and global search open this
    // form directly, and HomeBinding does not register PurchaseOrderProvider.
    Get.lazyPut<PurchaseOrderProvider>(() => PurchaseOrderProvider(), fenix: true);
    Get.lazyPut<PurchaseOrderFormController>(() => PurchaseOrderFormController());
    // PurchaseOrderItemFormController is registered on-demand (tagged) inside
    // PurchaseOrderFormController._openItemSheet() and deleted on sheet close.
    // No static registration needed here.
  }
}
