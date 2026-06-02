// test/unit/dn_item_form_controller_warehouse_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_item_form_controller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Stub path_provider so ApiProvider._initDio() does not throw in
    // the headless test environment (no platform plugins available).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  tearDown(() => Get.deleteAll(force: true));

  group('DeliveryNoteItemFormController.itemWarehouse', () {
    test('T-1: applyRackScan sets itemWarehouse for a parseable rack code', () {
      final ctrl = Get.put(DeliveryNoteItemFormController());
      ctrl.applyRackScan('KA-WH-DXB1-101A');
      expect(ctrl.itemWarehouse.value, equals('WH-DXB1 - KA'));
    });

    test('T-2: applyRackScan sets itemWarehouse to null for a non-parseable rack code', () {
      final ctrl = Get.put(DeliveryNoteItemFormController());
      ctrl.applyRackScan('BADRACK');
      expect(ctrl.itemWarehouse.value, isNull);
    });

    test('T-3: clearAll resets itemWarehouse to null', () {
      final ctrl = Get.put(DeliveryNoteItemFormController());
      ctrl.applyRackScan('KA-WH-DXB1-101A');
      expect(ctrl.itemWarehouse.value, isNotNull);
      ctrl.clearAll();
      expect(ctrl.itemWarehouse.value, isNull);
    });
  });
}
