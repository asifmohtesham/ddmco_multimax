import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_update_prompts.dart';
import 'package:multimax/main.dart' show buildAppTheme;

const _dialogBody = 'Multimax 2.58.10 is on the App Store. You have 2.58.9.';
const _restartMessage = 'Update downloaded — Restart to install';

Widget _app(
  AppUpdatePrompts prompts,
  Brightness brightness, {
  Widget body = const SizedBox.shrink(),
}) {
  return MaterialApp(
    scaffoldMessengerKey: prompts.messengerKey,
    navigatorObservers: [prompts.navigatorObserver],
    theme: buildAppTheme(AppScheme.of(brightness), brightness),
    home: Scaffold(body: Center(child: body)),
  );
}

Future<AppStorePromptResult> _showAppStore(
  AppUpdatePrompts prompts,
  Future<bool> Function() openStore,
) {
  return prompts.showAppStore(
    installedVersion: '2.58.9',
    storeVersion: '2.58.10',
    openStore: openStore,
  );
}

Color _materialColor(WidgetTester tester, Finder inside) {
  final material = find
      .descendant(of: inside, matching: find.byType(Material))
      .first;
  return tester.widget<Material>(material).color!;
}

Color _ink(WidgetTester tester, String text) {
  final richText = find.descendant(
    of: find.text(text),
    matching: find.byType(RichText),
  );
  return tester.widget<RichText>(richText).text.style!.color!;
}

double _contrast(Color foreground, Color background) {
  final fg = foreground.computeLuminance();
  final bg = background.computeLuminance();
  return fg > bg ? (fg + 0.05) / (bg + 0.05) : (bg + 0.05) / (fg + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('App Store dialog renders with readable text in $brightness', (
      tester,
    ) async {
      final prompts = AppUpdatePrompts();
      await tester.pumpWidget(_app(prompts, brightness));

      final result = _showAppStore(prompts, () async => true);
      await tester.pumpAndSettle();

      final surface = _materialColor(tester, find.byType(AlertDialog));
      for (final text in ['Update available', _dialogBody, 'Later']) {
        expect(
          _contrast(_ink(tester, text), surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      final button = find.ancestor(
        of: find.text('Update'),
        matching: find.byType(FilledButton),
      );
      expect(
        _contrast(_ink(tester, 'Update'), _materialColor(tester, button)),
        greaterThanOrEqualTo(4.5),
      );

      final later = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Later'),
      );
      later.onPressed!();
      later.onPressed!();
      await tester.pumpAndSettle();
      expect(await result, AppStorePromptResult.later);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('Play restart banner stays usable in $brightness', (
      tester,
    ) async {
      final prompts = AppUpdatePrompts();
      final restart = Completer<bool>();
      var restarts = 0;
      var scans = 0;
      await tester.pumpWidget(
        _app(
          prompts,
          brightness,
          body: TextButton(onPressed: () => scans++, child: const Text('Scan')),
        ),
      );

      prompts.showRestart(() {
        restarts++;
        return restart.future;
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 1));
      expect(find.text(_restartMessage), findsOneWidget);
      await tester.tap(find.text('Scan'));
      expect(scans, 1);

      final surface = _materialColor(tester, find.byType(MaterialBanner));
      for (final text in [_restartMessage, 'Dismiss']) {
        expect(
          _contrast(_ink(tester, text), surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      final button = find.ancestor(
        of: find.text('Restart'),
        matching: find.byType(FilledButton),
      );
      expect(
        _contrast(_ink(tester, 'Restart'), _materialColor(tester, button)),
        greaterThanOrEqualTo(4.5),
      );

      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(restarts, 1);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      final disabledFill = Color.alphaBlend(
        _materialColor(tester, button),
        surface,
      );
      expect(_contrast(spinner.color!, disabledFill), greaterThanOrEqualTo(3));

      restart.complete(false);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text(_restartMessage), findsNothing);

      prompts.showRestart(() async => true);
      await tester.pumpAndSettle();
      expect(find.text(_restartMessage), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(find.text(_restartMessage), findsNothing);
    });
  }

  testWidgets('dismissing the App Store dialog is equivalent to Later', (
    tester,
  ) async {
    final prompts = AppUpdatePrompts();
    await tester.pumpWidget(_app(prompts, Brightness.light));

    final result = _showAppStore(prompts, () async => true);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(await result, AppStorePromptResult.later);
  });

  testWidgets('App Store dialog defers while other modals are open', (
    tester,
  ) async {
    final prompts = AppUpdatePrompts();
    await tester.pumpWidget(_app(prompts, Brightness.light));
    final navigator = prompts.navigatorObserver.navigator!;

    unawaited(
      showModalBottomSheet<void>(
        context: navigator.context,
        builder: (_) => const Text('Another sheet'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Another sheet'), findsOneWidget);
    expect(
      await _showAppStore(prompts, () async => true),
      AppStorePromptResult.deferred,
    );
    navigator.pop();
    await tester.pumpAndSettle();

    unawaited(
      showCupertinoDialog<void>(
        context: navigator.context,
        builder: (_) =>
            const CupertinoAlertDialog(title: Text('Another dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Another dialog'), findsOneWidget);
    expect(
      await _showAppStore(prompts, () async => true),
      AppStorePromptResult.deferred,
    );
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('App Store launch shows progress and can be retried', (
    tester,
  ) async {
    final prompts = AppUpdatePrompts();
    final launch = Completer<bool>();
    var attempts = 0;
    await tester.pumpWidget(_app(prompts, Brightness.light));

    final result = _showAppStore(prompts, () {
      attempts++;
      return attempts == 1 ? launch.future : Future.value(true);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(attempts, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    launch.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(await result, AppStorePromptResult.update);
  });
}
