import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_binding.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  // Regression: the POS Upload form is reachable without the POS Upload list
  // (global search, the POS & DN Item Rate report tile, the workspace menu).
  // The form controller resolves PosUploadProvider via Get.find at
  // construction, so the route's own binding must register it — it cannot
  // rely on HomeBinding or the list binding having run upstream.
  test('PosUploadFormBinding self-registers the providers the form '
      'controller needs', () {
    PosUploadFormBinding().dependencies();

    expect(Get.isRegistered<PosUploadProvider>(), isTrue,
        reason: 'form route must supply its own PosUploadProvider');
    expect(Get.isRegistered<DeliveryNoteProvider>(), isTrue);
    expect(Get.isRegistered<StockEntryProvider>(), isTrue);
    expect(Get.isRegistered<PackingSlipProvider>(), isTrue);
    expect(Get.isRegistered<PosUploadFormController>(), isTrue);
  });
}
