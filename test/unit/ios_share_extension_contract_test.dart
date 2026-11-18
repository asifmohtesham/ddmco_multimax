import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS ShareExtension is our own `ShareViewController`; it no longer links
/// `receive_sharing_intent`. It writes the plugin's `ShareKey` contract by hand
/// (see docs/ios_share_extension_setup.md), and the app half of the plugin
/// reads it, so the plugin stays pinned to the version whose contract the
/// extension follows. CI never builds iOS, so these checks guard the contract.
void main() {
  const swiftPath = 'ios/ShareExtension/ShareViewController.swift';

  test('pubspec pins receive_sharing_intent exactly', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^  receive_sharing_intent: 1\.9\.0$', multiLine: true)
          .hasMatch(pubspec),
      isTrue,
      reason: 'The share extension writes the ShareKey contract of '
          'receive_sharing_intent 1.9.0. Re-check that contract in '
          'ShareViewController.swift before changing the pin.',
    );
  });

  test("the share screen writes the plugin's keys", () {
    final swift = File(swiftPath).readAsStringSync();
    expect(swift, isNot(contains('import receive_sharing_intent')));
    expect(swift, contains('"ShareKey"'));
    expect(swift, contains('"MultimaxShareId"'));
    expect(swift, contains('"ShareMedia-'));
  });

  test('the share screen shows the agreed copy', () {
    final swift = File(swiftPath).readAsStringSync();
    for (final copy in [
      'to Multimax…',
      "Couldn't read these photos.",
      "Multimax couldn't get these photos in time. Try fewer, or download "
          'them first.',
      'Switch to Multimax to continue.',
    ]) {
      expect(swift, contains(copy));
    }
  });

  test('the extension no longer links the plugin package', () {
    final pbxproj =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbxproj, isNot(contains('receive_sharing_intent-1.9.0')));
    expect(pbxproj, isNot(contains('receive-sharing-intent')));
    expect(
      pbxproj,
      isNot(contains('XCLocalSwiftPackageReference "receive_sharing_intent"')),
    );
    // The Runner still gets the plugin through Flutter's generated package.
    expect(pbxproj, contains('FlutterGeneratedPluginSwiftPackage'));
  });
}
