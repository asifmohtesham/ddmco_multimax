import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseHasPermissionResponse', () {
    test('T-1: returns true when has_permission is int 1', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': 1}}),
        isTrue,
      );
    });

    test('T-2: returns false when has_permission is int 0', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': 0}}),
        isFalse,
      );
    });

    test('T-3: returns true when has_permission is bool true', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': true}}),
        isTrue,
      );
    });

    test('T-4: returns false when has_permission is bool false', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': false}}),
        isFalse,
      );
    });

    test('T-5: returns false when data is null', () {
      expect(ApiProvider.parseHasPermissionResponse(null), isFalse);
    });

    test('T-6: returns false when data is not a Map', () {
      expect(ApiProvider.parseHasPermissionResponse('OK'), isFalse);
    });

    test('T-7: returns false when message key is absent', () {
      expect(
        ApiProvider.parseHasPermissionResponse({'other': 'data'}),
        isFalse,
      );
    });

    test('T-8: returns false when message is a String, not a Map', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': 'Insufficient Permission'}),
        isFalse,
      );
    });

    test('T-9: returns false when has_permission key is absent', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'other': 'data'}}),
        isFalse,
      );
    });
  });
}
