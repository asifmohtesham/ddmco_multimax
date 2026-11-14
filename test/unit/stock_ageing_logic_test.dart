import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_logic.dart';

// Column and row shapes copied from a real "Stock Ageing - Custom" run
// (ranges 90, 180, 360, 720).
const _columns = [
  {'fieldname': 'item_code', 'label': 'Item Code', 'fieldtype': 'Link'},
  {'fieldname': 'qty', 'label': 'Available Qty', 'fieldtype': 'Float'},
  {'fieldname': 'average_age', 'label': 'Average Age', 'fieldtype': 'Float'},
  {'fieldname': 'range1', 'label': 'Age (0 - 90)', 'fieldtype': 'Float'},
  {'fieldname': 'range1value', 'label': 'Value (0 - 90)', 'fieldtype': 'Float'},
  {'fieldname': 'range2', 'label': 'Age (91 - 180)', 'fieldtype': 'Float'},
  {'fieldname': 'range2value', 'label': 'Value (91 - 180)', 'fieldtype': 'Float'},
  {'fieldname': 'range3', 'label': 'Age (181 - 360)', 'fieldtype': 'Float'},
  {'fieldname': 'range3value', 'label': 'Value (181 - 360)', 'fieldtype': 'Float'},
  {'fieldname': 'range4', 'label': 'Age (361 - 720)', 'fieldtype': 'Float'},
  {'fieldname': 'range4value', 'label': 'Value (361 - 720)', 'fieldtype': 'Float'},
  {'fieldname': 'range5', 'label': 'Age (721 - Above)', 'fieldtype': 'Float'},
  {'fieldname': 'range5value', 'label': 'Value (721 - Above)', 'fieldtype': 'Float'},
  'not a column',
];

Map<String, dynamic> _row(
  String code,
  String name, {
  String warehouse = 'WH-DXB1 - KA',
  String variantOf = '',
  num qty = 0,
  num age = 0,
  num r1 = 0,
  num r5 = 0,
  num r1v = 0,
  num r5v = 0,
}) =>
    {
      'item_code': code,
      'item_name': name,
      'variant_of': variantOf,
      'warehouse': warehouse,
      'qty': qty,
      'average_age': age,
      'range1': r1,
      'range1value': r1v,
      'range5': r5,
      'range5value': r5v,
    };

