import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SaveIconButton success/error fade', () {
    testWidgets('wraps its display in an AnimatedSwitcher for a cross-fade',
        (tester) async {
      await tester.pumpWidget(_wrap(SaveIconButton(onPressed: () {})));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });

    testWidgets(
        'fades back to the save icon instead of an instant swap after success',
        (tester) async {
      SaveResult result = SaveResult.idle;
      late StateSetter setState;

      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setter) {
          setState = setter;
          return SaveIconButton(onPressed: () {}, saveResult: result);
        },
      )));

      setState(() => result = SaveResult.success);
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Advance past the 1.5s hold: the internal timer fires and flips the
      // displayed state back to idle. A frame shortly after should show
      // BOTH the outgoing check and the incoming save icon mid cross-fade —
      // an instant swap would never show both at once.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.save), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.save), findsOneWidget);
    });

    testWidgets(
        'fades back to the save icon instead of an instant swap after error',
        (tester) async {
      SaveResult result = SaveResult.idle;
      late StateSetter setState;

      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setter) {
          setState = setter;
          return SaveIconButton(onPressed: () {}, saveResult: result);
        },
      )));

      setState(() => result = SaveResult.error);
      await tester.pump();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.save), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byIcon(Icons.save), findsOneWidget);
    });
  });

  group('SaveIconButton.showFilledWhenDirty', () {
    testWidgets('shows plain IconButton when showFilledWhenDirty is false', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          isDirty: true,
          showFilledWhenDirty: false,
        ),
      ));
      // Plain IconButton — no filled style
      expect(find.byType(IconButton), findsOneWidget);
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      // style should be null (not a filled override)
      expect(btn.style, isNull);
    });

    testWidgets('shows filled IconButton when showFilledWhenDirty is true and dirty', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          isDirty: true,
          showFilledWhenDirty: true,
        ),
      ));
      // Widget renders without error
      expect(find.byType(IconButton), findsOneWidget);
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      // style is set (the filled override) with correct colours
      expect(btn.style?.backgroundColor?.resolve({}), const Color(0xFF25286F));
      expect(btn.style?.foregroundColor?.resolve({}), Colors.white);
    });

    testWidgets('shows plain IconButton when showFilledWhenDirty is true but not dirty', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          isDirty: false,
          showFilledWhenDirty: true,
        ),
      ));
      expect(find.byType(IconButton), findsOneWidget);
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.style, isNull);
    });

    testWidgets('no color: argument on plain IconButton (regression guard for 48e1596b)', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(onPressed: () {}, isDirty: true),
      ));
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      // The old bug: color: cs.onPrimary was set explicitly.
      // IconButton.color is the icon color override — must be null.
      expect(btn.color, isNull);
    });
  });

  group('SaveIconButton.onColor', () {
    const testColor = Color(0xFF112233);

    testWidgets('onColor + isSaving: spinner uses onColor', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          isSaving: true,
          onColor: testColor,
        ),
      ));
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.color, testColor);
    });

    testWidgets('onColor + filled dirty: uses onColor for bg (alpha 0.18) and fg', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          showFilledWhenDirty: true,
          isDirty: true,
          onColor: testColor,
        ),
      ));
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(
        btn.style?.backgroundColor?.resolve({}),
        testColor.withValues(alpha: 0.18),
      );
      expect(btn.style?.foregroundColor?.resolve({}), testColor);
    });

    testWidgets('default filled dirty without onColor still uses navy 0xFF25286F', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          showFilledWhenDirty: true,
          isDirty: true,
        ),
      ));
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.style?.backgroundColor?.resolve({}), const Color(0xFF25286F));
      expect(btn.style?.foregroundColor?.resolve({}), Colors.white);
    });
  });
}
