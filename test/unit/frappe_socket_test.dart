import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cookie header formatting', () {
    test('joins multiple cookies with semicolons', () {
      final cookies = [
        {'name': 'sid', 'value': 'abc123'},
        {'name': 'system_user', 'value': 'yes'},
      ];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, 'sid=abc123; system_user=yes');
    });

    test('single cookie has no trailing semicolon', () {
      final cookies = [
        {'name': 'sid', 'value': 'xyz'},
      ];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, 'sid=xyz');
    });

    test('empty cookie list produces empty string', () {
      final cookies = <Map<String, String>>[];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, '');
    });
  });
}
