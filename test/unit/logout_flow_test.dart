import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/auth/logout_flow.dart';

/// Logout is local-first: the device session is always cleared, and the
/// server call is best-effort. A dead network must never keep a user signed
/// in on a shared handheld.
void main() {
  group('localFirstLogout', () {
    test('tells the server first, then clears the device', () async {
      final calls = <String>[];

      final outcome = await localFirstLogout(
        serverLogout: () async => calls.add('server'),
        clearLocal: () async => calls.add('local'),
      );

      expect(calls, ['server', 'local']);
      expect(outcome, LogoutOutcome.serverConfirmed);
    });

    test('still clears the device when the server call fails', () async {
      var cleared = false;

      final outcome = await localFirstLogout(
        serverLogout: () async => throw Exception('no route to host'),
        clearLocal: () async => cleared = true,
      );

      expect(cleared, isTrue);
      expect(outcome, LogoutOutcome.localOnly);
    });

    test('gives up on a hung server and clears the device', () async {
      final neverAnswers = Completer<void>();
      var cleared = false;
      var timeoutHookCalls = 0;

      final outcome = await localFirstLogout(
        serverLogout: () => neverAnswers.future,
        clearLocal: () async => cleared = true,
        serverTimeout: const Duration(milliseconds: 20),
        onServerTimeout: () => timeoutHookCalls++,
      );

      expect(cleared, isTrue);
      expect(outcome, LogoutOutcome.localOnly);
      expect(timeoutHookCalls, 1);
    });

    test('does not fire the timeout hook for an ordinary server error',
        () async {
      var timeoutHookCalls = 0;

      await localFirstLogout(
        serverLogout: () async => throw Exception('500'),
        clearLocal: () async {},
        onServerTimeout: () => timeoutHookCalls++,
      );

      expect(timeoutHookCalls, 0);
    });

    test('surfaces a failure to clear the device', () async {
      expect(
        localFirstLogout(
          serverLogout: () async {},
          clearLocal: () async => throw StateError('disk full'),
        ),
        throwsStateError,
      );
    });
  });
}
