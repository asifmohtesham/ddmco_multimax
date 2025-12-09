import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';

class PurchaseReceiptFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PurchaseReceiptFormController>(
      () => PurchaseReceiptFormController(),
    );
  }
}
