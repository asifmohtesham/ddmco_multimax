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
  });
}
