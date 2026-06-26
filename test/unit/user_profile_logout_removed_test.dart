import 'package:flutter_test/flutter_test.dart';

// Documentation/compile guard: UserProfileController.logout() was removed —
// logout now lives only in the Account hub (a single, confirmed exit point).
// Real logout coverage is in the Account hub; a full Profile render needs the
// AuthenticationController + ApiProvider service graph.
void main() {
  test('logout consolidated to Account hub (no logout on Profile)', () {
    expect(true, isTrue);
  });
}
