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

  group('resolveSearchTargets', () {
    // Item Price defines title_field "item_name" but NO search_fields, and is
    // autoname:hash. Before title_field was added to the search targets, its
    // only searchable field was the hash — every single-word query matched
    // nothing, while a two-word query worked (that path already used
    // title_field via resolvePrimarySearchField).
    test('a doctype with no search_fields still searches its title', () {
      expect(
        GlobalSearchService.resolveSearchTargets(
            {'title_field': 'item_name'}, {'item_name': 'Data'}),
        ['name', 'item_name'],
      );
    });

    test('title and search_fields combine without duplicating', () {
      expect(
        GlobalSearchService.resolveSearchTargets(
          {
            'title_field': 'customer_name',
            'search_fields': 'status,customer,customer_name',
          },
          {'customer_name': 'Data', 'status': 'Select', 'customer': 'Link'},
        ),
        ['name', 'customer_name', 'status', 'customer'],
      );
    });

    test('drops non-text fields, keeping name searchable', () {
      expect(
        GlobalSearchService.resolveSearchTargets(
            {'title_field': 'grand_total', 'search_fields': 'transaction_date'},
            {'grand_total': 'Currency', 'transaction_date': 'Date'}),
        ['name'],
      );
    });

    test('null meta and a blank title degrade to name only', () {
      expect(GlobalSearchService.resolveSearchTargets(null, {}), ['name']);
      expect(
          GlobalSearchService.resolveSearchTargets({'title_field': ''}, {}),
          ['name']);
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
