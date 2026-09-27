import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/auth/widgets/logout_dialog.dart';

/// The logout confirmation and its loading feedback are ONE dialog that
/// changes state. The previous flow stacked a second, Material-less route on
/// top of the confirm dialog: the two ghosted through each other and the
/// "Logging out…" label rendered in the yellow-underlined fallback style.
void main() {
  late RxBool busy;
  late RxnString error;
  late int confirms;

  setUp(() {
    busy = false.obs;
    error = RxnString();
    confirms = 0;
  });

  tearDown(() {
    busy.close();
    error.close();
  });

  /// Opens the dialog as a real route (not inside a Scaffold), so it only
  /// gets the ancestors it would get in the app.
  Future<void> openDialog(
    WidgetTester tester, {
    ThemeData? theme,
    String? email = 'picker@multimax.cloud',
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => LogoutDialog(
                busy: busy,
                error: error,
                email: email,
                onConfirm: () => confirms++,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> goBusy(WidgetTester tester) async {
    busy.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // settle cross-fade
  }

  /// Runs any route transition to completion. pumpAndSettle cannot be used
  /// while busy (the spinner never settles), and a single pump(duration) only
  /// STARTS an animation — so step frames explicitly.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('confirm state', () {
    testWidgets('names the account being signed out', (tester) async {
      await openDialog(tester);

      expect(find.textContaining('picker@multimax.cloud'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('confirming fires onConfirm and keeps the dialog open',
        (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Log out'));
      await tester.pump();

      expect(confirms, 1);
      expect(find.byType(LogoutDialog), findsOneWidget);
    });

    testWidgets('Cancel closes the dialog without logging out',
        (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(LogoutDialog), findsNothing);
      expect(confirms, 0);
    });

    testWidgets('tapping outside closes the dialog', (tester) async {
      await openDialog(tester);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byType(LogoutDialog), findsNothing);
    });
  });

  group('busy state', () {
    testWidgets('shows a spinner and a Logging out label', (tester) async {
      await openDialog(tester);
      await goBusy(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Logging out…'), findsOneWidget);
    });

    testWidgets('a second tap cannot start a second logout', (tester) async {
      await openDialog(tester);
      await goBusy(tester);

      await tester.tap(find.text('Logging out…'), warnIfMissed: false);
      await tester.pump();

      expect(confirms, 0);
    });

    testWidgets('Cancel is disabled', (tester) async {
      await openDialog(tester);
      await goBusy(tester);

      await tester.tap(find.text('Cancel'), warnIfMissed: false);
      await pumpFrames(tester);

      expect(find.byType(LogoutDialog), findsOneWidget);
    });

    testWidgets('tapping outside does not dismiss', (tester) async {
      await openDialog(tester);
      await goBusy(tester);

      await tester.tapAt(const Offset(5, 5));
      await pumpFrames(tester);

      expect(find.byType(LogoutDialog), findsOneWidget);
    });

    testWidgets('system back does not dismiss', (tester) async {
      await openDialog(tester);
      await goBusy(tester);

      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(find.byType(LogoutDialog), findsOneWidget);
    });

    testWidgets('no text falls back to the underlined no-Material style',
        (tester) async {
      await openDialog(tester);
      await goBusy(tester);

      final texts = tester.widgetList<RichText>(find.descendant(
        of: find.byType(LogoutDialog),
        matching: find.byType(RichText),
      ));
      expect(texts, isNotEmpty);
      for (final t in texts) {
        expect(t.text.style?.decoration, isNot(TextDecoration.underline),
            reason: t.text.toPlainText());
      }
    });

    for (final brightness in Brightness.values) {
      testWidgets('spinner stays visible on the red button (${brightness.name})',
          (tester) async {
        await openDialog(tester, theme: ThemeData(brightness: brightness));
        await goBusy(tester);

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final fill =
            button.style?.backgroundColor?.resolve({WidgetState.disabled});
        final spinner = tester.widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator));

        expect(fill, AppColors.red700);
        expect(spinner.color, Colors.white);
      });
    }
  });

  group('shown through Get.dialog (the production path)', () {
    testWidgets('cannot be dismissed while busy', (tester) async {
      await tester.pumpWidget(
          const GetMaterialApp(home: Scaffold(body: SizedBox.shrink())));
      Get.dialog(LogoutDialog(
        busy: busy,
        error: error,
        email: 'picker@multimax.cloud',
        onConfirm: () => confirms++,
      ));
      await tester.pumpAndSettle();
      await goBusy(tester);

      await tester.tapAt(const Offset(5, 5));
      await pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(find.byType(LogoutDialog), findsOneWidget);

      // Leave nothing animating for the next test.
      busy.value = false;
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(LogoutDialog), findsNothing);
    });
  });

  group('failure', () {
    testWidgets('shows the error and lets the user try again',
        (tester) async {
      await openDialog(tester);
      await goBusy(tester);

      error.value = 'Could not clear the saved session.';
      busy.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Could not clear the saved session.'), findsOneWidget);

      await tester.tap(find.text('Log out'));
      await tester.pump();
      expect(confirms, 1);
    });
  });
}
