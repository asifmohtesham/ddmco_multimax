import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/modules/user_area/user_area_screen.dart';

User _mgr() =>
    User(id: 'a', name: 'A', email: 'a', roles: const ['Stock Manager']);
User _op() =>
    User(id: 'b', name: 'B', email: 'b', roles: const ['Stock User']);
User _noRoles() => User(id: 'c', name: 'C', email: 'c', roles: const []);

void main() {
  group('showNotificationsEntry', () {
    test('manager + android -> true', () {
      expect(
        showNotificationsEntry(
          user: _mgr(),
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isTrue,
      );
    });

    test('manager + iOS -> true', () {
      expect(
        showNotificationsEntry(
          user: _mgr(),
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        isTrue,
      );
    });

    test('non-manager + android -> false', () {
      expect(
        showNotificationsEntry(
          user: _op(),
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isFalse,
      );
    });

    test('empty-roles + android -> false', () {
      expect(
        showNotificationsEntry(
          user: _noRoles(),
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isFalse,
      );
    });

    test('manager but isWeb=true -> false', () {
      expect(
        showNotificationsEntry(
          user: _mgr(),
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        isFalse,
      );
    });

    test('manager + desktop (windows) -> false', () {
      expect(
        showNotificationsEntry(
          user: _mgr(),
          platform: TargetPlatform.windows,
          isWeb: false,
        ),
        isFalse,
      );
    });

    test('user == null -> false', () {
      expect(
        showNotificationsEntry(
          user: null,
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isFalse,
      );
    });
  });
}
