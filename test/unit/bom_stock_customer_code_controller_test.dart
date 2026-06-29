import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const message = {
    'columns': [
      {'fieldname': 'item_code', 'label': 'Item'},
    ],
    'result': [
      {'item_code': 'A', 'customer_code': '5067101', 'in_stock_qty': 10, 'required_qty': 5,  'running_total': 10},
      {'item_code': 'B', 'customer_code': '5067102', 'in_stock_qty': 2,  'required_qty': 8,  'running_total': 2},
      {'item_code': 'A', 'customer_code': '5067101', 'in_stock_qty': 10, 'required_qty': 5,  'running_total': 0},
      {'item_code': '',  'item_name': 'Total', 'in_stock_qty': 22, 'running_total': 12}, // total row
    ],
  };

  group('parseDataRows', () {
    test('returns empty for null / wrong-shape message', () {
      expect(BomStockCustomerCodeController.parseDataRows(null), isEmpty);
      expect(BomStockCustomerCodeController.parseDataRows({'result': 'x'}), isEmpty);
    });

    test('keeps only rows with a non-empty item_code (drops the total row)', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      expect(rows.length, 3);
      expect(rows.every((r) => (r['item_code'] as String).isNotEmpty), isTrue);
    });
  });

  group('extractTotalRow', () {
    test('returns the row whose item_code is empty', () {
      final total = BomStockCustomerCodeController.extractTotalRow(message);
      expect(total, isNotNull);
      expect(total!['in_stock_qty'], 22);
    });

    test('returns null when there is no total row', () {
      final t = BomStockCustomerCodeController.extractTotalRow({
        'result': [
          {'item_code': 'A'},
        ],
      });
      expect(t, isNull);
    });
  });

  group('isShortfall (shortage_qty)', () {
    test('true when shortage_qty > 0', () {
      expect(BomStockCustomerCodeController.isShortfall({'shortage_qty': 2004}), isTrue);
    });
    test('false when shortage_qty is 0', () {
      expect(BomStockCustomerCodeController.isShortfall({'shortage_qty': 0}), isFalse);
    });
    test('false when shortage_qty absent (no POS)', () {
      expect(BomStockCustomerCodeController.isShortfall({'in_stock_qty': 10}), isFalse);
    });
    test('coerces stringified shortage and never throws', () {
      expect(BomStockCustomerCodeController.isShortfall({'shortage_qty': '5'}), isTrue);
      expect(BomStockCustomerCodeController.isShortfall({'shortage_qty': 'n/a'}), isFalse);
    });
  });

  group('distinctCustomerCodes', () {
    test('returns distinct non-empty codes in first-seen order', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      expect(
        BomStockCustomerCodeController.distinctCustomerCodes(rows),
        ['5067101', '5067102'],
      );
    });
  });

  group('splitPosCodes', () {
    test('splits upload codes into found (present in results) and missing', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      final (found, missing) = BomStockCustomerCodeController.splitPosCodes(
        ['5067101', '5067102', '9999999'],
        rows,
      );
      expect(found, ['5067101', '5067102']);
      expect(missing, ['9999999']);
    });
  });

  group('applyRowFilter', () {
    final rows = <Map<String, dynamic>>[
      {'item_code': 'A', 'in_stock_qty': 10, 'shortage_qty': 0},
      {'item_code': 'B', 'in_stock_qty': 0,  'shortage_qty': 5},
      {'item_code': 'C', 'in_stock_qty': 3,  'shortage_qty': 2},
    ];
    test('ALL returns every row', () {
      expect(BomStockCustomerCodeController.applyRowFilter(rows, 'ALL').length, 3);
    });
    test('instock keeps positive stock only', () {
      final r = BomStockCustomerCodeController.applyRowFilter(rows, 'instock');
      expect(r.map((e) => e['item_code']), ['A', 'C']);
    });
    test('shortage keeps short rows only', () {
      final r = BomStockCustomerCodeController.applyRowFilter(rows, 'shortage');
      expect(r.map((e) => e['item_code']), ['B', 'C']);
    });
  });

  group('sumTotals', () {
    test('sums in_stock / required / shortage across rows', () {
      final rows = <Map<String, dynamic>>[
        {'in_stock_qty': 10, 'required_qty': 4, 'shortage_qty': 0},
        {'in_stock_qty': 3,  'required_qty': 8, 'shortage_qty': 5},
      ];
      final t = BomStockCustomerCodeController.sumTotals(rows);
      expect(t['in_stock'], 13);
      expect(t['required'], 12);
      expect(t['shortage'], 5);
    });
    test('empty rows give zeros', () {
      final t = BomStockCustomerCodeController.sumTotals(const []);
      expect(t, {'in_stock': 0, 'required': 0, 'shortage': 0});
    });
  });

  group('controller mutations (no network)', () {
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
      Get.testMode = true;
      if (!Get.isRegistered<ApiProvider>()) Get.put(ApiProvider());
    });
    tearDown(Get.reset);

    test('addCustomerCode dedupes and trims; removeCustomerCode removes', () {
      final c = BomStockCustomerCodeController();
      c.addCustomerCode('  5067101 ');
      c.addCustomerCode('5067101'); // duplicate
      c.addCustomerCode('5067102');
      expect(c.customerCodes, ['5067101', '5067102']);
      c.removeCustomerCode('5067101');
      expect(c.customerCodes, ['5067102']);
    });

    test('addWarehouse dedupes; clearFilters resets everything', () {
      final c = BomStockCustomerCodeController();
      c.customer.value = 'Acme';
      c.addWarehouse('Stores - M');
      c.addWarehouse('Stores - M');
      c.addCustomerCode('5067101');
      c.showExplodedView.value = true;
      c.posMissingCodes.add('9999999');
      expect(c.warehouses, ['Stores - M']);

      c.clearFilters();
      expect(c.customer.value, isNull);
      expect(c.customerCodes, isEmpty);
      expect(c.warehouses, isEmpty);
      expect(c.showExplodedView.value, isFalse);
      expect(c.hideOutOfStock.value, isFalse);
      expect(c.posUpload.value, isNull);
      expect(c.posMissingCodes, isEmpty);
      c.setRowFilter('shortage');
      c.clearFilters();
      expect(c.rowFilter.value, 'ALL');
    });
  });
}
