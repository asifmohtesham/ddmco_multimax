import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_binding.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  // Regression: navigating to the Purchase Receipt form from the Purchase
  // Order form (or any non-list entry point) must not crash with
  // "PurchaseReceiptProvider not found". The form controller resolves both
  // providers via Get.find at construction, so the route's own binding must
  // register them — it cannot rely on the list binding having run upstream.
  test('PurchaseReceiptFormBinding self-registers the providers the form '
      'controller needs', () {
    PurchaseReceiptFormBinding().dependencies();

    expect(Get.isRegistered<PurchaseReceiptProvider>(), isTrue,
        reason: 'form route must supply its own PurchaseReceiptProvider');
    expect(Get.isRegistered<PurchaseOrderProvider>(), isTrue,
        reason: 'form route must supply its own PurchaseOrderProvider');
    expect(Get.isRegistered<PurchaseReceiptFormController>(), isTrue);
  });
}
