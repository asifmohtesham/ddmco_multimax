import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/awesome_bar_service.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('AwesomeBarService.makeDescription', () {
    test('keeps only the fields whose value contains the keyword', () {
      const content =
          'Customer : Acme Ltd ||| Remarks : urgent delivery ||| Item Code : FG-1';
      expect(AwesomeBarService.makeDescription(content, 'acme', 'DN-1'),
          'Customer: Acme Ltd');
      expect(AwesomeBarService.makeDescription(content, 'FG', 'DN-1'),
          'Item Code: FG-1');
    });

    test('joins several matching fields with ", "', () {
      const content = 'Customer : Acme ||| Remarks : acme again';
      expect(AwesomeBarService.makeDescription(content, 'acme', 'DN-1'),
          'Customer: Acme, Remarks: acme again');
    });

    test('understands the " &&& " separator', () {
      expect(
          AwesomeBarService.makeDescription(
              'Notes &&& acme is here', 'acme', 'DN-1'),
          'Notes: acme is here');
    });

    test('never repeats the document name as a field', () {
      expect(AwesomeBarService.makeDescription('Name : DN-1', 'dn-1', 'DN-1'),
          '');
    });

    test('trims a long value to 120 chars around the first match', () {
      final value = '${'a' * 150}acme${'b' * 150}';
      final out = AwesomeBarService.makeDescription(
          'Remarks : $value', 'acme', 'DN-1');
      expect(out, startsWith('Remarks: ...'));
      expect(out, endsWith('...'));
      expect(out, contains('acme'));
      expect(out.length, lessThan(140));
    });

    test('caps the whole description at 300 chars with an ellipsis', () {
      final fields = [
        for (var i = 0; i < 10; i++) 'Field $i : ${'x' * 40} acme ${'y' * 20}',
      ];
      final out = AwesomeBarService.makeDescription(
          fields.join(' ||| '), 'acme', 'DN-1');
      expect(out.length, lessThanOrEqualTo(320));
      expect(out, endsWith('...'));
      expect(out.split(', ').length, lessThan(10));
    });

    test('empty content yields an empty description', () {
      expect(AwesomeBarService.makeDescription('', 'acme', 'DN-1'), '');
    });
  });

  group('GlobalSearchService.parseGlobalSearchResponse', () {
    test('reads {message: [...]}', () {
      final hits = GlobalSearchService.parseGlobalSearchResponse({
        'message': [
          {
            'doctype': 'Delivery Note',
            'name': 'KA-DN-1',
            'content': 'Customer : Acme',
            'rank': 1.5,
            'image': null,
          },
          {'doctype': '', 'name': 'x'},
          'garbage',
        ]
      });
      expect(hits.length, 1);
      expect(hits.single.doctype, 'Delivery Note');
      expect(hits.single.name, 'KA-DN-1');
      expect(hits.single.content, 'Customer : Acme');
      expect(hits.single.rank, 1.5);
      expect(hits.single.image, isNull);
    });

    test('reads a bare list and tolerates junk', () {
      expect(
          GlobalSearchService.parseGlobalSearchResponse([
            {'doctype': 'Item', 'name': 'FG-1'}
          ]).single.name,
          'FG-1');
      expect(GlobalSearchService.parseGlobalSearchResponse(null), isEmpty);
      expect(GlobalSearchService.parseGlobalSearchResponse({'message': 'x'}),
          isEmpty);
    });
  });
}
