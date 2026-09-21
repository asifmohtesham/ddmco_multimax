import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/utils/fuzzy_match.dart';

/// Score parity with Frappe's `fuzzy_match.js`, computed by hand from the
/// constants: base 100 on a full match, −5 per leading letter (capped at
/// −15), −1 per unmatched letter, +15 first letter, +25 sequential,
/// +30 after a separator, +30 camel boundary.
void main() {
  group('fuzzyMatch', () {
    test('"dn" vs "Delivery Note": first letter + separator bonuses', () {
      // D@0 → +15 first letter; N@9 after ' ' → +30 separator.
      // 100 − 0 (leading) − 11 (unmatched) + 15 + 30 = 134.
      final r = fuzzyMatch('dn', 'Delivery Note');
      expect(r.matched, isTrue);
      expect(r.score, 134);
      expect(r.matches, [0, 9]);
    });

    test('is case-insensitive', () {
      expect(fuzzyMatch('DN', 'delivery note').score, 134);
      expect(fuzzyMatch('dn', 'DELIVERY NOTE').score, 134);
    });

    test('"it" vs "Item": first letter + sequential', () {
      // 100 − 0 − 2 + 15 + 25 = 138.
      final r = fuzzyMatch('it', 'Item');
      expect(r.score, 138);
      expect(r.matches, [0, 1]);
    });

    test('"note" vs "Delivery Note": leading-letter penalty caps at −15', () {
      // n@9: −45 capped to −15; unmatched 9; separator +30; three
      // sequential +75 → 100 − 15 − 9 + 30 + 75 = 181.
      final r = fuzzyMatch('note', 'Delivery Note');
      expect(r.matched, isTrue);
      expect(r.score, 181);
      expect(r.matches, [9, 10, 11, 12]);
    });

    test('camel-case boundary earns the camel bonus', () {
      // 'p' in "itemPrice": P@4, prev 'm' lower, 'P' upper → +30 camel;
      // 100 − 15 (capped leading) − 8 unmatched + 30 = 107.
      expect(fuzzyMatch('p', 'itemPrice').score, 107);
    });

    test('no match when a pattern letter is absent', () {
      final r = fuzzyMatch('xyz', 'Item');
      expect(r.matched, isFalse);
      expect(r.score, 0);
    });

    test('no match when the pattern is longer than the string', () {
      expect(fuzzyMatch('items', 'Item').matched, isFalse);
    });

    test('empty pattern or string never matches', () {
      expect(fuzzyMatch('', 'Item').matched, isFalse);
      expect(fuzzyMatch('a', '').matched, isFalse);
    });

    test('prefers the higher-scoring alternative alignment', () {
      // "se" in "Stock Entry": S@0,e@6 (separator) beats S@0,e? — only one
      // 'e' exists; but "st" has t@1 (sequential) vs t@8 (separator): the
      // sequential alignment scores 100 − 9 + 15 + 25 = 131 versus
      // 100 − 9 + 15 + 0 = 106, so the matcher must report [0, 1].
      final r = fuzzyMatch('st', 'Stock Entry');
      expect(r.matches, [0, 1]);
      expect(r.score, 131);
    });
  });

  group('fuzzySearch', () {
    test('returns score 0 and no indices when nothing matched', () {
      final r = fuzzySearch('zz', 'Item');
      expect(r.score, 0);
      expect(r.matches, isEmpty);
    });

    test('returns the match otherwise', () {
      expect(fuzzySearch('dn', 'Delivery Note').score, 134);
    });
  });
}
