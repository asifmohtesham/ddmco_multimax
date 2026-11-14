import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// Minimal `frappe.desk.form.load.getdoctype` payload with the given fieldnames.
Map<String, dynamic> _meta(String doctype, List<String> fieldnames,
        {bool wrapInMessage = false}) {
  final body = {
    'docs': [
      {
        'doctype': 'DocType',
        'name': doctype,
        'fields': [
          for (final f in fieldnames) {'fieldname': f, 'fieldtype': 'Check'},
        ],
      },
      // A linked child doctype carrying `disabled` that must be ignored.
      {
        'doctype': 'DocType',
        'name': '$doctype Item',
        'fields': [
          {'fieldname': 'disabled', 'fieldtype': 'Check'},
        ],
      },
    ],
  };
  return wrapInMessage ? {'message': body} : body;
}

void main() {
  group('ApiProvider.activeFilterFromMeta', () {
    test('Item/Warehouse style meta → disabled = 0', () {
      expect(
        ApiProvider.activeFilterFromMeta(
            _meta('Warehouse', ['warehouse_name', 'disabled']), 'Warehouse'),
        {'disabled': 0},
      );
    });

    test('UOM style meta → enabled = 1', () {
      expect(
        ApiProvider.activeFilterFromMeta(
            _meta('UOM', ['uom_name', 'enabled', 'must_be_whole_number']),
            'UOM'),
        {'enabled': 1},
      );
    });

    test('disabled wins when a doctype has both flags', () {
      expect(
        ApiProvider.activeFilterFromMeta(
            _meta('Odd', ['enabled', 'disabled']), 'Odd'),
        {'disabled': 0},
      );
    });

    test('neither flag → no filter (Item Group, Warehouse Type)', () {
      expect(
        ApiProvider.activeFilterFromMeta(
            _meta('Item Group', ['item_group_name', 'is_group']),
            'Item Group'),
        isEmpty,
      );
    });

    test('only the target doctype meta is consulted, not linked docs', () {
      // The only `disabled` field lives on "Plain Item" (a linked doc).
      expect(
        ApiProvider.activeFilterFromMeta(_meta('Plain', ['title']), 'Plain'),
        isEmpty,
      );
    });

    test('tolerates the {message: {docs}} wrapper', () {
      expect(
        ApiProvider.activeFilterFromMeta(
            _meta('Item', ['disabled'], wrapInMessage: true), 'Item'),
        {'disabled': 0},
      );
    });

    test('unexpected shapes fail open to no filter', () {
      expect(ApiProvider.activeFilterFromMeta(null, 'Item'), isEmpty);
      expect(ApiProvider.activeFilterFromMeta('nope', 'Item'), isEmpty);
      expect(ApiProvider.activeFilterFromMeta({'docs': 'x'}, 'Item'), isEmpty);
    });
  });
}
