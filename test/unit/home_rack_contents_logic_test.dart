// test/unit/home_rack_contents_logic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/rack_contents_logic.dart';

/// A Stock Balance row for rack KA-WH-DXB1-121D as ERPNext 16.55 returns it
/// (trimmed): the report carries no Item image or Country of Origin.
Map<String, dynamic> _row(String code, double qty, {String? name}) => {
  'item_code': code,
  'item_name': name ?? 'BELTS LADIES PU',
  'item_group': 'Belts',
  'stock_uom': 'Nos',
  'bal_qty': qty,
  'rack': 'KA-WH-DXB1-121D',
  'Colour': 'MIX',
};

/// The `/api/resource/Item` reply for the same codes, as the live server
/// sent it on 15/11/2026.
Map<String, dynamic> _itemBody(List<Map<String, dynamic>> data) => {
  'data': data,
};

void main() {
  group('rackItemFields', () {
    test('asks only for Item fields the report does not carry', () {
      expect(rackItemFields, contains('image'));
      expect(rackItemFields, contains('variant_of'));
      expect(rackItemFields, contains('country_of_origin'));
      expect(rackItemFields, isNot(contains('item_group')));
      expect(rackItemFields, isNot(contains('stock_uom')));
      expect(rackItemFields, isNot(contains('valuation_rate')));
      expect(rackItemFields, isNot(contains('standard_rate')));
    });
  });

  group('rackItemCodes', () {
    test('dedupes and keeps first-seen order, skipping empty codes', () {
      final rows = [
        _row('3000247', 36),
        {'item_code': '', 'bal_qty': 1},
        _row('2002849', 168),
        _row('3000247', 0), // second batch row of the same item
        {'bal_qty': 2},
      ];
      expect(rackItemCodes(rows), ['3000247', '2002849']);
    });
  });

  group('itemFieldsByCode', () {
    test('keys the Item list reply by name', () {
      final byCode = itemFieldsByCode(
        _itemBody([
          {'name': '3000247', 'image': '/files/3000247-SGPU-14.jpg'},
          {'name': '2002849', 'image': null},
        ]),
      );
      expect(byCode.keys, ['3000247', '2002849']);
      expect(byCode['3000247']!['image'], '/files/3000247-SGPU-14.jpg');
    });

    test('an empty data list is a valid answer', () {
      expect(itemFieldsByCode(_itemBody([])), isEmpty);
    });

    test('a body without a data list is a FormatException', () {
      expect(
        () => itemFieldsByCode({'message': []}),
        throwsA(isA<FormatException>()),
      );
      expect(() => itemFieldsByCode('<html>'), throwsA(isA<FormatException>()));
      expect(() => itemFieldsByCode(null), throwsA(isA<FormatException>()));
    });
  });

  group('mergeRackContents', () {
    final rows = [_row('3000247', 36), _row('2002654', 0, name: '2002654')];
    final items = itemFieldsByCode(
      _itemBody([
        {
          'name': '3000247',
          'image': '/files/3000247-SGPU-14.jpg',
          'variant_of': 'SGPU-14',
          'country_of_origin': 'China',
          'brand': 'FOCUS',
          'description': '<div><p>BELTS LADIES PU</p></div>',
          'disabled': 0,
        },
        {
          'name': '2002654',
          'image': null,
          'variant_of': 'SGPU-52',
          'country_of_origin': 'China',
          'brand': null,
          'description': '2002654',
          'disabled': 1,
        },
      ]),
    );

    test('adds Item fields to each report row, in report order', () {
      final merged = mergeRackContents(rows, items);
      expect(merged.map((e) => e.itemCode), ['3000247', '2002654']);

      final a = merged.first;
      expect(a.balanceQty, 36);
      expect(a.stockUom, 'Nos');
      expect(a.itemGroup, 'Belts');
      expect(a.image, '/files/3000247-SGPU-14.jpg');
      expect(a.variantOf, 'SGPU-14');
      expect(a.countryOfOrigin, 'China');
      expect(a.brand, 'FOCUS');
      expect(a.disabled, isFalse);

      final b = merged.last;
      expect(b.image, isNull);
      expect(b.brand, isNull);
      expect(b.disabled, isTrue);
    });

    test('drops a description that only repeats the name or code', () {
      final merged = mergeRackContents(rows, items);
      expect(merged.first.description, isNull, reason: 'same as item name');
      expect(merged.last.description, isNull, reason: 'same as item code');
    });

    test('keeps a description that says more, as one line of plain text', () {
      final merged = mergeRackContents(
        [_row('3000253', 72)],
        {
          '3000253': {
            'name': '3000253',
            'description':
                '<p>BELTS LADIES PU-FOCUS</p><p>110-115CM &amp; 25mm</p>',
          },
        },
      );
      expect(
        merged.single.description,
        'BELTS LADIES PU-FOCUS 110-115CM & 25mm',
      );
    });

    test('a failed fetch (null) keeps the report data alone', () {
      final merged = mergeRackContents(rows, null);
      expect(merged, hasLength(2));
      expect(merged.first.itemName, 'BELTS LADIES PU');
      expect(merged.first.balanceQty, 36);
      expect(merged.first.image, isNull);
      expect(merged.first.countryOfOrigin, isNull);
      expect(merged.first.disabled, isFalse);
    });

    test('an item missing from the reply keeps its report data', () {
      final merged = mergeRackContents(rows, {'3000247': items['3000247']!});
      expect(merged.first.variantOf, 'SGPU-14');
      expect(merged.last.itemCode, '2002654');
      expect(merged.last.variantOf, isNull);
    });

    test('falls back to the row variant_of when Item has none', () {
      final row = {..._row('3000247', 36), 'variant_of': 'SGPU-14'};
      expect(mergeRackContents([row], null).single.variantOf, 'SGPU-14');
    });

    test(
      'a row without item_name shows the code and keeps unknown quantities',
      () {
        final merged = mergeRackContents([
          {'item_code': '3000247'},
          _row('zero', 0),
          {'item_code': 'blank', 'bal_qty': ''},
          {'item_code': 'invalid', 'bal_qty': 'invalid'},
          {'item_code': 'nonfinite', 'bal_qty': 'NaN'},
        ], null);
        expect(merged.first.itemName, '3000247');
        expect(merged.map((entry) => entry.balanceQty), [
          null,
          0,
          null,
          null,
          null,
        ]);
      },
    );
  });

  group('totals', () {
    final entries = mergeRackContents([
      _row('a', 36),
      _row('b', 0),
      _row('c', 12.5),
    ], null);

    test('rackQtyTotal sums Balance Qty', () {
      expect(rackQtyTotal(entries), 48.5);
      expect(rackQtyTotal(const []), 0);
    });

    test('sharedStockUom names the unit only when every row shares it', () {
      expect(sharedStockUom(entries), 'Nos');
      final mixed = mergeRackContents([
        _row('a', 1),
        {..._row('b', 1), 'stock_uom': 'Pair'},
      ], null);
      expect(sharedStockUom(mixed), isNull);
      expect(sharedStockUom(const []), isNull);
    });
  });

  group('filterRackContents', () {
    const belt = RackContentsEntry(
      itemCode: '3000247',
      itemName: 'BELTS LADIES PU',
      balanceQty: 36,
      variantOf: 'SGPU-14',
      brand: 'FOCUS',
      itemGroup: 'Belts',
      countryOfOrigin: 'China',
    );
    const wallet = RackContentsEntry(
      itemCode: '2002654',
      itemName: 'WALLET MENS',
      balanceQty: 4,
      brand: 'ARROW',
      batchNo: 'B-0091',
      description: 'Genuine leather bifold',
    );
    const all = [belt, wallet];

    test('a blank query keeps every entry', () {
      expect(filterRackContents(all, ''), all);
      expect(filterRackContents(all, '   '), all);
    });

    test(
      'matches code, name, variant, brand, batch and description, any case',
      () {
        expect(filterRackContents(all, '3000'), [belt]);
        expect(filterRackContents(all, 'wallet'), [wallet]);
        expect(filterRackContents(all, 'sgpu'), [belt]);
        expect(filterRackContents(all, 'Arrow'), [wallet]);
        expect(filterRackContents(all, 'b-0091'), [wallet]);
        expect(filterRackContents(all, 'LEATHER'), [wallet]);
        expect(filterRackContents(all, 'china'), [belt]);
      },
    );

    test('every word must match, in any order', () {
      expect(filterRackContents(all, 'focus belts'), [belt]);
      expect(filterRackContents(all, 'belts arrow'), isEmpty);
      expect(filterRackContents(all, 'nothing-like-this'), isEmpty);
    });
  });

  group('isSameDay', () {
    test('compares the calendar day only', () {
      expect(
        isSameDay(DateTime(2026, 11, 16, 23, 59), DateTime(2026, 11, 16, 0, 1)),
        isTrue,
      );
      expect(
        isSameDay(DateTime(2026, 11, 15), DateTime(2026, 11, 16)),
        isFalse,
      );
      expect(
        isSameDay(DateTime(2025, 11, 16), DateTime(2026, 11, 16)),
        isFalse,
      );
    });
  });

  group('itemImageUrl', () {
    test('joins a server-relative path to the base URL', () {
      expect(
        itemImageUrl('https://erp.domain.com', '/files/a.jpg'),
        'https://erp.domain.com/files/a.jpg',
      );
      expect(
        itemImageUrl('https://erp.domain.com/', '/files/a.jpg'),
        'https://erp.domain.com/files/a.jpg',
      );
      expect(
        itemImageUrl('https://erp.domain.com', 'files/a.jpg'),
        'https://erp.domain.com/files/a.jpg',
      );
    });

    test('keeps an absolute URL and returns null for no image', () {
      expect(
        itemImageUrl('https://erp.domain.com', 'https://cdn.example/a.jpg'),
        'https://cdn.example/a.jpg',
      );
      expect(itemImageUrl('https://erp.domain.com', null), isNull);
      expect(itemImageUrl('https://erp.domain.com', '  '), isNull);
    });
  });
}
