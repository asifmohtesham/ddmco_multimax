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

  group('rowMatchesAllTokens', () {
    const fields = ['name', 'item_name'];

    test('matches all tokens in any order, case-insensitive', () {
      final row = {'name': 'FG-1', 'item_name': 'Reversible Belts 30mm'};
      expect(
          GlobalSearchService.rowMatchesAllTokens(
              row, fields, ['belts', 'reversible']),
          isTrue);
      expect(
          GlobalSearchService.rowMatchesAllTokens(
              row, fields, ['REVERSIBLE', 'BELTS']),
          isTrue);
    });

    test('fails when a token is absent', () {
      final row = {'name': 'FG-1', 'item_name': 'Reversible Belts 30mm'};
      expect(
          GlobalSearchService.rowMatchesAllTokens(
              row, fields, ['belts', 'strap']),
          isFalse);
    });

    test('matches a token found in the code (name) field', () {
      final row = {'name': 'BELT-RED-01', 'item_name': 'Reversible'};
      expect(
          GlobalSearchService.rowMatchesAllTokens(
              row, fields, ['belt', 'reversible']),
          isTrue);
    });

    test('empty tokens -> true (no constraint)', () {
      expect(GlobalSearchService.rowMatchesAllTokens({'name': 'x'}, fields, []),
          isTrue);
    });

    test('missing field is treated as empty', () {
      final row = {'name': 'FG-1'}; // no item_name key
      expect(GlobalSearchService.rowMatchesAllTokens(row, fields, ['fg-1']),
          isTrue);
      expect(GlobalSearchService.rowMatchesAllTokens(row, fields, ['belts']),
          isFalse);
    });
  });
}
