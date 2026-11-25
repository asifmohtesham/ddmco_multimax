import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';

// The summary strip and the sticky total bar both summarise the whole result
// set. computeStockBalanceTotals derives those aggregates from the already-loaded
// rows — distinct item/warehouse counts, a negative-row count, and summed
// Opening/In/Out/Balance + stock value (reading ERPNext's bal_qty/bal_val names).
void main() {
  List<Map<String, dynamic>> rows() => [
    {
      'item_code': '2002855',
      'warehouse': 'WH-DXB3 - KA',
      'opening_qty': 12,
      'in_qty': 0,
      'out_qty': 0,
      'bal_qty': 12,
      'bal_val': 0,
    },
    {
      'item_code': '2003120',
      'warehouse': 'WH-DXB3 - KA',
      'opening_qty': 180,
      'in_qty': 64,
      'out_qty': 24,
      'bal_qty': 220,
      'bal_val': 8470,
    },
    {
      'item_code': '2001045',
      'warehouse': 'WH-DXB3 - KA',
      'opening_qty': 4,
      'in_qty': 0,
      'out_qty': 10,
      'bal_qty': -6,
      'bal_val': -126,
    },
  ];

  test('counts distinct items and warehouses', () {
    final t = computeStockBalanceTotals(rows());
    expect(t.itemCount, 3);
    expect(t.warehouseCount, 1);
  });

  test('counts negative-balance rows', () {
    final t = computeStockBalanceTotals(rows());
    expect(t.negativeCount, 1);
  });

  test('sums the ledger columns (out as magnitude)', () {
    final t = computeStockBalanceTotals(rows());
    expect(t.opening, 196);
    expect(t.inQty, 64);
    expect(t.outQty, 34); // |0| + |24| + |10|
    expect(t.balance, 226); // 12 + 220 + (-6)
  });

  test('sums total stock value including negatives', () {
    final t = computeStockBalanceTotals(rows());
    expect(t.value, 8344); // 0 + 8470 + (-126)
  });

  test('reads legacy balance_qty / string values too', () {
    final t = computeStockBalanceTotals([
      {
        'item_code': 'A',
        'warehouse': 'W1',
        'balance_qty': '5',
        'bal_val': '2.5',
      },
      {
        'item_code': 'A',
        'warehouse': 'W2',
        'balance_qty': 3,
        'balance_value': 1,
      },
    ]);
    expect(t.itemCount, 1); // same item code, two warehouses
    expect(t.warehouseCount, 2);
    expect(t.balance, 8);
    expect(t.value, 3.5);
  });

  test('empty report → all zeros', () {
    final t = computeStockBalanceTotals(const []);
    expect(t.itemCount, 0);
    expect(t.warehouseCount, 0);
    expect(t.negativeCount, 0);
    expect(t.balance, 0);
    expect(t.value, 0);
  });

  test(
    'ignores report grand total, rates, conversions and repeated reservations',
    () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          for (final key in [
            'item_code',
            'warehouse',
            'rack',
            'stock_uom',
            'bal_qty',
            'bal_val',
            'in_qty',
            'out_qty',
            'val_rate',
            'bal_qty_alt',
            'reserved_stock',
          ])
            {'fieldname': key},
        ],
        'result': [
          ['Total Tools', 'WH', 'A', 'Each', 8, 40, 2, 3, 5, 4, 17],
          ['Total Tools', 'WH', 'B', 'Pair', -3, -15, 0, 5, 5, -1.5, 17],
          ['Total', '', '', '', 5, 25, 2, 8, 10, 2.5, 34],
        ],
        'add_total_row': true,
      });
      final total = computeStockBalanceTotals(result.rows);
      expect(total.itemCount, 1);
      expect(total.warehouseCount, 1);
      expect(total.negativeCount, 1);
      expect(total.inQty, 2);
      expect(total.outQty, 8);
      expect(total.balance, 5);
      expect(total.value, 25);
    },
  );
}
