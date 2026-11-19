import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/batch_age_provider.dart';

/// The parsers behind the oldest-stock-first lookups. Row shapes are the ones
/// the live v16 server returned on 19 November 2026.
void main() {
  group('parseBatchStock', () {
    test('keyed rows: one line per batch and warehouse, Total row dropped', () {
      final lines = ApiBatchAgeDataSource.parseBatchStock({
        'result': [
          {
            'item': '2002154',
            'warehouse': 'WH-DXB1 - KA',
            'batch': '20021542-BZD',
            'balance_qty': 96.0,
          },
          {
            'item': '2002154',
            'warehouse': 'WH-DXB3 - KA',
            'batch': '20021542-BZD',
            'balance_qty': 1680.0,
          },
          {
            'item': '2002154',
            'warehouse': 'WH-DXB1 - KA',
            'batch': '20021542-OUT',
            'balance_qty': 0.0,
          },
          // The report appends its totals as a bare list.
          ['Total', null, null, null, 1776.0],
        ],
      });

      expect(lines.map((l) => '${l.warehouse}|${l.batchNo}|${l.qty}'), [
        'WH-DXB1 - KA|20021542-BZD|96.0',
        'WH-DXB3 - KA|20021542-BZD|1680.0',
      ]);
    });

    test('positional rows are read through the column list', () {
      final lines = ApiBatchAgeDataSource.parseBatchStock({
        'columns': [
          {'fieldname': 'item'},
          {'fieldname': 'warehouse'},
          {'fieldname': 'batch'},
          {'fieldname': 'balance_qty'},
        ],
        'result': [
          ['2002154', 'WH-DXB1 - KA', '20021542-BZD', 96],
          ['2002154', 'WH-DXB1 - KA', '', 96], // totals: no batch
        ],
      });
      expect(lines.single.batchNo, '20021542-BZD');
      expect(lines.single.qty, 96.0);
    });

    test('a report without a result is an error, not "no stock"', () {
      expect(
        () => ApiBatchAgeDataSource.parseBatchStock({'columns': []}),
        throwsFormatException,
      );
    });
  });

  group('parseFirstReceipts', () {
    test('keeps the earliest receipt of each batch', () {
      final first = ApiBatchAgeDataSource.parseFirstReceipts([
        {'batch_no': '20015657-4AYXY7', 'posting_date': '2026-07-23'},
        {'batch_no': '20015657-4AYXY7', 'posting_date': '2026-07-16'},
        {'batch_no': '20015657-TM6', 'posting_date': '2025-09-10'},
        {'batch_no': '', 'posting_date': '2025-01-01'},
        {'batch_no': 'NO-DATE', 'posting_date': null},
      ]);
      expect(first, {
        '20015657-4AYXY7': DateTime(2026, 7, 16),
        '20015657-TM6': DateTime(2025, 9, 10),
      });
    });
  });

  group('parseDraftRows', () {
    test('Delivery Note rows: row warehouse first, header as fallback', () {
      final lines = ApiBatchAgeDataSource.parseDraftRows(
        [
          {
            'name': 'MAT-DN-2026-01135',
            'set_warehouse': 'WH-DXB1 - KA',
            'batch_no': '10028902-4CDQ9W',
            'warehouse': 'WH-DXB3 - KA',
            'stock_qty': 36.0,
            'qty': 3.0,
          },
          {
            'name': 'MAT-DN-2026-01136',
            'set_warehouse': 'WH-DXB1 - KA',
            'batch_no': '10028902-46FTRR',
            'warehouse': null,
            'stock_qty': 0,
            'qty': 12.0,
          },
          {'name': 'MAT-DN-2026-01137', 'batch_no': null, 'qty': 5},
        ],
        doctype: 'Delivery Note',
        warehouseKeys: const ['warehouse', 'set_warehouse'],
        qtyKeys: const ['stock_qty', 'qty'],
      );

      expect(lines.length, 2);
      expect(lines[0].warehouse, 'WH-DXB3 - KA');
      expect(lines[0].qty, 36.0); // stock quantity, not the row's UOM qty
      expect(lines[0].doctype, 'Delivery Note');
      expect(lines[0].docName, 'MAT-DN-2026-01135');
      expect(lines[1].warehouse, 'WH-DXB1 - KA');
      expect(lines[1].qty, 12.0);
    });

    test('Stock Entry rows: only rows that take stock out', () {
      final lines = ApiBatchAgeDataSource.parseDraftRows(
        [
          {
            'name': 'MAT-STE-1',
            'batch_no': 'B1',
            's_warehouse': 'WH-DXB1 - KA',
            'transfer_qty': 24.0,
            'qty': 2.0,
          },
          // Receipt row: no source warehouse.
          {
            'name': 'MAT-STE-2',
            'batch_no': 'B1',
            's_warehouse': '',
            'transfer_qty': 10.0,
          },
        ],
        doctype: 'Stock Entry',
        warehouseKeys: const ['s_warehouse'],
        qtyKeys: const ['transfer_qty', 'qty'],
      );
      expect(lines.single.docName, 'MAT-STE-1');
      expect(lines.single.qty, 24.0);
    });
  });

  group('parseRackStock', () {
    test('racks with stock, largest first; empty racks dropped', () {
      final racks = ApiBatchAgeDataSource.parseRackStock({
        'result': [
          {'warehouse': 'WH-DXB1 - KA', 'rack': 'KA-WH-DXB1-16B', 'bal_qty': 321.0},
          {'warehouse': 'WH-DXB1 - KA', 'rack': 'KA-WH-DXB1-11B', 'bal_qty': 1092.0},
          {'warehouse': 'WH-DXB1 - KA', 'rack': 'KA-WH-DXB1-1A', 'bal_qty': -6.0},
          {'warehouse': 'WH-DXB1 - KA', 'rack': 'KA-WH-DXB1-30C', 'bal_qty': 0.0},
          {'warehouse': 'WH-DXB1 - KA', 'rack': null, 'bal_qty': 36.0},
        ],
      });

      expect(racks.map((r) => '${r.rack}:${r.qty}'), [
        'KA-WH-DXB1-11B:1092.0',
        'KA-WH-DXB1-16B:321.0',
        ':36.0', // stock with no rack recorded is kept
      ]);
    });

    test('rows for the same rack are added together', () {
      final racks = ApiBatchAgeDataSource.parseRackStock({
        'result': [
          {'warehouse': 'WH-DXB3 - KA', 'rack': 'KA-WH-DXB3-122A', 'bal_qty': 240.0},
          {'warehouse': 'WH-DXB3 - KA', 'rack': 'KA-WH-DXB3-122A', 'bal_qty': 2400.0},
        ],
      });
      expect(racks.single.qty, 2640.0);
    });

    test('positional rows are read through the column list', () {
      final racks = ApiBatchAgeDataSource.parseRackStock({
        'columns': [
          {'fieldname': 'item_code'},
          {'fieldname': 'warehouse'},
          {'fieldname': 'bal_qty'},
          {'fieldname': 'rack'},
        ],
        'result': [
          ['1001826', 'WH-ECOM - KA', 984, 'KA-WH-ECOM-201'],
        ],
      });
      expect(racks.single.rack, 'KA-WH-ECOM-201');
      expect(racks.single.qty, 984.0);
    });
  });
}
