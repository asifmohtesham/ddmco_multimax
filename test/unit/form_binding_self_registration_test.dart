import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_binding.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_form_binding.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_binding.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';
import 'package:multimax/app/modules/work_order/form/work_order_form_binding.dart';
import 'package:multimax/app/modules/work_order/form/work_order_form_controller.dart';

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  // Regression: form routes are reachable without their list screen — the
  // Home "Needs your action" strip, global search and the workspace menu all
  // Get.toNamed(<form route>) directly. Each form controller resolves its
  // providers via Get.find at construction, so the route's own binding must
  // register them rather than rely on HomeBinding or a list binding upstream.
  // (Purchase Order was a live crash: HomeBinding never registers
  // PurchaseOrderProvider, and the Home strip opens the PO form directly.)

  test('PurchaseOrderFormBinding registers PurchaseOrderProvider', () {
    PurchaseOrderFormBinding().dependencies();

    expect(Get.isRegistered<PurchaseOrderProvider>(), isTrue,
        reason: 'form route must supply its own PurchaseOrderProvider');
    expect(Get.isRegistered<PurchaseOrderFormController>(), isTrue);
  });

  test('DeliveryNoteFormBinding registers DeliveryNoteProvider and '
      'PosUploadProvider', () {
    DeliveryNoteFormBinding().dependencies();

    expect(Get.isRegistered<DeliveryNoteProvider>(), isTrue,
        reason: 'form route must supply its own DeliveryNoteProvider');
    expect(Get.isRegistered<PosUploadProvider>(), isTrue,
        reason: 'form route must supply its own PosUploadProvider');
    expect(Get.isRegistered<WorkOrderProvider>(), isTrue);
    expect(Get.isRegistered<DeliveryNoteFormController>(), isTrue);
  });

  test('ItemFormBinding registers ItemProvider', () {
    ItemFormBinding().dependencies();

    expect(Get.isRegistered<ItemProvider>(), isTrue,
        reason: 'form route must supply its own ItemProvider');
    expect(Get.isRegistered<ItemFormController>(), isTrue);
  });

  test('WorkOrderFormBinding registers JobCardProvider', () {
    WorkOrderFormBinding().dependencies();

    expect(Get.isRegistered<JobCardProvider>(), isTrue,
        reason: 'form route must supply its own JobCardProvider');
    expect(Get.isRegistered<WorkOrderProvider>(), isTrue);
    expect(Get.isRegistered<WorkOrderFormController>(), isTrue);
  });
}
