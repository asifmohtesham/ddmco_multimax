// test/unit/pos_dn_grouping_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';

const _rows = <Map<String, dynamic>>[
  {'item_group': 'Straps', 'customer': 'MBT', 'upload_item': 'STRAP TX',
   'upload_rate': 10, 'upload_qty': 5, 'dn_qty': 4},
  {'item_group': 'Straps', 'customer': 'ACE', 'upload_item': 'STRAP TX',
   'upload_rate': 100, 'upload_qty': 2, 'dn_qty': 2},
  {'item_group': 'Buckles', 'customer': 'MBT', 'upload_item': 'BUCKLE',
   'upload_rate': 2, 'upload_qty': 3, 'dn_qty': 0},
  {'item_group': '', 'customer': null, 'upload_item': 'X',
   'upload_rate': null, 'upload_qty': 1, 'dn_qty': 1},
];

void main() {
  group('PosDnGroupField.valueOf', () {
    test('text fields; blank/missing -> dash', () {
      expect(PosDnGroupField.itemGroup.valueOf(_rows[0]), 'Straps');
      expect(PosDnGroupField.itemGroup.valueOf(_rows[3]), '—');
      expect(PosDnGroupField.customer.valueOf(_rows[3]), '—');
    });
    test('rate formats numerically; missing -> dash', () {
      expect(PosDnGroupField.rate.valueOf(_rows[0]), '10');
      expect(PosDnGroupField.rate.valueOf(_rows[3]), '—');
      expect(PosDnGroupField.rate.numeric, isTrue);
    });
  });

  group('groupRows single level', () {
    test('buckets, counts, qty totals; blanks last', () {
      final g = groupRows(_rows, PosDnGroupField.itemGroup);
      expect(g.map((n) => n.key), ['Buckles', 'Straps', '—']);
      final straps = g.firstWhere((n) => n.key == 'Straps');
      expect(straps.count, 2);
      expect(straps.posQty, 7);
      expect(straps.dnQty, 6);
      expect(straps.children, isEmpty);
      expect(straps.rows.length, 2);
    });

    test('rate groups sort numerically not lexically', () {
      final g = groupRows(_rows, PosDnGroupField.rate);
      expect(g.map((n) => n.key), ['2', '10', '100', '—']);
    });
  });

  group('groupRows two levels', () {
    test('nests, aggregates parent recursively', () {
      final g = groupRows(_rows, PosDnGroupField.itemGroup,
          secondary: PosDnGroupField.customer);
      final straps = g.firstWhere((n) => n.key == 'Straps');
      expect(straps.rows, isEmpty);
      expect(straps.children.map((c) => c.key), ['ACE', 'MBT']);
      expect(straps.count, 2);           // sum of children counts
      expect(straps.posQty, 7);          // 2 + 5
      final mbt = straps.children.firstWhere((c) => c.key == 'MBT');
      expect(mbt.count, 1);
      expect(mbt.posQty, 5);
    });
  });

  group('sanitizeSecondary', () {
    test('drops secondary when equal to primary', () {
      expect(sanitizeSecondary(PosDnGroupField.customer, PosDnGroupField.customer),
          isNull);
      expect(sanitizeSecondary(PosDnGroupField.customer, PosDnGroupField.rate),
          PosDnGroupField.rate);
    });
  });

  group('flattenForDisplay', () {
    test('single level: header then its rows; collapse hides rows', () {
      final tree = groupRows(_rows, PosDnGroupField.itemGroup);
      final open = flattenForDisplay(tree, <String>{});
      // Buckles(header,1 row), Straps(header,2 rows), —(header,1 row)
      expect(open.where((d) => d.kind == DisplayKind.primaryHeader).length, 3);
      expect(open.where((d) => d.kind == DisplayKind.row).length, 4);

      final collapsed = flattenForDisplay(
          tree, {primaryCollapseKey('Straps')});
      expect(collapsed.where((d) => d.kind == DisplayKind.row).length, 2);
    });

    test('two levels: primary header, secondary headers, rows; nesting order',
        () {
      final tree = groupRows(_rows, PosDnGroupField.itemGroup,
          secondary: PosDnGroupField.customer);
      final items = flattenForDisplay(tree, <String>{});
      final straps = items.indexWhere((d) =>
          d.kind == DisplayKind.primaryHeader && d.node!.key == 'Straps');
      expect(items[straps + 1].kind, DisplayKind.secondaryHeader); // ACE
      expect(items[straps + 2].kind, DisplayKind.row);

      // Collapsing the Straps primary hides its secondary headers too.
      final c = flattenForDisplay(tree, {primaryCollapseKey('Straps')});
      expect(
        c.any((d) =>
            d.kind == DisplayKind.secondaryHeader && d.node!.key == 'ACE'),
        isFalse,
      );
    });

    test('collapseKeysFor returns all header keys', () {
      final tree = groupRows(_rows, PosDnGroupField.itemGroup,
          secondary: PosDnGroupField.customer);
      final keys = collapseKeysFor(tree);
      expect(keys.contains(primaryCollapseKey('Straps')), isTrue);
      expect(keys.contains(secondaryCollapseKey('Straps', 'ACE')), isTrue);
    });
  });
}
