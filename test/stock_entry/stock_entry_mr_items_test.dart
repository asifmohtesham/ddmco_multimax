// Unit tests for StockEntryFormController — MR items merge & filter.
// Covers:
//   Group 1 — mrAllItems merge logic
//   Group 2 — mrFilteredItems filter chip logic
//   Group 3 — MrItemRow computed properties
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'helpers/mock_providers.dart';

void main() {
  late StockEntryFormController controller;

  setUp(() {
    Get.testMode = true;
    registerFormFakes();
    controller = Get.put(StockEntryFormController());

    // Seed MR reference items
    controller.mrReferenceItems = [
      {
        'item_code': 'ITEM-A',
        'qty': 10.0,
        'material_request': 'MAT-MR-0001',
        'material_request_item': 'MAT-MR-0001-ITEM-1',
      },
      {
        'item_code': 'ITEM-B',
        'qty': 5.0,
        'material_request': 'MAT-MR-0001',
        'material_request_item': 'MAT-MR-0001-ITEM-2',
      },
      {
        'item_code': 'ITEM-C',
        'qty': 3.0,
        'material_request': 'MAT-MR-0001',
        'material_request_item': 'MAT-MR-0001-ITEM-3',
      },
    ];
  });

  tearDown(() async {
    await Get.deleteAll(force: true);
  });

  // -------------------------------------------------------------------------
  // Group 1 — mrAllItems merge
  // -------------------------------------------------------------------------
  group('mrAllItems', () {
    test('returns one row per MR reference item', () {
      _setItems(controller, []);
      expect(controller.mrAllItems.length, equals(3));
    });

    test('scannedQty is 0 when no entry items exist', () {
      _setItems(controller, []);
      for (final row in controller.mrAllItems) {
        expect(row.scannedQty, equals(0.0));
      }
    });

    test('scannedQty accumulates multiple scans of the same item', () {
      _setItems(controller, [
        _item('ITEM-A', 4.0),
        _item('ITEM-A', 3.0), // second scan
      ]);
      final rowA = controller.mrAllItems
          .firstWhere((r) => r.itemCode == 'ITEM-A');
      expect(rowA.scannedQty, equals(7.0));
    });

    test('scannedQty is case-insensitive item code match', () {
      _setItems(controller, [_item('item-a', 2.0)]);
      final rowA = controller.mrAllItems
          .firstWhere((r) => r.itemCode == 'ITEM-A');
      expect(rowA.scannedQty, equals(2.0));
    });

    test('other items are not affected by unrelated scans', () {
      _setItems(controller, [_item('ITEM-A', 5.0)]);
      final rowB = controller.mrAllItems
          .firstWhere((r) => r.itemCode == 'ITEM-B');
      expect(rowB.scannedQty, equals(0.0));
    });
  });

  // -------------------------------------------------------------------------
  // Group 2 — MrItemRow computed properties
  // -------------------------------------------------------------------------
  group('MrItemRow — isCompleted / isPending', () {
    test('isCompleted when scannedQty >= requestedQty', () {
      _setItems(controller, [_item('ITEM-A', 10.0)]);
      final row = controller.mrAllItems
          .firstWhere((r) => r.itemCode == 'ITEM-A');
      expect(row.isCompleted, isTrue);
      expect(row.isPending, isFalse);
    });

    test('isPending when scannedQty < requestedQty', () {
      _setItems(controller, [_item('ITEM-A', 9.0)]);
      final row = controller.mrAllItems
          .firstWhere((r) => r.itemCode == 'ITEM-A');
      expect(row.isPending, isTrue);
      expect(row.isCompleted, isFalse);
    });

    test('isCompleted when scannedQty exceeds requestedQty', () {
      _setItems(controller, [_item('ITEM-A', 12.0)]);
      final row = controller.mrAllItems
          .firstWhere((r) => r.itemCode == 'ITEM-A');
      expect(row.isCompleted, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 3 — mrFilteredItems filter chip
  // -------------------------------------------------------------------------
  group('mrFilteredItems', () {
    setUp(() {
      // ITEM-A: completed (10/10), ITEM-B: pending (2/5), ITEM-C: pending (0/3)
      _setItems(controller, [
        _item('ITEM-A', 10.0),
        _item('ITEM-B', 2.0),
      ]);
    });

    test('filter All returns all 3 rows', () {
      controller.mrItemFilter.value = 'All';
      expect(controller.mrFilteredItems.length, equals(3));
    });

    test('filter Completed returns only completed rows', () {
      controller.mrItemFilter.value = 'Completed';
      final rows = controller.mrFilteredItems;
      expect(rows.length, equals(1));
      expect(rows.first.itemCode, equals('ITEM-A'));
    });

    test('filter Pending returns only pending rows', () {
      controller.mrItemFilter.value = 'Pending';
      final rows = controller.mrFilteredItems;
      expect(rows.length, equals(2));
      expect(rows.map((r) => r.itemCode),
          containsAll(['ITEM-B', 'ITEM-C']));
    });

    test('filter counts from mrAllItems are independent of active filter', () {
      controller.mrItemFilter.value = 'Completed';
      // mrAllItems should still return all 3 regardless of filter
      expect(controller.mrAllItems.length, equals(3));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
void _setItems(StockEntryFormController c, List<StockEntryItem> items) {
  c.stockEntry.value = StockEntry(
    name: 'MAT-STE-TEST',
    purpose: 'Material Transfer',
    totalAmount: 0,
    postingDate: '2026-01-01',
    modified: '',
    creation: '2026-01-01',
    status: 'Draft',
    docstatus: 0,
    currency: 'AED',
    items: items,
  );
}

StockEntryItem _item(String itemCode, double qty) => StockEntryItem(
      itemCode: itemCode,
      qty: qty,
      basicRate: 0,
    );
