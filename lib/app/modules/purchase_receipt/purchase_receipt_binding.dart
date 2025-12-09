import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';
import 'package:multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';

class PurchaseReceiptBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PurchaseReceiptProvider>(() => PurchaseReceiptProvider());
    Get.lazyPut<PurchaseOrderProvider>(() => PurchaseOrderProvider());
    Get.lazyPut<PurchaseReceiptController>(() => PurchaseReceiptController());
  }
}
