import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseHasDocPermissionResponse', () {
    // frappe.client.has_permission returns {"message": {"has_permission": 1}}.

    test('T-1: true when has_permission is int 1', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({
          'message': {'has_permission': 1},
        }),
        isTrue,
      );
    });

    test('T-2: true when has_permission is bool true', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({
          'message': {'has_permission': true},
        }),
        isTrue,
      );
    });

    test('T-3: false when has_permission is int 0', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({
          'message': {'has_permission': 0},
        }),
        isFalse,
      );
    });

    test('T-4: false when has_permission is bool false', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({
          'message': {'has_permission': false},
        }),
        isFalse,
      );
    });

    test('T-5: false when data is null', () {
      expect(ApiProvider.parseHasDocPermissionResponse(null), isFalse);
    });

    test('T-6: false when data is not a Map', () {
      expect(ApiProvider.parseHasDocPermissionResponse('OK'), isFalse);
    });

    test('T-7: false when message is absent', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({'other': 1}),
        isFalse,
      );
    });

    test('T-8: false when message is not a Map', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({'message': [1, 2]}),
        isFalse,
      );
    });

    test('T-9: false when has_permission key is absent', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({'message': {'x': 1}}),
        isFalse,
      );
    });
  });
}
