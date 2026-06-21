import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

// The Phase-2 quick filters are a pure client-side view over the loaded rows:
// search (code OR name), warehouse facet, a 4-way state segment, hide-empty, and
// a sort. filterAndSortRows encodes that, reading ERPNext's bal_qty/bal_val
// fieldnames. attachItemImages surfaces the item image (absent from the report
// response) as an absolute URL.
void main() {
  List<Map<String, dynamic>> rows() => [
        {'item_code': '2002855', 'item_name': 'BELTS FORMAL AUTO CP', 'warehouse': 'WH-A', 'bal_qty': 12, 'in_qty': 0, 'out_qty': 0, 'bal_val': 0},
        {'item_code': '2003120', 'item_name': 'WALLET BIFOLD', 'warehouse': 'WH-B', 'bal_qty': 220, 'in_qty': 64, 'out_qty': 24, 'bal_val': 8470},
        {'item_code': '2001045', 'item_name': 'BELT NICKEL', 'warehouse': 'WH-A', 'bal_qty': -6, 'in_qty': 0, 'out_qty': 10, 'bal_val': -126},
        {'item_code': '2004890', 'item_name': 'CARD HOLDER', 'warehouse': 'WH-B', 'bal_qty': 0, 'in_qty': 0, 'out_qty': 0, 'bal_val': 0},
      ];

  List<String> codes(List<Map<String, dynamic>> r) =>
      r.map((e) => e['item_code'].toString()).toList();

  group('filterAndSortRows — filtering', () {
    test('no filters → all rows (default bal-asc sort)', () {
      final r = StockBalanceController.filterAndSortRows(rows());
      // bal asc: -6, 0, 12, 220
      expect(codes(r), ['2001045', '2004890', '2002855', '2003120']);
    });

    test('warehouse facet restricts to the chosen warehouse', () {
      final r = StockBalanceController.filterAndSortRows(rows(), warehouse: 'WH-A');
      expect(codes(r).toSet(), {'2002855', '2001045'});
    });

    test('search matches item_code OR item_name, case-insensitive', () {
      expect(codes(StockBalanceController.filterAndSortRows(rows(), search: 'wallet')),
          ['2003120']);
      expect(codes(StockBalanceController.filterAndSortRows(rows(), search: '2001045')),
          ['2001045']);
      expect(codes(StockBalanceController.filterAndSortRows(rows(), search: 'belt')).toSet(),
          {'2002855', '2001045'});
    });

    test('state segment: instock / neg / empty', () {
      expect(codes(StockBalanceController.filterAndSortRows(rows(), state: 'instock')).toSet(),
          {'2002855', '2003120'});
      expect(codes(StockBalanceController.filterAndSortRows(rows(), state: 'neg')),
          ['2001045']);
      expect(codes(StockBalanceController.filterAndSortRows(rows(), state: 'empty')),
          ['2004890']);
    });

    test('hideEmpty drops zero-balance rows', () {
      final r = StockBalanceController.filterAndSortRows(rows(), hideEmpty: true);
      expect(codes(r).contains('2004890'), isFalse);
      expect(r.length, 3);
    });

    test('filters combine (warehouse + hideEmpty)', () {
      final r = StockBalanceController.filterAndSortRows(rows(),
          warehouse: 'WH-A', hideEmpty: true);
      expect(codes(r).toSet(), {'2002855', '2001045'});
    });
  });

  group('filterAndSortRows — sorting', () {
    test('bal ascending surfaces negatives first', () {
      final r = StockBalanceController.filterAndSortRows(rows(), sort: 'bal');
      expect(codes(r), ['2001045', '2004890', '2002855', '2003120']);
    });

    test('value descending', () {
      final r = StockBalanceController.filterAndSortRows(rows(), sort: 'val');
      expect(codes(r).first, '2003120'); // 8470 highest
      expect(codes(r).last, '2001045');  // -126 lowest
    });

    test('movement = |in| + |out| descending', () {
      final r = StockBalanceController.filterAndSortRows(rows(), sort: 'move');
      // moves: 2002855=0, 2003120=88, 2001045=10, 2004890=0
      expect(codes(r).first, '2003120');
    });

    test('code ascending', () {
      final r = StockBalanceController.filterAndSortRows(rows(), sort: 'code');
      expect(codes(r), ['2001045', '2002855', '2003120', '2004890']);
    });
  });

  group('attachItemImages', () {
    test('prefixes relative paths with the base URL', () {
      final r = StockBalanceController.attachItemImages(
        [
          {'item_code': 'A'},
          {'item_code': 'B'},
        ],
        {'A': '/files/a.jpg'},
        'https://erp.example.com',
      );
      expect(r[0]['item_image'], 'https://erp.example.com/files/a.jpg');
      expect(r[1].containsKey('item_image'), isFalse);
    });

    test('keeps absolute URLs as-is and trims a trailing slash on base', () {
      final r = StockBalanceController.attachItemImages(
        [
          {'item_code': 'A'},
          {'item_code': 'B'},
        ],
        {'A': 'https://cdn.example.com/a.png', 'B': '/files/b.png'},
        'https://erp.example.com/',
      );
      expect(r[0]['item_image'], 'https://cdn.example.com/a.png');
      expect(r[1]['item_image'], 'https://erp.example.com/files/b.png');
    });

    test('empty map → rows unchanged', () {
      final r = StockBalanceController.attachItemImages(
        [{'item_code': 'A'}],
        const {},
        'https://erp.example.com',
      );
      expect(r.first.containsKey('item_image'), isFalse);
    });
  });
}
