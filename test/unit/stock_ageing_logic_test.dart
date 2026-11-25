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
  {
    'fieldname': 'range2value',
    'label': 'Value (91 - 180)',
    'fieldtype': 'Float',
  },
  {'fieldname': 'range3', 'label': 'Age (181 - 360)', 'fieldtype': 'Float'},
  {
    'fieldname': 'range3value',
    'label': 'Value (181 - 360)',
    'fieldtype': 'Float',
  },
  {'fieldname': 'range4', 'label': 'Age (361 - 720)', 'fieldtype': 'Float'},
  {
    'fieldname': 'range4value',
    'label': 'Value (361 - 720)',
    'fieldtype': 'Float',
  },
  {'fieldname': 'range5', 'label': 'Age (721 - Above)', 'fieldtype': 'Float'},
  {
    'fieldname': 'range5value',
    'label': 'Value (721 - Above)',
    'fieldtype': 'Float',
  },
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
}) => {
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
    _row(
      '1000030',
      'WALLETS COW',
      variantOf: '301--WAL',
      qty: 22,
      age: 523,
      r5: 2,
      r5v: 10,
      r1: 20,
      r1v: 100.5,
    ),
    _row(
      '1004997',
      'POUCH LEATHER',
      warehouse: 'POS-DXB2 - KA',
      qty: 502,
      age: 4,
      r1: 502,
    ),
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
      {'item_code': 'A'},
    ]);
    expect(StockAgeingLogic.parseRows(null), isEmpty);
  });

  test(
    'num_ coerces ints, doubles and numeric strings; anything else is 0',
    () {
      expect(StockAgeingLogic.num_(3), 3.0);
      expect(StockAgeingLogic.num_(2.5), 2.5);
      expect(StockAgeingLogic.num_('4'), 4.0);
      expect(StockAgeingLogic.num_(null), 0.0);
      expect(StockAgeingLogic.num_('x'), 0.0);
    },
  );

  group('filterAndSort', () {
    List<String> codes(List<Map<String, dynamic>> r) =>
        r.map((e) => e['item_code'] as String).toList();

    test(
      'search is case-insensitive over name, code, variant-of, warehouse',
      () {
        expect(codes(StockAgeingLogic.filterAndSort(rows, search: 'wal')), [
          '1000030',
        ]);
        expect(codes(StockAgeingLogic.filterAndSort(rows, search: '301--')), [
          '1000030',
        ]);
        expect(
          codes(StockAgeingLogic.filterAndSort(rows, search: 'pos-dxb2')),
          ['1004997'],
        );
        expect(codes(StockAgeingLogic.filterAndSort(rows, search: '10049')), [
          '1004997',
        ]);
      },
    );

    test('sort keys', () {
      expect(codes(StockAgeingLogic.filterAndSort(rows)).first, '1000074');
      expect(
        codes(StockAgeingLogic.filterAndSort(rows, sort: 'qty')).first,
        '1004997',
      );
      expect(
        codes(
          StockAgeingLogic.filterAndSort(rows, sort: 'old', buckets: buckets),
        ).first,
        '1000074',
      );
      expect(codes(StockAgeingLogic.filterAndSort(rows, sort: 'code')), [
        '1000030',
        '1000074',
        '1004997',
      ]);
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
          {'a': 1, 'b': '', 'c': null, 'd': 0},
          {'a': '1'},
        ),
        isTrue,
      );
      expect(
        StockAgeingLogic.sameFilters(
          {'range': '90, 180 '},
          {'range': '90, 180'},
        ),
        isTrue,
      );
    });

    test('a changed or extra value differs', () {
      expect(StockAgeingLogic.sameFilters({'a': 1}, {'a': 2}), isFalse);
      expect(
        StockAgeingLogic.sameFilters({'a': 1, 'b': 'x'}, {'a': 1}),
        isFalse,
      );
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
          fetchedAt: lateFetch,
          now: DateTime(2026, 11, 15, 0, 10),
        ),
        isTrue,
      );
    });

    test('a fetch time in the future (clock changed) is stale', () {
      expect(stale(DateTime(2026, 11, 14, 8, 0)), isTrue);
    });
  });

  group('card fields', () {
    test('never saved gives the defaults', () {
      expect(
        StockAgeingLogic.decodeCardFields(null),
        StockAgeingLogic.defaultCardFields,
      );
      expect(
        StockAgeingLogic.decodeCardFields('x'),
        StockAgeingLogic.defaultCardFields,
      );
    });

    test('a saved selection is kept as is, unknown columns included', () {
      expect(StockAgeingLogic.decodeCardFields(['brand', 'gone']), {
        'brand',
        'gone',
      });
    });

    test('an empty saved selection stays empty', () {
      expect(StockAgeingLogic.decodeCardFields(const []), isEmpty);
    });

    test('Variant Of is on the card by default', () {
      expect(StockAgeingLogic.defaultCardFields, contains('variant_of'));
    });
  });

  group('parseColumns', () {
    final cols = StockAgeingLogic.parseColumns(const [
      {'fieldname': 'variant_of', 'label': 'Variant Of', 'fieldtype': 'Link'},
      {
        'fieldname': 'image',
        'label': 'Item Image',
        'fieldtype': 'Attach Image',
      },
      {
        'fieldname': 'range1value',
        'label': 'Value (0 - 90)',
        'fieldtype': 'Float',
      },
      {'fieldname': 'earliest', 'label': 'Earliest', 'fieldtype': 'Int'},
      {'fieldname': 'qty', 'label': '', 'fieldtype': 'Float'},
      {'label': 'no fieldname'},
      null,
      'UOM:Link/UOM:60',
    ]);

    test('keeps report order and verbatim labels', () {
      expect(cols.map((c) => c.label), [
        'Variant Of',
        'Item Image',
        'Value (0 - 90)',
        'Earliest',
        'Available Qty',
        'UOM',
      ]);
      expect(cols[1].isImage, isTrue);
      expect(cols[0].isImage, isFalse);
      expect(cols[4].listed, isFalse);
      expect(cols[5].fieldtype, 'Link');
    });

    test('formatCell follows the column type', () {
      expect(StockAgeingLogic.formatCell(cols[0], '301--WAL'), '301--WAL');
      expect(StockAgeingLogic.formatCell(cols[0], null), '—');
      expect(StockAgeingLogic.formatCell(cols[0], ' '), '—');
      expect(StockAgeingLogic.formatCell(cols[2], 110.006), '110.01');
      expect(StockAgeingLogic.formatCell(cols[3], 523), '523');
      expect(StockAgeingLogic.formatCell(cols[4], 24864.0), '24,864');
      expect(StockAgeingLogic.formatCell(cols[4], 908.71), '908.71');
    });
  });

  group('detail sheet ages', () {
    final cols = StockAgeingLogic.parseColumns(const [
      {
        'fieldname': 'average_age',
        'label': 'Average Age',
        'fieldtype': 'Float',
      },
      {'fieldname': 'earliest', 'label': 'Earliest', 'fieldtype': 'Int'},
      {'fieldname': 'latest', 'label': 'Latest', 'fieldtype': 'Int'},
      {'fieldname': 'qty', 'label': 'Available Qty', 'fieldtype': 'Float'},
    ]);
    final avg = cols[0], earliest = cols[1], latest = cols[2], qty = cols[3];
    final asOn = DateTime(2026, 11, 15);

    test('batch ages add the year they arrived', () {
      expect(
        StockAgeingLogic.formatDetailCell(earliest, 1612, asOn: asOn),
        '1,612 days · since 2022',
      );
      expect(
        StockAgeingLogic.formatDetailCell(latest, 58, asOn: asOn),
        '58 days · since 2026',
      );
      expect(
        StockAgeingLogic.formatDetailCell(latest, 1, asOn: asOn),
        '1 day · since 2026',
      );
    });

    test('the year is counted from the as-on date, across New Year', () {
      final jan5 = DateTime(2026, 1, 5);
      expect(
        StockAgeingLogic.formatDetailCell(latest, 4, asOn: jan5),
        '4 days · since 2026',
      );
      expect(
        StockAgeingLogic.formatDetailCell(latest, 5, asOn: jan5),
        '5 days · since 2025',
      );
    });

    test('average age gets the unit but no year', () {
      expect(
        StockAgeingLogic.formatDetailCell(avg, 1247.5, asOn: asOn),
        '1,247.5 days',
      );
    });

    test('no date, blank cells and other columns', () {
      expect(StockAgeingLogic.formatDetailCell(earliest, 1612), '1,612 days');
      expect(
        StockAgeingLogic.formatDetailCell(earliest, null, asOn: asOn),
        '—',
      );
      expect(StockAgeingLogic.formatDetailCell(qty, 1240, asOn: asOn), '1,240');
    });

    test('reportDate prefers the as-on date, then the fetch day', () {
      final fetched = DateTime(2026, 11, 14, 9, 42);
      expect(
        StockAgeingLogic.reportDate('2026-10-31', fetched),
        DateTime(2026, 10, 31),
      );
      expect(StockAgeingLogic.reportDate('', fetched), DateTime(2026, 11, 14));
      expect(StockAgeingLogic.reportDate('bad', null), isNull);
    });
  });

  group('imageUrl', () {
    test('relative paths are prefixed and encoded', () {
      expect(
        StockAgeingLogic.imageUrl(
          '/files/1000 ART COW.jpg',
          'https://erp.domain.com/',
        ),
        'https://erp.domain.com/files/1000%20ART%20COW.jpg',
      );
    });

    test('absolute URLs are kept; blank and null are null', () {
      expect(
        StockAgeingLogic.imageUrl('https://x.test/a.jpg', 'https://e'),
        'https://x.test/a.jpg',
      );
      expect(StockAgeingLogic.imageUrl('  ', 'https://e'), isNull);
      expect(StockAgeingLogic.imageUrl(null, 'https://e'), isNull);
    });
  });

  // A Frappe Custom Report freezes its column list, so the server returns
  // the saved bucket titles whatever range the data was calculated with.
  group('applyRange', () {
    test('matches Desk digit-only limits and ignores invalid tokens', () {
      for (final range in ['-1,360,720', '360,foo,720', '+30,360,720']) {
        final columns = StockAgeingLogic.effectiveColumns(_columns, range);
        final ages = columns.where((column) => RegExp(r'^range\d+$').hasMatch(column.fieldname));
        final values = columns.where((column) => column.fieldname.endsWith('value'));
        expect(ages.map((column) => column.interval), ['0 - 360', '361 - 720', '721 - Above']);
        expect(values.map((column) => column.interval), ['0 - 360', '361 - 720', '721 - Above']);
      }
    });
    List<String> labels(List<dynamic> cols) => [
      for (final c in cols)
        if (c is Map) '${c['fieldname']}=${c['label']}',
    ];

    test(
      'relabels and trims the frozen bucket columns to the range in effect',
      () {
        final out = StockAgeingLogic.applyRange(_columns, '360, 720');
        expect(labels(out), [
          'item_code=Item Code',
          'qty=Available Qty',
          'average_age=Average Age',
          'range1=Age (0 - 360)',
          'range1value=Value (0 - 360)',
          'range2=Age (361 - 720)',
          'range2value=Value (361 - 720)',
          'range3=Age (721 - Above)',
          'range3value=Value (721 - Above)',
        ]);
        final buckets = StockAgeingLogic.parseBuckets(out);
        expect(buckets.map((b) => b.label), [
          '0 - 360',
          '361 - 720',
          '721 - Above',
        ]);
      },
    );

    test('adds bucket columns the frozen list does not have', () {
      final out = StockAgeingLogic.applyRange(_columns, '10,20,30,40,50,60');
      final b = StockAgeingLogic.parseBuckets(out);
      expect(b.length, 7);
      expect(b.last.qtyKey, 'range7');
      expect(b.last.label, '61 - Above');
      expect(b[5].label, '51 - 60');
    });

    test('the saved range reproduces the saved titles', () {
      final out = StockAgeingLogic.applyRange(_columns, '90, 180, 360, 720');
      expect(
        StockAgeingLogic.parseBuckets(out).map((b) => b.label),
        StockAgeingLogic.parseBuckets(_columns).map((b) => b.label),
      );
    });

    test('bucket columns keep their position; other columns are untouched', () {
      final cols = [
        {'fieldname': 'qty', 'label': 'Available Qty'},
        {'fieldname': 'range1', 'label': 'Age (0 - 90)', 'fieldtype': 'Float'},
        {'fieldname': 'range1value', 'label': 'Value (0 - 90)'},
        {'fieldname': 'uom', 'label': 'UOM'},
      ];
      expect(labels(StockAgeingLogic.applyRange(cols, '30')), [
        'qty=Available Qty',
        'range1=Age (0 - 30)',
        'range1value=Value (0 - 30)',
        'range2=Age (31 - Above)',
        'range2value=Value (31 - Above)',
        'uom=UOM',
      ]);
    });

    test('a blank or unreadable range leaves the columns as sent', () {
      expect(StockAgeingLogic.applyRange(_columns, null), same(_columns));
      expect(StockAgeingLogic.applyRange(_columns, '  '), same(_columns));
      expect(StockAgeingLogic.applyRange(_columns, 'abc'), same(_columns));
    });

    test(
      'retains raw Desk labels while qualifying sorted effective intervals',
      () {
        final raw = _columns.take(5).toList();
        final columns = StockAgeingLogic.effectiveColumns(raw, '720, 360');
        final bucket = columns.firstWhere(
          (column) => column.fieldname == 'range1',
        );
        expect(bucket.label, 'Age (0 - 90)');
        expect(bucket.interval, '0 - 360');
        expect(bucket.rangeHint, 'Range for this run: 0–360');
        expect(bucket.listed, isTrue);
        final derived = columns.firstWhere(
          (column) => column.fieldname == 'range3',
        );
        expect(derived.label, 'Age (721 - Above)');
        expect(derived.listed, isFalse);
      },
    );
  });

  test(
    'legacy positionals decode equivalent keys and preserve a real zero Total',
    () {
      final descriptors = StockAgeingLogic.deskColumns([
        'Item Code:Link/Item:160',
        null,
        'Available Qty:Float:100',
        'Age (0 - 90):Float:100',
        'Value (0 - 90):Currency:100',
      ]);
      final rows = StockAgeingLogic.parseRows(
        [
          ['Total', 'ignored', 0, 0, 0],
          ['Total', null, 3, 3, 20],
        ],
        columns: descriptors,
        addTotalRow: true,
      );
      expect(rows.single, {
        'item_code': 'Total',
        'qty': 0,
        'range1': 0,
        'range1value': 0,
      });
    },
  );
}
