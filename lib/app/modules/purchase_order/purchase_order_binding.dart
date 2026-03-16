import 'package:get/get.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/supplier_provider.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';

class PurchaseOrderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SupplierProvider>(() => SupplierProvider());
    Get.lazyPut<PurchaseOrderProvider>(() => PurchaseOrderProvider());
    Get.lazyPut<PurchaseOrderController>(() => PurchaseOrderController());
  }
}
