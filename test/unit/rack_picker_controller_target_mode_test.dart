// test/unit/rack_picker_controller_target_mode_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';

class _FakeApiProvider extends ApiProvider {
  final List<String> racks;
  _FakeApiProvider(this.racks);

  @override
  Future<List<String>> getRacksByWarehouse(String warehouse) async => racks;
}

class _ThrowingApiProvider extends ApiProvider {
  @override
  Future<List<String>> getRacksByWarehouse(String warehouse) async =>
      throw Exception('network error');
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Stub the path_provider channel so ApiProvider._initDio() doesn't throw
    // in a headless test environment (no platform plugins available).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  tearDown(() => Get.deleteAll(force: true));

  group('RackPickerController.loadForTarget', () {
    test('sets isTargetMode to true', () async {
      Get.put<ApiProvider>(_FakeApiProvider(['KA-WH-DXB1-101A']));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(ctrl.isTargetMode.value, isTrue);
    });

    test('all entries have requestedQty == 0', () async {
      Get.put<ApiProvider>(_FakeApiProvider([
        'KA-WH-DXB1-101A',
        'KA-WH-DXB1-102A',
      ]));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(ctrl.entries.every((e) => e.requestedQty == 0.0), isTrue);
    });

    test('all entries have SufficiencyStatus.unknown', () async {
      Get.put<ApiProvider>(_FakeApiProvider(['KA-WH-DXB1-101A', 'KA-WH-DXB1-101B']));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(
        ctrl.entries.every((e) => e.status == SufficiencyStatus.unknown),
        isTrue,
      );
    });

    test('entries are sorted aisle-ascending then shelf-ascending', () async {
      Get.put<ApiProvider>(_FakeApiProvider([
        'KA-WH-DXB1-102B',
        'KA-WH-DXB1-101A',
        'KA-WH-DXB1-102A',
        'KA-WH-DXB1-101B',
      ]));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(
        ctrl.entries.map((e) => e.rackName).toList(),
        equals([
          'KA-WH-DXB1-101A',
          'KA-WH-DXB1-101B',
          'KA-WH-DXB1-102A',
          'KA-WH-DXB1-102B',
        ]),
      );
    });

    test('entries are empty and isLoading is false when warehouse is empty', () async {
      Get.put<ApiProvider>(_FakeApiProvider(['KA-WH-DXB1-101A']));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: '', currentRack: '');
      expect(ctrl.entries, isEmpty);
      expect(ctrl.isLoading.value, isFalse);
    });

    test('sets selectedRack to currentRack', () async {
      Get.put<ApiProvider>(_FakeApiProvider(['KA-WH-DXB1-101A']));
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(
        warehouse:   'WH-DXB1 - KA',
        currentRack: 'KA-WH-DXB1-101A',
      );
      expect(ctrl.selectedRack.value, equals('KA-WH-DXB1-101A'));
    });

    test('entries are empty and isLoading is false when API throws', () async {
      Get.put<ApiProvider>(_ThrowingApiProvider());
      final ctrl = Get.put(RackPickerController());
      await ctrl.loadForTarget(warehouse: 'WH-DXB1 - KA', currentRack: '');
      expect(ctrl.entries, isEmpty);
      expect(ctrl.isLoading.value, isFalse);
    });
  });
}
