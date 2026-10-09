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

  // Regression (2026-10-10, found on device): choosing an invoice serial
  // lowers the qty ceiling to that voucher line's qty, but nothing
  // re-validated, so a stale "valid" sheet saved 4 onto a line of 1.
  _rackGroup();

  group('DeliveryNoteItemFormController serial change', () {
    test('T-4: selecting a serial re-runs validateSheet', () async {
      final ctrl = Get.put(_ValidateSpy());
      ctrl.selectedSerial.value = '2';
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.validations, 1);
      ctrl.selectedSerial.value = '1';
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.validations, 2);
    });
  });
}

// Desk enforces Delivery Note Item.rack via mandatory_depends_on
// (eval:doc.item_code); the server does not for API saves, so the sheet must.
void _rackGroup() {
  group('DeliveryNoteItemFormController rack is required', () {
    DeliveryNoteItemFormController ready({required String rack}) {
      final ctrl = Get.put(DeliveryNoteItemFormController());
      ctrl.qtyController.text = '1';
      ctrl.isBatchValid.value = true;
      ctrl.rackController.text = rack;
      return ctrl;
    }

    test('T-5: blank rack refuses add/update with a reason', () async {
      final ctrl = ready(rack: '  ');
      await expectLater(
        ctrl.submit(),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('Scan or choose a rack'))),
      );
    });

    test('T-6: a rack passes the rack check', () async {
      final ctrl = ready(rack: 'KA-WH-DXB1-121D');
      // Proceeds past the precondition (and then needs a parent form, which
      // this unit test does not build) — so any failure must not be the rack.
      try {
        await ctrl.submit();
      } catch (e) {
        expect(e.toString(), isNot(contains('Scan or choose a rack')));
      }
    });
  });
}

class _ValidateSpy extends DeliveryNoteItemFormController {
  int validations = 0;
  @override
  void validateSheet() => validations++;
}
