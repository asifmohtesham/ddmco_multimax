import 'package:get/get.dart';
import 'package:multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';

class PurchaseReceiptFormBinding extends Bindings {
  @override
  void dependencies() {
    // The form controller resolves both providers via Get.find at
    // construction, so this route must register them itself — it cannot rely
    // on the list binding (PurchaseReceiptBinding) having run upstream. Without
    // this, reaching the form from the Purchase Order form (or any non-list
    // entry point) crashes with "PurchaseReceiptProvider not found".
    // Guarded so we never replace a live instance registered by the list route.
    if (!Get.isRegistered<PurchaseReceiptProvider>()) {
      Get.lazyPut<PurchaseReceiptProvider>(() => PurchaseReceiptProvider());
    }
    if (!Get.isRegistered<PurchaseOrderProvider>()) {
      Get.lazyPut<PurchaseOrderProvider>(() => PurchaseOrderProvider());
    }
    Get.lazyPut<PurchaseReceiptFormController>(
      () => PurchaseReceiptFormController(),
    );
  }
}
