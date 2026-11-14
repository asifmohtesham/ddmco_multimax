import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/voice_search_engine.dart';

void main() {
  group('resolveLocaleId', () {
    const available = ['en_US', 'en_GB', 'fr_FR', 'ur_PK'];

    test('picks the device locale when the recognizer supports it', () {
      expect(resolveLocaleId(available, 'fr_FR'), 'fr_FR');
    });

    test('normalizes separator/casing when matching the device locale', () {
      // Device tags often arrive hyphenated (en-GB) and differently cased.
      expect(resolveLocaleId(available, 'en-gb'), 'en_GB');
    });

    test('falls back to en_GB when the device locale is unsupported', () {
      expect(resolveLocaleId(available, 'de_DE'), 'en_GB');
    });

    test('falls back to en_US when en_GB is absent', () {
      expect(resolveLocaleId(const ['en_US', 'fr_FR'], 'de_DE'), 'en_US');
    });

    test('returns null (engine default) when no English is available', () {
      expect(resolveLocaleId(const ['fr_FR', 'ur_PK'], 'de_DE'), isNull);
    });

    test('returns null when the available list is empty', () {
      expect(resolveLocaleId(const [], 'en_GB'), isNull);
    });
  });
}
