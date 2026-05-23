import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
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
      // style is set (the filled override)
      expect(btn.style, isNotNull);
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
}
