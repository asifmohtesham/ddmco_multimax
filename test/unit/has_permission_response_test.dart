import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseHasPermissionResponse', () {
    // The probe uses frappe.client.get_list which returns {"message": [...]}.
    // A List value for "message" (even empty) means the user has access.

    test('T-1: returns true when message is an empty list', () {
      expect(
        ApiProvider.parseHasPermissionResponse({'message': []}),
        isTrue,
      );
    });

    test('T-2: returns true when message is a list with items', () {
      expect(
        ApiProvider.parseHasPermissionResponse({
          'message': [
            {'name': 'BATCH-0001'},
          ],
        }),
        isTrue,
      );
    });

    test('T-3: returns false when data is null', () {
      expect(ApiProvider.parseHasPermissionResponse(null), isFalse);
    });

    test('T-4: returns false when data is not a Map', () {
      expect(ApiProvider.parseHasPermissionResponse('OK'), isFalse);
    });

    test('T-5: returns false when message key is absent', () {
      expect(
        ApiProvider.parseHasPermissionResponse({'other': 'data'}),
        isFalse,
      );
    });

    test('T-6: returns false when message is a Map, not a List', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': 1}}),
        isFalse,
      );
    });

    test('T-7: returns false when message is a String', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': 'Insufficient Permission'}),
        isFalse,
      );
    });

    test('T-8: returns false when message is null', () {
      expect(
        ApiProvider.parseHasPermissionResponse({'message': null}),
        isFalse,
      );
    });

    test('T-9: returns false when message is an int', () {
      expect(
        ApiProvider.parseHasPermissionResponse({'message': 0}),
        isFalse,
      );
    });
  });
}
