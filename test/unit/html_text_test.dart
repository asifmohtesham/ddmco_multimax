import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/core/utils/html_text.dart';

void main() {
  group('htmlToSingleLine', () {
    test('flattens the Desk ql-editor wrapper to its inner text', () {
      expect(
        htmlToSingleLine(
            '<div class="ql-editor read-mode"><p>Inventory: Price List</p></div>'),
        'Inventory: Price List',
      );
    });

    test('strips tags and joins block elements with spaces', () {
      expect(
        htmlToSingleLine(
            '<div class="ql-editor"><p>Pack <b>DN-101</b></p>\n<p>today</p></div>'),
        'Pack DN-101 today',
      );
    });

    test('decodes common entities and converts <br> to a space', () {
      expect(
        htmlToSingleLine('Check&nbsp;racks<br/>A &amp; B &lt;urgent&gt;'),
        'Check racks A & B <urgent>',
      );
    });

    test('passes plain text through untouched', () {
      expect(htmlToSingleLine('Call supplier'), 'Call supplier');
    });

    test('returns empty for empty input', () {
      expect(htmlToSingleLine(''), '');
    });
  });

  group('htmlToPlainText', () {
    test('converts the Desk sample to plain text', () {
      expect(
        htmlToPlainText(
            '<div class="ql-editor read-mode"><p>Inventory: Price List</p></div>'),
        'Inventory: Price List',
      );
    });

    test('keeps paragraph and <br> structure as newlines', () {
      expect(
        htmlToPlainText('<p>Line one</p><p>Line two<br>Line three</p>'),
        'Line one\nLine two\nLine three',
      );
    });

    test('collapses 3+ newlines to a single blank line', () {
      expect(htmlToPlainText('<p>a</p><br><br><br><p>b</p>'), 'a\n\nb');
    });

    test('decodes entities on multi-line output', () {
      expect(
        htmlToPlainText('Check&nbsp;racks<br/>A &amp; B'),
        'Check racks\nA & B',
      );
    });

    test('returns empty for empty input', () {
      expect(htmlToPlainText(''), '');
    });
  });
}
