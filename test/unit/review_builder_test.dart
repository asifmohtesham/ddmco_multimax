import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_sheet/logic/review_builder.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';

ClassifiedCode code(String item) =>
    ClassifiedCode(itemCode: item, barcode: '${item}5');

ItemInfo info(String item) => ItemInfo(
    itemCode: item,
    itemName: 'Name $item',
    variantOf: 'V$item',
    countryOfOrigin: 'IT');

PhotoScan scan(String path, List<ClassifiedCode> codes,
        {List<String>? raw, bool failed = false}) =>
    PhotoScan(
        index: 0,
        path: path,
        rawValues: raw ?? codes.map((c) => c.barcode).toList(),
        items: codes,
        decodeFailed: failed);

ReviewEntry entry(String path, List<String> itemCodes) => ReviewEntry(
      path: path,
      items: [
        for (final c in itemCodes)
          ReviewItem(code: code(c), info: info(c), included: true),
      ],
    );

ReviewEntry unresolved(String path,
        {bool failed = false, List<String> notInErp = const []}) =>
    ReviewEntry(path: path, decodeFailed: failed, notInErp: notInErp);

void main() {
  group('entryFor', () {
    test('known and unknown code: one item, one notInErp', () {
      final e = ReviewBuilder.entryFor(
        scan('a.jpg', [code('1002312'), const ClassifiedCode(itemCode: '9999999', barcode: '99999995')]),
        {'1002312': info('1002312')},
        {},
      );
      expect(e.items.length, 1);
      expect(e.items.first.included, isTrue);
      expect(e.notInErp, ['99999995']);
      expect(e.resolved, isTrue);
    });

    test('all unknown: unresolved and not included', () {
      final e = ReviewBuilder.entryFor(
        scan('a.jpg', [const ClassifiedCode(itemCode: '9999999', barcode: '99999995')]),
        {},
        {},
      );
      expect(e.resolved, isFalse);
      expect(e.included, isFalse);
      expect(e.notInErp, ['99999995']);
    });

    test('decodeFailed is unresolved', () {
      final e = ReviewBuilder.entryFor(scan('a.jpg', [], failed: true), {}, {});
      expect(e.decodeFailed, isTrue);
      expect(e.resolved, isFalse);
      expect(e.included, isFalse);
    });

    test('stock is attached by item code', () {
      const s = ItemStock(total: 5, racks: [RackQty(rack: 'R1', qty: 5)]);
      final e = ReviewBuilder.entryFor(
          scan('a.jpg', [code('1002312')]),
          {'1002312': info('1002312')},
          {'1002312': s});
      expect(e.items.first.stock, same(s));
    });
  });

  group('switches', () {
    test('row off clears both items', () {
      final r = ReviewBuilder.setIncluded([entry('a', ['1', '2'])], 0, false);
      expect(r[0].items.every((i) => !i.included), isTrue);
      expect(r[0].included, isFalse);
    });

    test('item off then the other off: entry not included', () {
      var l = [entry('a', ['1', '2'])];
      l = ReviewBuilder.setItemIncluded(l, 0, 0, false);
      expect(l[0].included, isTrue);
      l = ReviewBuilder.setItemIncluded(l, 0, 1, false);
      expect(l[0].included, isFalse);
    });

    test('row on sets all on', () {
      var l = ReviewBuilder.setIncluded([entry('a', ['1', '2'])], 0, false);
      l = ReviewBuilder.setIncluded(l, 0, true);
      expect(l[0].items.every((i) => i.included), isTrue);
    });

    test('setIncluded on unresolved entry changes nothing', () {
      final l = [unresolved('a')];
      final r = ReviewBuilder.setIncluded(l, 0, true);
      expect(r[0].included, isFalse);
      expect(r[0].items, isEmpty);
    });

    test('does not mutate the input list', () {
      final l = [entry('a', ['1'])];
      ReviewBuilder.setIncluded(l, 0, false);
      expect(l[0].included, isTrue);
    });
  });

  group('reorder', () {
    final l = [for (final p in ['a', 'b', 'c', 'd']) entry(p, ['1'])];
    List<String> paths(List<ReviewEntry> x) => x.map((e) => e.path).toList();

    test('0 to 3', () {
      expect(paths(ReviewBuilder.reorder(l, 0, 3)), ['b', 'c', 'a', 'd']);
    });
    test('3 to 0', () {
      expect(paths(ReviewBuilder.reorder(l, 3, 0)), ['d', 'a', 'b', 'c']);
    });
  });

  group('toResult', () {
    test('rows only for included items, photoIndex is list position', () {
      final two = entry('a', ['1', '2']);
      final l = ReviewBuilder.setItemIncluded([two, entry('c', ['3'])], 0, 1, false);
      final r = ReviewBuilder.toResult(l);
      expect(r.rows.map((x) => x.barcode), ['15', '35']);
      expect(r.rows.map((x) => x.photoIndex), [0, 1]);
      expect(r.rows.first.photoPath, 'a');
      expect(r.rows.first.itemName, 'Name 1');
      expect(r.rows.first.variantOf, 'V1');
      expect(r.rows.first.countryOfOrigin, 'IT');
      expect(r.unresolved, isEmpty);
    });

    test('same item in two entries gives two rows', () {
      final r = ReviewBuilder.toResult(
          [entry('a', ['1002312']), entry('b', ['1002312'])]);
      expect(r.rows.length, 2);
    });

    test('outOfStock when stock is null or zero', () {
      const zero = ItemStock(total: 0, racks: []);
      const some = ItemStock(total: 2, racks: [RackQty(rack: null, qty: 2)]);
      ReviewEntry withStock(String c, ItemStock? s) => ReviewEntry(
          path: c,
          items: [ReviewItem(code: code(c), info: info(c), stock: s)]);
      final r = ReviewBuilder.toResult(
          [withStock('1', null), withStock('2', zero), withStock('3', some)]);
      expect(r.rows.map((x) => x.outOfStock), [true, true, false]);
    });

    test('switched-off entries add nothing', () {
      final l = ReviewBuilder.setIncluded([entry('a', ['1'])], 0, false);
      final r = ReviewBuilder.toResult(l);
      expect(r.rows, isEmpty);
      expect(r.unresolved, isEmpty);
    });

    test('unresolved entries give one each with the right reason', () {
      final r = ReviewBuilder.toResult([
        unresolved('a', failed: true),
        unresolved('b', notInErp: ['99999995', '88888885']),
        unresolved('c'),
      ]);
      expect(r.rows, isEmpty);
      expect(r.unresolved.map((u) => u.reason), [
        UnresolvedReason.unreadable,
        UnresolvedReason.notInErp,
        UnresolvedReason.noRecognisedCode,
      ]);
      expect(r.unresolved[1].barcode, '99999995');
      expect(r.unresolved.map((u) => u.photoIndex), [0, 1, 2]);
      expect(r.unresolved.map((u) => u.photoPath), ['a', 'b', 'c']);
    });

    test('resolved entry leftover notInErp adds nothing', () {
      final e = entry('a', ['1']).copyWith(notInErp: ['99999995']);
      expect(ReviewBuilder.toResult([e]).unresolved, isEmpty);
    });
  });

  test('sheetPhotoCount counts entries with an included item', () {
    var l = [entry('a', ['1']), entry('b', ['2']), unresolved('c')];
    l = ReviewBuilder.setIncluded(l, 1, false);
    expect(ReviewBuilder.sheetPhotoCount(l), 1);
  });
}
