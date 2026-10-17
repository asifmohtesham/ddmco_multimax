import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

// The mobile Stock Balance filter sheet mirrors the v15 desk report
// (stock_balance.js). buildStockBalanceFilters is the wire contract for the
// query_report.run `filters` payload; previousMonth reproduces the desk's
// From Date default (frappe.datetime.add_months(today, -1)).
void main() {
  Map<String, dynamic> build({
    List<String>? warehouses,
    String? warehouseType,
    String? rack,
    String? includeUom,
    bool ageing = false,
    bool ignoreClosing = false,
    bool zero = false,
  }) =>
      ApiProvider.buildStockBalanceFilters(
        company: 'Multimax',
        fromDate: '2026-09-17',
        toDate: '2026-10-17',
        warehouses: warehouses,
        warehouseType: warehouseType,
        rack: rack,
        includeUom: includeUom,
        showStockAgeing: ageing,
        ignoreClosingBalance: ignoreClosing,
        includeZeroStockItems: zero,
      );

  group('ApiProvider.buildStockBalanceFilters', () {
    test('bare call sends only the required keys + Currency valuation', () {
      expect(build(), {
        'company': 'Multimax',
        'from_date': '2026-09-17',
        'to_date': '2026-10-17',
        'valuation_field_type': 'Currency',
      });
    });

    test('one warehouse is a scalar (works on every instance version)', () {
      expect(build(warehouses: ['WH-A'])['warehouse'], 'WH-A');
    });

    test('several warehouses are sent as a list (desk MultiSelectList)', () {
      expect(build(warehouses: ['WH-A', 'WH-B'])['warehouse'], ['WH-A', 'WH-B']);
    });

    test('blank warehouse entries are dropped; all-blank omits the key', () {
      expect(build(warehouses: ['', ' WH-A '])['warehouse'], ' WH-A ');
      expect(build(warehouses: ['', '  ']).containsKey('warehouse'), isFalse);
    });

    test('rack is an inventory-dimension filter → always a list', () {
      expect(build(rack: 'A-01-02')['rack'], ['A-01-02']);
      expect(build(rack: '').containsKey('rack'), isFalse);
    });

    test('warehouse type and include UOM are plain links', () {
      final f = build(warehouseType: 'Transit', includeUom: 'Box');
      expect(f['warehouse_type'], 'Transit');
      expect(f['include_uom'], 'Box');
    });

    test('check filters are 1 when on and absent when off', () {
      final f = build(ageing: true, ignoreClosing: true, zero: true);
      expect(f['show_stock_ageing_data'], 1);
      expect(f['ignore_closing_balance'], 1);
      expect(f['include_zero_stock_items'], 1);
      final off = build();
      expect(off.containsKey('show_stock_ageing_data'), isFalse);
      expect(off.containsKey('ignore_closing_balance'), isFalse);
      expect(off.containsKey('include_zero_stock_items'), isFalse);
    });
  });

  group('StockBalanceController.previousMonth', () {
    test('same day one month back', () {
      expect(StockBalanceController.previousMonth(DateTime(2026, 10, 17)),
          DateTime(2026, 9, 17));
    });

    test('clamps to the previous month\'s last day', () {
      expect(StockBalanceController.previousMonth(DateTime(2026, 3, 31)),
          DateTime(2026, 2, 28));
      expect(StockBalanceController.previousMonth(DateTime(2028, 3, 31)),
          DateTime(2028, 2, 29)); // leap year
      expect(StockBalanceController.previousMonth(DateTime(2026, 5, 31)),
          DateTime(2026, 4, 30));
    });

    test('January rolls back into the previous year', () {
      expect(StockBalanceController.previousMonth(DateTime(2026, 1, 15)),
          DateTime(2025, 12, 15));
    });
  });
}
