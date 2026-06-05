import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/auth/connect/connect_to_instance_controller.dart';

void main() {
  group('ConnectToInstanceController.normaliseUrl', () {
    test('adds https:// when scheme is missing', () {
      expect(
        ConnectToInstanceController.normaliseUrl('erp.example.com'),
        'https://erp.example.com',
      );
    });

    test('strips trailing slash', () {
      expect(
        ConnectToInstanceController.normaliseUrl('https://erp.example.com/'),
        'https://erp.example.com',
      );
    });

    test('leaves existing https:// scheme unchanged', () {
      expect(
        ConnectToInstanceController.normaliseUrl('https://erp.example.com'),
        'https://erp.example.com',
      );
    });

    test('leaves existing http:// scheme unchanged', () {
      expect(
        ConnectToInstanceController.normaliseUrl('http://erp.example.com'),
        'http://erp.example.com',
      );
    });

    test('trims whitespace', () {
      expect(
        ConnectToInstanceController.normaliseUrl('  https://erp.example.com  '),
        'https://erp.example.com',
      );
    });

    test('strips multiple trailing slashes', () {
      expect(
        ConnectToInstanceController.normaliseUrl('https://erp.example.com//'),
        'https://erp.example.com',
      );
    });

    test('returns empty string for empty input', () {
      expect(
        ConnectToInstanceController.normaliseUrl(''),
        '',
      );
    });

    test('prefixes https:// when string starts with http but has no scheme separator', () {
      expect(
        ConnectToInstanceController.normaliseUrl('httpfoo.bar'),
        'https://httpfoo.bar',
      );
    });
  });

  group('ConnectToInstanceController.looksLikeUrl', () {
    test('returns true for https URL', () {
      expect(ConnectToInstanceController.looksLikeUrl('https://erp.example.com'), isTrue);
    });

    test('returns true for domain without scheme', () {
      expect(ConnectToInstanceController.looksLikeUrl('erp.example.com'), isTrue);
    });

    test('returns false for EAN-8 digit string', () {
      expect(ConnectToInstanceController.looksLikeUrl('12345678'), isFalse);
    });

    test('returns false for rack code', () {
      expect(ConnectToInstanceController.looksLikeUrl('A-01-02-03'), isFalse);
    });

    test('returns false for empty string', () {
      expect(ConnectToInstanceController.looksLikeUrl(''), isFalse);
    });

    test('returns true for http-prefixed non-URL (passes startsWith guard)', () {
      // Documents known behaviour: looksLikeUrl only filters obvious non-URLs;
      // normaliseUrl is responsible for producing a valid scheme.
      expect(ConnectToInstanceController.looksLikeUrl('httpfoo'), isTrue);
    });
  });
}
