import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PosDnItemRateController c;

  setUpAll(() {
    // ApiProvider() fires _initDio() asynchronously which calls path_provider.
    // Stub the MethodChannel so the background async doesn't leak into tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.reset();
    Get.testMode = true;
    Get.put(ApiProvider());
    c = PosDnItemRateController();
    c.reportRows.assignAll(const [
      {'status': 'New', 'item_group': 'Straps', 'customer': 'MBT',
       'upload_qty': 5, 'dn_qty': 4},
      {'status': 'New', 'item_group': 'Straps', 'customer': 'ACE',
       'upload_qty': 2, 'dn_qty': 2},
      {'status': 'New', 'item_group': 'Buckles', 'customer': 'MBT',
       'upload_qty': 3, 'dn_qty': 0},
    ]);
  });

  tearDown(Get.reset);

  test('not grouped by default -> empty displayItems', () {
    expect(c.isGrouped, isFalse);
    expect(c.displayItems, isEmpty);
  });

  test('setPrimaryGroup builds display items over filteredRows', () {
    c.setPrimaryGroup(PosDnGroupField.itemGroup);
    expect(c.isGrouped, isTrue);
    expect(c.displayItems.where((d) => d.kind == DisplayKind.primaryHeader)
        .length, 2); // Straps, Buckles
    expect(c.displayItems.where((d) => d.kind == DisplayKind.row).length, 3);
  });

  test('secondary equal to primary is dropped', () {
    c.setPrimaryGroup(PosDnGroupField.customer);
    c.setSecondaryGroup(PosDnGroupField.customer);
    expect(c.secondaryGroup.value, isNull);
  });

  test('changing primary clears collapsed set', () {
    c.setPrimaryGroup(PosDnGroupField.itemGroup);
    c.toggleGroupCollapsed(primaryCollapseKey('Straps'));
    expect(c.collapsedGroups, isNotEmpty);
    c.setPrimaryGroup(PosDnGroupField.customer);
    expect(c.collapsedGroups, isEmpty);
  });

  test('collapseAll then expandAll', () {
    c.setPrimaryGroup(PosDnGroupField.itemGroup);
    c.collapseAllGroups();
    expect(c.displayItems.where((d) => d.kind == DisplayKind.row), isEmpty);
    c.expandAllGroups();
    expect(c.displayItems.where((d) => d.kind == DisplayKind.row).length, 3);
  });

  test('clearFilters resets grouping', () {
    c.setPrimaryGroup(PosDnGroupField.itemGroup);
    c.clearFilters();
    expect(c.primaryGroup.value, isNull);
    expect(c.isGrouped, isFalse);
  });
}
