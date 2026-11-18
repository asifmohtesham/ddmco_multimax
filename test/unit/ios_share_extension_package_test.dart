import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS ShareExtension target links `receive_sharing_intent` through a
/// local Swift package reference. Flutter links each plugin's package under
/// `ios/Flutter/ephemeral/Packages/.packages/<name>-<version>`, so the path in
/// the Xcode project names the version and must follow every plugin upgrade,
/// or the extension stops building on the Mac (CI never builds iOS).
void main() {
  test('ShareExtension package path matches the resolved plugin version', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final version = RegExp(
      r'\n  receive_sharing_intent:\n(?:    .*\n)*?    version: "([^"]+)"',
    ).firstMatch(lock)?.group(1);
    expect(version, isNotNull, reason: 'receive_sharing_intent not in pubspec.lock');

    final pbxproj =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
      pbxproj,
      contains('Flutter/ephemeral/Packages/.packages/receive_sharing_intent-$version'),
      reason: 'Update the XCLocalSwiftPackageReference "receive_sharing_intent" '
          'relativePath in ios/Runner.xcodeproj/project.pbxproj to '
          'receive_sharing_intent-$version.',
    );
  });
}
