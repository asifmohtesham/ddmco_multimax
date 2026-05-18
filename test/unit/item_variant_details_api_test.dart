import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseItemVariantDetailsResponse', () {
    test('T-1: returns empty record when message is null', () {
      final result = ApiProvider.parseItemVariantDetailsResponse(null);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-2: returns empty record when message lacks columns/result keys', () {
      final result = ApiProvider.parseItemVariantDetailsResponse({'other': 'data'});
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-3: parses columns and rows from a well-formed message', () {
      final message = <String, dynamic>{
        'columns': [
          {'fieldname': 'item',   'label': 'Item'},
          {'fieldname': 'colour', 'label': 'Colour'},
          {'fieldname': 'size',   'label': 'Size'},
        ],
        'result': [
          {'item': 'BLUE-T-S', 'colour': 'Blue', 'size': 'S'},
          {'item': 'BLUE-T-M', 'colour': 'Blue', 'size': 'M'},
        ],
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.columns.length, 3);
      expect(result.rows.length, 2);
      expect(result.columns.first['fieldname'], 'item');
      expect(result.rows.first['item'], 'BLUE-T-S');
      expect(result.rows.last['size'], 'M');
    });

    test('T-4: ignores null and non-Map entries in the result list', () {
      final message = <String, dynamic>{
        'columns': [{'fieldname': 'item', 'label': 'Item'}],
        'result': [
          null,
          {'item': 'ITEM-001'},
          42,
          {'item': 'ITEM-002'},
        ],
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.rows.length, 2);
      expect(result.rows.map((r) => r['item']),
          containsAll(['ITEM-001', 'ITEM-002']));
    });

    test('T-5: returns empty record when columns or result are not Lists', () {
      final message = <String, dynamic>{
        'columns': 'not-a-list',
        'result':  'not-a-list',
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });
  });
}
