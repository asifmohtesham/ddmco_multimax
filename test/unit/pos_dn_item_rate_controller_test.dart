import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

void main() {
  // Canned query_report.run message with all four statuses (keyed rows).
  const message = {
    'columns': [
      {'fieldname': 'status', 'label': 'Status'},
      {'fieldname': 'ref_code', 'label': 'Customer Code'},
      {'fieldname': 'item_code', 'label': 'Item Code'},
    ],
    'result': [
      {'status': 'New', 'ref_code': '5067101', 'item_code': '2001272',
       'dn_item': 'STRAPS T/X', 'upload_item': 'STRAP TX', 'customer': 'MBT'},
      {'status': 'Already mapped', 'ref_code': '5067102', 'item_code': '2001273',
       'dn_item': 'BELTS PU', 'upload_item': 'BELT PU', 'customer': 'MBT'},
      {'status': 'No delivery line', 'ref_code': '5067103', 'item_code': null,
       'dn_item': null, 'upload_item': 'WALLETS COW', 'customer': null},
      {'status': 'No code', 'ref_code': null, 'item_code': null,
       'dn_item': null, 'upload_item': 'CARD CASE', 'customer': null},
    ],
  };

  group('parseRows', () {
    test('returns empty for null / wrong-shape message', () {
      expect(PosDnItemRateController.parseRows(null), isEmpty);
      expect(PosDnItemRateController.parseRows({'result': 'x'}), isEmpty);
    });

    test('parses keyed (list-of-maps) rows', () {
      final rows = PosDnItemRateController.parseRows(message);
      expect(rows.length, 4);
      expect(rows.first['ref_code'], '5067101');
    });

    test('parses positional (list-of-lists) rows by zipping column fieldnames',
        () {
      final rows = PosDnItemRateController.parseRows(const {
        'columns': [
          {'fieldname': 'status'},
          {'fieldname': 'ref_code'},
          {'fieldname': 'item_code'},
        ],
        'result': [
          ['New', '5067101', '2001272'],
        ],
      });
      expect(rows.single['status'], 'New');
      expect(rows.single['item_code'], '2001272');
    });
  });

  group('statusCounts', () {
    test('counts each status', () {
      final rows = PosDnItemRateController.parseRows(message);
      final c = PosDnItemRateController.statusCounts(rows);
      expect(c[PosDnItemRateController.statusNew], 1);
      expect(c[PosDnItemRateController.statusMapped], 1);
      expect(c[PosDnItemRateController.statusNoDelivery], 1);
      expect(c[PosDnItemRateController.statusNoCode], 1);
    });
  });

  group('applyFilters', () {
    final rows = PosDnItemRateController.parseRows(message);

    test('ALL + empty query returns everything', () {
      expect(PosDnItemRateController.applyFilters(rows, 'ALL', ''), rows);
    });

    test('status filter matches exactly', () {
      final out =
          PosDnItemRateController.applyFilters(rows, 'No delivery line', '');
      expect(out.single['ref_code'], '5067103');
    });

    test('text query is case-insensitive across code/item/customer fields', () {
      expect(
          PosDnItemRateController.applyFilters(rows, 'ALL', 'straps').length, 1);
      expect(PosDnItemRateController.applyFilters(rows, 'ALL', '5067102')
          .single['status'], 'Already mapped');
      expect(PosDnItemRateController.applyFilters(rows, 'ALL', 'mbt').length, 2);
    });

    test('status filter and query compose', () {
      expect(
        PosDnItemRateController.applyFilters(rows, 'New', 'wallets'),
        isEmpty,
      );
    });
  });

  group('defaultFromDate', () {
    test('is 30 days before now, yyyy-MM-dd zero-padded', () {
      expect(PosDnItemRateController.defaultFromDate(DateTime(2026, 7, 3)),
          '2026-06-03');
      expect(PosDnItemRateController.defaultFromDate(DateTime(2026, 1, 5)),
          '2025-12-06');
    });
  });
}
