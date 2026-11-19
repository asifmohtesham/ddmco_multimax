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
  group('entriesFor', () {
    const unknown = ClassifiedCode(itemCode: '9999999', barcode: '99999995');

    test('one item: one row whose id is the path', () {
      final rows = ReviewBuilder.entriesFor(
        scan('a.jpg', [code('1002312')]),
        {'1002312': info('1002312')},
        {},
      );
      expect(rows, hasLength(1));
      expect(rows.single.id, 'a.jpg');
      expect(rows.single.items.single.included, isTrue);
    });

    test('a sheet of items: one row per item, in the order read', () {
      final rows = ReviewBuilder.entriesFor(
        scan('a.jpg', [code('3'), code('1'), code('2')]),
        {for (final c in ['1', '2', '3']) c: info(c)},
        {},
      );
      expect(rows.map((r) => r.items.single.code.itemCode), ['3', '1', '2']);
      expect(rows.map((r) => r.path).toSet(), {'a.jpg'});
      expect(rows.map((r) => r.id).toSet(), hasLength(3));
      expect(rows.every((r) => r.notInErp.isEmpty), isTrue);
    });

    test('a known and an unknown code: an item row, then a Not in ERP row', () {
      final rows = ReviewBuilder.entriesFor(
        scan('a.jpg', [unknown, code('1002312')]),
        {'1002312': info('1002312')},
        {},
      );
      expect(rows, hasLength(2));
      expect(rows[0].items.single.code.itemCode, '1002312');
      expect(rows[0].notInErp, isEmpty);
      expect(rows[1].resolved, isFalse);
      expect(rows[1].notInErp, ['99999995']);
      expect(rows[0].id, isNot(rows[1].id));
    });

    test('all unknown: one unresolved row per code', () {
      final rows = ReviewBuilder.entriesFor(
        scan('a.jpg', [unknown]),
        {},
        {},
      );
      expect(rows.single.resolved, isFalse);
      expect(rows.single.included, isFalse);
      expect(rows.single.notInErp, ['99999995']);
    });

    test('decodeFailed is one unresolved row', () {
      final rows =
          ReviewBuilder.entriesFor(scan('a.jpg', [], failed: true), {}, {});
      expect(rows.single.decodeFailed, isTrue);
      expect(rows.single.resolved, isFalse);
    });

    test('stock is attached by item code', () {
      const s = ItemStock(total: 5, racks: [RackQty(rack: 'R1', qty: 5)]);
      final rows = ReviewBuilder.entriesFor(
          scan('a.jpg', [code('1002312')]),
          {'1002312': info('1002312')},
          {'1002312': s});
      expect(rows.single.items.single.stock, same(s));
    });

    test('copyWith keeps the id', () {
      final rows = ReviewBuilder.entriesFor(
        scan('a.jpg', [code('1'), code('2')]),
        {'1': info('1'), '2': info('2')},
        {},
      );
      expect(rows[1].copyWith(typed: true).id, rows[1].id);
    });

    test('a default entry is settled', () {
      final e = ReviewEntry(path: 'a');
      expect(e.stage, ReadStage.settled);
      expect(e.settled, isTrue);
      expect(e.number, 0);
      expect(e.codes, isEmpty);
    });

    test('copyWith keeps stage, number and codes, and takes new ones', () {
      final e = ReviewEntry(
        path: 'a',
        stage: ReadStage.zooming,
        number: 4,
        codes: [code('1')],
      );
      final kept = e.copyWith(typed: true);
      expect(kept.stage, ReadStage.zooming);
      expect(kept.number, 4);
      expect(kept.codes.single.itemCode, '1');
      expect(kept.settled, isFalse);
      final moved = e.copyWith(
          stage: ReadStage.settled, number: 5, codes: [code('2'), code('3')]);
      expect(moved.stage, ReadStage.settled);
      expect(moved.number, 5);
      expect(moved.codes, hasLength(2));
    });
  });

  group('switches', () {
    test('row off, then on', () {
      var l = ReviewBuilder.setIncluded([entry('a', ['1'])], 0, false);
      expect(l[0].included, isFalse);
      l = ReviewBuilder.setIncluded(l, 0, true);
      expect(l[0].included, isTrue);
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
    test('rows only for included items, photoIndex counts photos', () {
      // Two rows of photo a, one of photo c; a's second row switched off.
      final l = ReviewBuilder.setIncluded([
        entry('a', ['1']),
        ReviewEntry(path: 'a', id: 'a#1', items: entry('a', ['2']).items),
        entry('c', ['3']),
      ], 1, false);
      final r = ReviewBuilder.toResult(l);
      expect(r.rows.map((x) => x.barcode), ['15', '35']);
      expect(r.rows.map((x) => x.photoIndex), [0, 1]);
      expect(r.rows.first.photoPath, 'a');
      expect(r.rows.first.itemName, 'Name 1');
      expect(r.rows.first.variantOf, 'V1');
      expect(r.rows.first.countryOfOrigin, 'IT');
      expect(r.unresolved, isEmpty);
    });

    test('imageKey only for an Item with an ERP image', () {
      ReviewEntry withImage(String c, String? image) => ReviewEntry(
            path: c,
            items: [
              ReviewItem(
                code: code(c),
                info: ItemInfo(itemCode: c, image: image),
              ),
            ],
          );
      final r = ReviewBuilder.toResult(
          [withImage('1', '/files/1.jpg'), withImage('2', null)]);
      expect(r.rows.map((x) => x.imageKey), ['item:1', null]);
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

  test('counts: rows of one photo are one photo, each its own item', () {
    var l = [
      entry('a', ['1']),
      ReviewEntry(path: 'a', id: 'a#1', items: entry('a', ['2']).items),
      ReviewEntry(path: 'a', id: 'a#2', notInErp: const ['99999995']),
      entry('b', ['3']),
    ];
    expect(ReviewBuilder.photoCount(l), 2);
    expect(ReviewBuilder.sheetPhotoCount(l), 2);
    expect(ReviewBuilder.sheetItemCount(l), 3);
    l = ReviewBuilder.setIncluded(l, 3, false);
    expect(ReviewBuilder.sheetPhotoCount(l), 1);
    expect(ReviewBuilder.sheetItemCount(l), 2);
  });
}
