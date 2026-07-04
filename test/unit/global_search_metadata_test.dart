import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('extractDocTypeMeta', () {
    final itemDoc = {
      'doctype': 'DocType',
      'name': 'Item',
      'search_fields': 'item_name,item_group',
      'title_field': 'item_name',
      'fields': [
        {'fieldname': 'item_name', 'fieldtype': 'Data'},
      ],
    };

    test('finds the target doc in {docs: [...]}', () {
      final data = {
        'docs': [
          {'doctype': 'DocType', 'name': 'UOM'}, // a parent/other doc
          itemDoc,
        ],
      };
      final meta = GlobalSearchService.extractDocTypeMeta(data, 'Item');
      expect(meta, isNotNull);
      expect(meta!['search_fields'], 'item_name,item_group');
      expect(meta['title_field'], 'item_name');
      expect(meta['fields'], isA<List>());
    });

    test('tolerates the {message: {docs: [...]}} wrapper', () {
      final data = {
        'message': {'docs': [itemDoc]},
      };
      final meta = GlobalSearchService.extractDocTypeMeta(data, 'Item');
      expect(meta?['title_field'], 'item_name');
    });

    test('returns null when the target doc is absent', () {
      final data = {
        'docs': [
          {'doctype': 'DocType', 'name': 'UOM'},
        ],
      };
      expect(GlobalSearchService.extractDocTypeMeta(data, 'Item'), isNull);
    });

    test('returns null on non-Map data or a missing/!List docs', () {
      expect(GlobalSearchService.extractDocTypeMeta('nope', 'Item'), isNull);
      expect(GlobalSearchService.extractDocTypeMeta({'foo': 'bar'}, 'Item'),
          isNull);
      expect(
          GlobalSearchService.extractDocTypeMeta({'docs': 'notalist'}, 'Item'),
          isNull);
    });
  });
}
