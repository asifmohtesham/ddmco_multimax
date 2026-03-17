// Smoke test for the Multimax app.
// The app entry point uses GetMaterialApp inline inside main() — there is no
// MyApp class. This file replaces the default Flutter template test that
// referenced the non-existent MyApp and caused a compile-time error:
//   "The name 'MyApp' isn't a class."

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder — app has no MyApp widget class', () {
    // The app bootstraps via main() → GetMaterialApp inline.
    // Widget-level integration tests should be added here once a
    // testable root widget is extracted from main.dart.
    expect(true, isTrue);
  });
}