void main() {
  final buckets = StockAgeingLogic.parseBuckets(_columns);

  final rows = [
    _row('1000030', 'WALLETS COW',
        variantOf: '301--WAL', qty: 22, age: 523, r5: 2, r5v: 10, r1: 20, r1v: 100.5),
    _row('1004997', 'POUCH LEATHER',
        warehouse: 'POS-DXB2 - KA', qty: 502, age: 4, r1: 502),
    _row('1000074', 'BELT MONTENA', qty: 10, age: 900, r5: 10, r5v: 50),
  ];

  group('parseBuckets', () {
    test('reads the five ranges and their labels from the columns', () {
      expect(buckets.length, 5);
      expect(buckets.first.qtyKey, 'range1');
      expect(buckets.first.label, '0 - 90');
      expect(buckets.last.label, '721 - Above');
      expect(buckets.last.valueKey, 'range5value');
    });

    test('a label without the Age (…) wrapper is kept as is', () {
      final b = StockAgeingLogic.parseBuckets([
        {'fieldname': 'range1', 'label': '0 - 30'},
      ]);
      expect(b.single.label, '0 - 30');
    });
  });

  test('parseRows keeps maps and drops list rows and non-lists', () {
    final parsed = StockAgeingLogic.parseRows([
      {'item_code': 'A'},
      ['Total', 1, 2],
      null,
    ]);
    expect(parsed, [
      {'item_code': 'A'}
    ]);
    expect(StockAgeingLogic.parseRows(null), isEmpty);
  });

  test('num_ coerces ints, doubles and numeric strings; anything else is 0',
      () {
    expect(StockAgeingLogic.num_(3), 3.0);
    expect(StockAgeingLogic.num_(2.5), 2.5);
    expect(StockAgeingLogic.num_('4'), 4.0);
    expect(StockAgeingLogic.num_(null), 0.0);
    expect(StockAgeingLogic.num_('x'), 0.0);
  });

  group('filterAndSort', () {
    List<String> codes(List<Map<String, dynamic>> r) =>
        r.map((e) => e['item_code'] as String).toList();

    test('search is case-insensitive over name, code, variant-of, warehouse',
        () {
      expect(codes(StockAgeingLogic.filterAndSort(rows, search: 'wal')),
          ['1000030']);
      expect(codes(StockAgeingLogic.filterAndSort(rows, search: '301--')),
          ['1000030']);
      expect(codes(StockAgeingLogic.filterAndSort(rows, search: 'pos-dxb2')),
          ['1004997']);
      expect(codes(StockAgeingLogic.filterAndSort(rows, search: '10049')),
          ['1004997']);
    });

    test('sort keys', () {
      expect(codes(StockAgeingLogic.filterAndSort(rows)).first, '1000074');
      expect(
          codes(StockAgeingLogic.filterAndSort(rows, sort: 'qty')).first,
          '1004997');
      expect(
          codes(StockAgeingLogic.filterAndSort(rows,
                  sort: 'old', buckets: buckets))
              .first,
          '1000074');
      expect(codes(StockAgeingLogic.filterAndSort(rows, sort: 'code')),
          ['1000030', '1000074', '1004997']);
    });

    test('returns a new list and leaves the input order alone', () {
      final out = StockAgeingLogic.filterAndSort(rows, sort: 'code');
      expect(identical(out, rows), isFalse);
      expect(rows.first['item_code'], '1000030');
    });
  });

  test('totals sum qty, every bucket value and per-bucket qty', () {
    final t = StockAgeingLogic.totals(rows, buckets);
    expect(t.qty, 534);
    expect(t.value, closeTo(160.5, 1e-9));
    expect(t.bucketQty, [522, 0, 0, 0, 12]);
  });

  group('sameFilters', () {
    test('ignores blank, null and zero entries and compares as strings', () {
      expect(
          StockAgeingLogic.sameFilters(
              {'a': 1, 'b': '', 'c': null, 'd': 0}, {'a': '1'}),
          isTrue);
      expect(
          StockAgeingLogic.sameFilters({'range': '90, 180 '}, {'range': '90, 180'}),
          isTrue);
    });

    test('a changed or extra value differs', () {
      expect(StockAgeingLogic.sameFilters({'a': 1}, {'a': 2}), isFalse);
      expect(StockAgeingLogic.sameFilters({'a': 1, 'b': 'x'}, {'a': 1}), isFalse);
    });
  });

  group('shouldAutoRefresh', () {
    final fetched = DateTime(2026, 11, 14, 9, 0);
    bool stale(DateTime now) =>
        StockAgeingLogic.shouldAutoRefresh(fetchedAt: fetched, now: now);

    test('fresh within four hours on the same day', () {
      expect(stale(DateTime(2026, 11, 14, 9, 5)), isFalse);
      expect(stale(DateTime(2026, 11, 14, 12, 59)), isFalse);
    });

    test('stale once four hours old', () {
      expect(stale(DateTime(2026, 11, 14, 13, 0)), isTrue);
    });

    test('stale on a new calendar day even if recent', () {
      final lateFetch = DateTime(2026, 11, 14, 23, 50);
      expect(
          StockAgeingLogic.shouldAutoRefresh(
              fetchedAt: lateFetch, now: DateTime(2026, 11, 15, 0, 10)),
          isTrue);
    });

    test('a fetch time in the future (clock changed) is stale', () {
      expect(stale(DateTime(2026, 11, 14, 8, 0)), isTrue);
    });
  });

  group('card fields', () {
    test('never saved gives the defaults', () {
      expect(StockAgeingLogic.decodeCardFields(null), AgeingCardField.defaults);
      expect(StockAgeingLogic.decodeCardFields('x'), AgeingCardField.defaults);
    });

    test('round trip keeps the selection; unknown names are dropped', () {
      final chosen = {AgeingCardField.image, AgeingCardField.brand};
      final stored = StockAgeingLogic.encodeCardFields(chosen);
      expect(stored, ['image', 'brand']);
      expect(StockAgeingLogic.decodeCardFields([...stored, 'gone']), chosen);
    });

    test('an empty saved selection stays empty', () {
      expect(StockAgeingLogic.decodeCardFields(const []), isEmpty);
    });
  });

  test('rowValue sums every bucket value', () {
    expect(StockAgeingLogic.rowValue(rows.first, buckets), closeTo(110.5, 1e-9));
  });

  group('imageUrl', () {
    test('relative paths are prefixed and encoded', () {
      expect(
          StockAgeingLogic.imageUrl(
              '/files/1000 ART COW.jpg', 'https://erp.domain.com/'),
          'https://erp.domain.com/files/1000%20ART%20COW.jpg');
    });

    test('absolute URLs are kept; blank and null are null', () {
      expect(StockAgeingLogic.imageUrl('https://x.test/a.jpg', 'https://e'),
          'https://x.test/a.jpg');
      expect(StockAgeingLogic.imageUrl('  ', 'https://e'), isNull);
      expect(StockAgeingLogic.imageUrl(null, 'https://e'), isNull);
    });
  });
}
