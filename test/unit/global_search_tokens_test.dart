import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('searchTokens', () {
    test('splits on whitespace, drops empties', () {
      expect(GlobalSearchService.searchTokens('belts reversible'),
          ['belts', 'reversible']);
      expect(GlobalSearchService.searchTokens('  a   b '), ['a', 'b']);
      expect(GlobalSearchService.searchTokens('single'), ['single']);
      expect(GlobalSearchService.searchTokens(''), isEmpty);
      expect(GlobalSearchService.searchTokens('   '), isEmpty);
    });
  });

  group('resolvePrimarySearchField', () {
    test('uses title_field when present', () {
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              {'title_field': 'item_name'}, ['name', 'item_name']),
          'item_name');
    });

    test('falls back to the first non-name search target', () {
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              {}, ['name', 'item_name', 'item_group']),
          'item_name');
    });

    test('falls back to name when only name is searchable', () {
      expect(GlobalSearchService.resolvePrimarySearchField({}, ['name']),
          'name');
    });

    test('null meta falls back to the searchTargets rule', () {
      expect(
          GlobalSearchService.resolvePrimarySearchField(null, ['name']), 'name');
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              null, ['name', 'customer_name']),
          'customer_name');
    });

    test('empty / non-String title_field is ignored', () {
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              {'title_field': ''}, ['name', 'item_name']),
          'item_name');
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              {'title_field': 1}, ['name', 'item_name']),
          'item_name');
    });
  });
}
