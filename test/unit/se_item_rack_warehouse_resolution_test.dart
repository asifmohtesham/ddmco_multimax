// test/unit/se_item_rack_warehouse_resolution_test.dart
//
// Tests resolveRackWarehouse() in isolation. It must NOT touch the late
// _parent field, so the controller can be constructed bare via Get.put.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';

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

  StockEntryItemFormController makeController(
      Future<RackWarehouseLookup> Function(String) fetcher) {
    final ctrl = Get.put(StockEntryItemFormController());
    ctrl.rackWarehouseFetcher = fetcher;
    return ctrl;
  }

  group('StockEntryItemFormController.resolveRackWarehouse — source side', () {
    test('T-1: Rack API warehouse overwrites the name-parse value', () async {
      final ctrl = makeController(
          (_) async => const RackWarehouseLookup.found('WH-DXB9 - KA'));
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-101A', true);
      expect(ok, isTrue);
      // Name-parse would yield 'WH-DXB1 - KA'; the API value must win.
      expect(ctrl.itemSourceWarehouse.value, equals('WH-DXB9 - KA'));
    });

    test('T-2: network error keeps the optimistic name-parse value', () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.error());
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-101A', true);
      expect(ok, isTrue);
      expect(ctrl.itemSourceWarehouse.value, equals('WH-DXB1 - KA'));
    });

    test('T-3: 404 clears the warehouse and reports rack invalid', () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.notFound());
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-101A', true);
      expect(ok, isFalse);
      expect(ctrl.itemSourceWarehouse.value, isNull);
    });

    test('T-4: non-parseable rack name still gets the API warehouse',
        () async {
      final ctrl = makeController(
          (_) async => const RackWarehouseLookup.found('WH-DXB2 - KA'));
      final ok = await ctrl.resolveRackWarehouse('ODDRACK99', true);
      expect(ok, isTrue);
      expect(ctrl.itemSourceWarehouse.value, equals('WH-DXB2 - KA'));
    });

    test(
        'T-5: non-parseable rack name + network error leaves warehouse null '
        '(document default applies at submit)', () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.error());
      final ok = await ctrl.resolveRackWarehouse('ODDRACK99', true);
      expect(ok, isTrue);
      expect(ctrl.itemSourceWarehouse.value, isNull);
    });

    test('T-6: found-with-null-warehouse keeps the name-parse value',
        () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.found(null));
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-101A', true);
      expect(ok, isTrue);
      expect(ctrl.itemSourceWarehouse.value, equals('WH-DXB1 - KA'));
    });
  });

  group('StockEntryItemFormController.resolveRackWarehouse — target side', () {
    test('T-7: API warehouse lands on itemTargetWarehouse', () async {
      final ctrl = makeController(
          (_) async => const RackWarehouseLookup.found('WH-DXB3 - KA'));
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-202B', false);
      expect(ok, isTrue);
      expect(ctrl.itemTargetWarehouse.value, equals('WH-DXB3 - KA'));
      expect(ctrl.itemSourceWarehouse.value, isNull,
          reason: 'target resolution must not touch the source side');
    });

    test('T-8: 404 clears itemTargetWarehouse and reports invalid', () async {
      final ctrl =
          makeController((_) async => const RackWarehouseLookup.notFound());
      final ok = await ctrl.resolveRackWarehouse('KA-WH-DXB1-202B', false);
      expect(ok, isFalse);
      expect(ctrl.itemTargetWarehouse.value, isNull);
    });
  });
}
