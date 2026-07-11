import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

void main() {
  group('FormattingHelper.formatTime', () {
    test('trims server microseconds and zero-pads the hour', () {
      expect(FormattingHelper.formatTime('9:46:34.234513'), '09:46:34');
    });

    test('leaves an already-normalised HH:mm:ss value unchanged', () {
      expect(FormattingHelper.formatTime('14:05:09'), '14:05:09');
    });

    test('passes through null, empty, and non-time strings', () {
      expect(FormattingHelper.formatTime(null), isNull);
      expect(FormattingHelper.formatTime(''), '');
      expect(FormattingHelper.formatTime('not a time'), 'not a time');
    });
  });
}
