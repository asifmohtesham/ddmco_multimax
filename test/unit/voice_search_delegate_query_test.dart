import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';

void main() {
  group('GlobalDocumentSearchDelegate.voiceQueryUpdate', () {
    test('returns the trimmed transcript when non-empty', () {
      expect(GlobalDocumentSearchDelegate.voiceQueryUpdate('  blue strap '),
          'blue strap');
    });

    test('returns null for null', () {
      expect(GlobalDocumentSearchDelegate.voiceQueryUpdate(null), isNull);
    });

    test('returns null for empty / whitespace-only', () {
      expect(GlobalDocumentSearchDelegate.voiceQueryUpdate(''), isNull);
      expect(GlobalDocumentSearchDelegate.voiceQueryUpdate('   '), isNull);
    });
  });
}
