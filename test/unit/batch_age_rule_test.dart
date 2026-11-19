import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';

const _dxb1 = 'WH-DXB1 - KA';
const _dxb3 = 'WH-DXB3 - KA';
const _shop = 'POS-DXB1 - KA';

BatchStockLine _stock(String batch, double qty, [String wh = _dxb1]) =>
    BatchStockLine(batchNo: batch, warehouse: wh, qty: qty);

BatchDraftLine _draft(String batch, double qty, [String wh = _dxb1]) =>
    BatchDraftLine(batchNo: batch, warehouse: wh, qty: qty);

BatchAge _received(int y, int m, int d) =>
    BatchAge(DateTime(y, m, d), fromReceipt: true);

void main() {
  group('batchAgeRuleApplies', () {
    test('covers WH- warehouses only', () {
      expect(batchAgeRuleApplies('WH-DXB1 - KA'), isTrue);
      expect(batchAgeRuleApplies('WH-ECOM - KA'), isTrue);
      expect(batchAgeRuleApplies(' wh-wip1 - KA'), isTrue);
      expect(batchAgeRuleApplies('POS-DXB1 - KA'), isFalse);
      expect(batchAgeRuleApplies('Goods In Transit - KA'), isFalse);
      expect(batchAgeRuleApplies(''), isFalse);
      expect(batchAgeRuleApplies(null), isFalse);
    });
  });

  group('parseBatchAgeDate', () {
    test('reads a date and the date part of a datetime', () {
      expect(parseBatchAgeDate('2026-11-18'), DateTime(2026, 11, 18));
      expect(parseBatchAgeDate('2025-06-09 10:28:31.403897'),
          DateTime(2025, 6, 9));
    });

    test('keeps the server day: a late-evening time does not roll over', () {
      expect(parseBatchAgeDate('2026-11-18 23:59:59.999999'),
          DateTime(2026, 11, 18));
    });

    test('returns null for blanks and junk', () {
      expect(parseBatchAgeDate(null), isNull);
      expect(parseBatchAgeDate(''), isNull);
      expect(parseBatchAgeDate('yesterday'), isNull);
      expect(parseBatchAgeDate('2026-13-40'), isNull);
    });
  });

  group('resolveBatchAge', () {
    test('the earliest Purchase Receipt wins over the Batch dates', () {
      final age = resolveBatchAge(
        firstReceipt: DateTime(2026, 9, 23),
        manufacturing: DateTime(2026, 8, 1),
        creation: DateTime(2026, 8, 1, 9),
      );
      expect(age!.date, DateTime(2026, 9, 23));
      expect(age.fromReceipt, isTrue);
    });

    test('falls back to manufacturing date, then creation', () {
      final mfg = resolveBatchAge(
          manufacturing: DateTime(2004, 7, 3), creation: DateTime(2025, 6, 9));
      expect(mfg!.date, DateTime(2004, 7, 3));
      expect(mfg.fromReceipt, isFalse);

      final created = resolveBatchAge(creation: DateTime(2025, 6, 9, 10, 28));
      expect(created!.date, DateTime(2025, 6, 9));
      expect(created.fromReceipt, isFalse);
    });

    test('is null when nothing is known', () {
      expect(resolveBatchAge(), isNull);
    });
  });

  group('findOlderBatches', () {
    final ages = {
      'OLD': _received(2025, 9, 10),
      'MID': _received(2026, 3, 14),
      'NEW': _received(2026, 7, 16),
    };

    test('refuses a newer batch while an older one has stock', () {
      final older = findOlderBatches(
        batchNo: 'NEW',
        stock: [_stock('OLD', 69), _stock('NEW', 500)],
        ages: ages,
      );
      expect(older.map((o) => o.batchNo), ['OLD']);
      expect(older.single.availableQty, 69);
      expect(older.single.qtyByWarehouse, {_dxb1: 69.0});
    });

    test('lets the oldest batch through', () {
      expect(
        findOlderBatches(
          batchNo: 'OLD',
          stock: [_stock('OLD', 69), _stock('NEW', 500)],
          ages: ages,
        ),
        isEmpty,
      );
    });

    test('lists every older batch, oldest first', () {
      final older = findOlderBatches(
        batchNo: 'NEW',
        stock: [_stock('MID', 60), _stock('OLD', 20), _stock('NEW', 1)],
        ages: ages,
      );
      expect(older.map((o) => o.batchNo), ['OLD', 'MID']);
    });

    test('a batch received the same day is not older', () {
      final sameDay = {
        'A': _received(2026, 7, 16),
        'B': _received(2026, 7, 16),
      };
      final stock = [_stock('A', 10), _stock('B', 10)];
      expect(findOlderBatches(batchNo: 'A', stock: stock, ages: sameDay),
          isEmpty);
      expect(findOlderBatches(batchNo: 'B', stock: stock, ages: sameDay),
          isEmpty);
    });

    test('a batch with no receipt counts by its fallback date', () {
      final mixed = {
        'LEGACY': BatchAge(DateTime(2004, 7, 3), fromReceipt: false),
        'NEW': _received(2026, 9, 23),
      };
      final older = findOlderBatches(
        batchNo: 'NEW',
        stock: [_stock('LEGACY', 1136), _stock('NEW', 111)],
        ages: mixed,
      );
      expect(older.single.batchNo, 'LEGACY');
      expect(older.single.age.fromReceipt, isFalse);
    });

    test('older stock in a sibling WH- warehouse blocks', () {
      final older = findOlderBatches(
        batchNo: 'NEW',
        stock: [_stock('OLD', 2400, _dxb3), _stock('NEW', 833)],
        ages: ages,
      );
      expect(older.single.qtyByWarehouse, {_dxb3: 2400.0});
    });

    test('stock outside the WH- warehouses never blocks', () {
      expect(
        findOlderBatches(
          batchNo: 'NEW',
          stock: [
            _stock('OLD', 40, _shop),
            _stock('OLD', 12, 'Goods In Transit - KA'),
            _stock('NEW', 833),
          ],
          ages: ages,
        ),
        isEmpty,
      );
    });

    test('quantities on drafts are taken off the older batch', () {
      final stock = [_stock('OLD', 12), _stock('NEW', 500)];

      // The whole older batch is already picked on drafts: nothing left.
      expect(
        findOlderBatches(
          batchNo: 'NEW',
          stock: stock,
          ages: ages,
          drafts: [_draft('OLD', 5), _draft('OLD', 7)],
        ),
        isEmpty,
      );

      // Only part of it is: the rest must still ship first.
      final older = findOlderBatches(
        batchNo: 'NEW',
        stock: stock,
        ages: ages,
        drafts: [_draft('OLD', 5)],
      );
      expect(older.single.availableQty, 7);
    });

    test('a draft in one warehouse does not free stock in another', () {
      final older = findOlderBatches(
        batchNo: 'NEW',
        stock: [_stock('OLD', 12), _stock('OLD', 30, _dxb3), _stock('NEW', 5)],
        ages: ages,
        drafts: [_draft('OLD', 50)], // over-drawn in DXB1 only
      );
      expect(older.single.qtyByWarehouse, {_dxb3: 30.0});
      expect(older.single.availableQty, 30);
    });

    test('zero, negative and dust balances are not stock', () {
      expect(
        findOlderBatches(
          batchNo: 'NEW',
          stock: [
            _stock('OLD', 0),
            _stock('MID', -6),
            _stock('NEW', 10),
          ],
          ages: ages,
        ),
        isEmpty,
      );
      expect(
        findOlderBatches(
          batchNo: 'NEW',
          stock: [_stock('OLD', 0.0000001), _stock('NEW', 10)],
          ages: ages,
        ),
        isEmpty,
      );
    });

    test('ages are not needed when no other batch has stock', () {
      expect(
        findOlderBatches(
          batchNo: 'NEW',
          stock: [_stock('NEW', 10)],
          ages: const {},
        ),
        isEmpty,
      );
    });

    test('refuses to guess when an age is missing', () {
      final stock = [_stock('OLD', 5), _stock('NEW', 10)];
      expect(
        () => findOlderBatches(
            batchNo: 'NEW', stock: stock, ages: {'OLD': ages['OLD']!}),
        throwsA(isA<BatchAgeUnknown>()
            .having((e) => e.batchNo, 'batchNo', 'NEW')),
      );
      expect(
        () => findOlderBatches(
            batchNo: 'NEW', stock: stock, ages: {'NEW': ages['NEW']!}),
        throwsA(isA<BatchAgeUnknown>()
            .having((e) => e.batchNo, 'batchNo', 'OLD')),
      );
    });
  });

  group('batchesPutOutOfOrder', () {
    final ages = {
      'OLD': _received(2025, 9, 10),
      'NEW': _received(2026, 7, 16),
    };
    final stock = [_stock('OLD', 12), _stock('NEW', 500)];

    test('reducing the older row frees stock and breaks the newer row', () {
      final before = [_draft('OLD', 12), _draft('NEW', 88)];
      final after = [_draft('OLD', 2), _draft('NEW', 88)];
      expect(
        batchesPutOutOfOrder(
          stock: stock,
          ages: ages,
          otherDrafts: const [],
          linesBefore: before,
          linesAfter: after,
        ),
        ['NEW'],
      );
    });

    test('removing the older row breaks the newer row', () {
      expect(
        batchesPutOutOfOrder(
          stock: stock,
          ages: ages,
          otherDrafts: const [],
          linesBefore: [_draft('OLD', 12), _draft('NEW', 88)],
          linesAfter: [_draft('NEW', 88)],
        ),
        ['NEW'],
      );
    });

    test('removing or reducing the newer row is always fine', () {
      final before = [_draft('OLD', 12), _draft('NEW', 88)];
      expect(
        batchesPutOutOfOrder(
          stock: stock,
          ages: ages,
          otherDrafts: const [],
          linesBefore: before,
          linesAfter: [_draft('OLD', 12)],
        ),
        isEmpty,
      );
      expect(
        batchesPutOutOfOrder(
          stock: stock,
          ages: ages,
          otherDrafts: const [],
          linesBefore: before,
          linesAfter: [_draft('OLD', 12), _draft('NEW', 10)],
        ),
        isEmpty,
      );
    });

    test('a row that already broke the rule is left alone', () {
      // A supervisor added NEW in Desk while OLD still had stock.
      final before = [_draft('OLD', 4), _draft('NEW', 88)];
      final after = [_draft('OLD', 1), _draft('NEW', 88)];
      expect(
        batchesPutOutOfOrder(
          stock: stock,
          ages: ages,
          otherDrafts: const [],
          linesBefore: before,
          linesAfter: after,
        ),
        isEmpty,
      );
    });

    test('another draft holding the older stock keeps the edit legal', () {
      expect(
        batchesPutOutOfOrder(
          stock: stock,
          ages: ages,
          otherDrafts: [_draft('OLD', 12)],
          linesBefore: [_draft('OLD', 12), _draft('NEW', 88)],
          linesAfter: [_draft('NEW', 88)],
        ),
        isEmpty,
      );
    });

    test('rows outside the WH- warehouses are not judged', () {
      expect(
        batchesPutOutOfOrder(
          stock: stock,
          ages: ages,
          otherDrafts: const [],
          linesBefore: [_draft('NEW', 88, _shop)],
          linesAfter: [_draft('NEW', 88, _shop)],
        ),
        isEmpty,
      );
    });
  });
}
