import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/purchase_order/purchase_order_controller.dart';
import 'package:ddmco_multimax/app/data/providers/purchase_order_provider.dart';

class PurchaseOrderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PurchaseOrderProvider>(() => PurchaseOrderProvider());
    Get.lazyPut<PurchaseOrderController>(() => PurchaseOrderController());
  }
}