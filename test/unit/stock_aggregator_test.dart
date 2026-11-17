import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_sheet/logic/stock_aggregator.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';

ClassifiedCode _code(String item, String barcode) =>
    ClassifiedCode(itemCode: item, barcode: barcode);

const _known = ItemInfo(
  itemCode: '2001141',
  itemName: 'Strap A',
  variantOf: 'Strap',
  countryOfOrigin: 'Italy',
);

void main() {
  group('StockAggregator.sumByItem', () {
    test('sums per item across warehouses and tolerates mixed types', () {
      final totals = StockAggregator.sumByItem([
        {'item_code': '2001136', 'warehouse': 'WH-DXB1 - KA', 'bal_qty': 60.0},
        {'item_code': '2001136', 'warehouse': 'WH-DXB3 - KA', 'bal_qty': -5},
        {'item_code': '2002349', 'bal_qty': '295'},
        {'item_code': '', 'bal_qty': 420},
      ]);
      expect(totals, {'2001136': 55.0, '2002349': 295.0});
    });
  });

  group('StockAggregator.build', () {
    test('an unknown valid EAN-8 is notInErp and does not stop other items', () {
      final result = StockAggregator.build(
        [
          PhotoScan(
            index: 0,
            path: '/p/0.jpg',
            rawValues: const ['20011414', '99999995'],
            items: [_code('2001141', '20011414'), _code('9999999', '99999995')],
          ),
        ],
        {'2001141': _known},
        {'2001141': 10},
      );
      expect(result.rows.length, 1);
      expect(result.unresolved.single.reason, UnresolvedReason.notInErp);
      expect(result.unresolved.single.barcode, '99999995');
      expect(result.unresolved.single.photoIndex, 0);
    });

    test('item absent from the report is out of stock', () {
      final r = StockAggregator.build(
        [PhotoScan(index: 0, path: 'a', items: [_code('2001141', '20011414')])],
        {'2001141': _known},
        {},
      );
      expect(r.rows.single.outOfStock, isTrue);
      expect(r.outOfStockCount, 1);
    });

    test('negative total is out of stock; 0.5 is in stock', () {
      StockSheetRow rowFor(double qty) => StockAggregator.build(
            [PhotoScan(index: 0, path: 'a', items: [_code('2001141', '20011414')])],
            {'2001141': _known},
            {'2001141': qty},
          ).rows.single;
      expect(rowFor(-2).outOfStock, isTrue);
      expect(rowFor(0.5).outOfStock, isFalse);
    });

    test('row carries the item details and the photo', () {
      final row = StockAggregator.build(
        [PhotoScan(index: 3, path: '/p/3.jpg', items: [_code('2001141', '20011414')])],
        {'2001141': _known},
        {'2001141': 4},
      ).rows.single;
      expect(row.photoIndex, 3);
      expect(row.photoPath, '/p/3.jpg');
      expect(row.barcode, '20011414');
      expect(row.itemName, 'Strap A');
      expect(row.variantOf, 'Strap');
      expect(row.countryOfOrigin, 'Italy');
    });

    test('the same item in two scans gives two rows, in photo order', () {
      final r = StockAggregator.build(
        [
          PhotoScan(index: 0, path: 'a', items: [_code('2001141', '20011414')]),
          PhotoScan(index: 1, path: 'b', items: [_code('2001141', '20011414')]),
        ],
        {'2001141': _known},
        {'2001141': 1},
      );
      expect(r.rows.map((x) => x.photoIndex), [0, 1]);
    });

    test('a decodeFailed scan is unreadable', () {
      final r = StockAggregator.build(
        [PhotoScan(index: 2, path: 'c', decodeFailed: true)],
        {},
        {},
      );
      expect(r.rows, isEmpty);
      expect(r.unresolved.single.reason, UnresolvedReason.unreadable);
      expect(r.unresolved.single.photoIndex, 2);
    });

    test('raw values but no classified items is noRecognisedCode', () {
      final r = StockAggregator.build(
        [PhotoScan(index: 0, path: 'a', rawValues: const ['4006381333931'])],
        {},
        {},
      );
      expect(r.rows, isEmpty);
      expect(r.unresolved.single.reason, UnresolvedReason.noRecognisedCode);
    });
  });
}
