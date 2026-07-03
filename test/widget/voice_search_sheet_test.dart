import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/voice_search_engine.dart';
import 'package:multimax/app/modules/global_widgets/voice_search_sheet.dart';

/// Test double: records callbacks so the test can drive engine events, and
/// exposes them for assertions on stop/cancel.
class FakeVoiceSearchEngine implements VoiceSearchEngine {
  void Function(String text, bool isFinal)? onResult;
  void Function(VoiceEngineState state)? onState;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(VoiceEngineState state) onState,
  }) async {
    startCalls++;
    this.onResult = onResult;
    this.onState = onState;
    onState(VoiceEngineState.listening);
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> cancel() async => cancelCalls++;
}

/// Captures the outcome of `VoiceSearchSheet.show`. [completed] flips true only
/// once the future resolves, so a returned `null` is provably distinct from
/// "not yet returned" (both would otherwise read as `value == null`).
class _ShowResult {
  bool completed = false;
  String? value;
}

/// Pumps a host screen with a button that opens [VoiceSearchSheet.show], taps
/// it, and settles so the sheet is open and [fake]'s callbacks are wired.
/// The eventual return value of `show` is recorded into [result].
Future<void> _openSheet(
  WidgetTester tester,
  FakeVoiceSearchEngine fake,
  _ShowResult result,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await VoiceSearchSheet.show(context, engine: fake);
              result
                ..completed = true
                ..value = r;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the live partial transcript while listening',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    final result = _ShowResult();
    await _openSheet(tester, fake, result);

    fake.onResult!('blue str', false);
    await tester.pump();

    expect(find.text('blue str'), findsOneWidget);
  });

  testWidgets('a final result pops the sheet with the transcript',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    final result = _ShowResult();
    await _openSheet(tester, fake, result);

    fake.onResult!('blue strap', true);
    await tester.pumpAndSettle();

    expect(result.completed, isTrue);
    expect(result.value, 'blue strap');
  });

  testWidgets('a final result is trimmed before popping', (tester) async {
    final fake = FakeVoiceSearchEngine();
    final result = _ShowResult();
    await _openSheet(tester, fake, result);

    fake.onResult!('  blue strap  ', true);
    await tester.pumpAndSettle();

    expect(result.completed, isTrue);
    expect(result.value, 'blue strap');
  });

  testWidgets('an empty / whitespace-only final result pops with null',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    final result = _ShowResult();
    await _openSheet(tester, fake, result);

    fake.onResult!('   ', true);
    await tester.pumpAndSettle();

    // completed distinguishes "popped with null" from "never returned".
    expect(result.completed, isTrue);
    expect(result.value, isNull);
  });

  testWidgets('permission-denied state shows a message and does not crash',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    final result = _ShowResult();
    await _openSheet(tester, fake, result);

    fake.onState!(VoiceEngineState.permissionDenied);
    await tester.pump();

    expect(find.textContaining('permission'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The brief for this task calls out that an engine may emit a terminal
    // state twice; the sheet must not crash or double-pop on the repeat.
    fake.onState!(VoiceEngineState.permissionDenied);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('notAvailable state shows the unavailable message',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    final result = _ShowResult();
    await _openSheet(tester, fake, result);

    fake.onState!(VoiceEngineState.notAvailable);
    await tester.pump();

    expect(find.textContaining("isn't available"), findsOneWidget);
    // No recognizer → no point retrying; only Close is offered.
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('error state offers Retry which restarts listening',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    final result = _ShowResult();
    await _openSheet(tester, fake, result);
    expect(fake.startCalls, 1); // started once on open

    fake.onState!(VoiceEngineState.error);
    await tester.pump();

    // Error UI is reachable and offers a Retry.
    expect(find.textContaining('Retry'), findsWidgets);
    final retry = find.widgetWithText(FilledButton, 'Retry');
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();

    // Back to the listening UI (the Done/stop control) and re-started.
    expect(find.text('Done'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
    expect(fake.startCalls, 2); // once on open, once on retry
    expect(result.completed, isFalse); // sheet stayed open
  });
}
