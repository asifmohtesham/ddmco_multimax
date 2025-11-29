import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';
import 'package:ddmco_multimax/app/data/providers/purchase_receipt_provider.dart';

class PurchaseReceiptBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PurchaseReceiptProvider>(() => PurchaseReceiptProvider());
    Get.lazyPut<PurchaseReceiptController>(() => PurchaseReceiptController());
  }
}
