import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
import 'package:multimax/main.dart' show buildAppTheme;

Widget _host(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
  theme: ThemeData(brightness: b),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('renders the count', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 3)));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('default variant uses red700 background', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 1)));
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('1'), matching: find.byType(Container)).first,
    );
    expect((box.decoration as BoxDecoration).color, AppColors.red700);
  });

  testWidgets('muted variant uses scheme.textSubtle background', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const CountBadge(count: 9, muted: true)));
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('9'), matching: find.byType(Container)).first,
    );
    expect((box.decoration as BoxDecoration).color, AppScheme.light.textSubtle);
  });

  testWidgets('muted variant uses scheme.text for text color', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 5, muted: true)));
    final text = tester.widget<Text>(find.text('5'));
    expect((text.style as TextStyle).color, AppScheme.light.text);
  });

  testWidgets('default variant uses white text color', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 7)));
    final text = tester.widget<Text>(find.text('7'));
    expect((text.style as TextStyle).color, Colors.white);
  });

  testWidgets('dark toolbar badge has a surface ring and stable numeral', (
    tester,
  ) async {
    final theme = buildAppTheme(AppScheme.dark, Brightness.dark);
    Future<void> pump(int count) => tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(child: CountBadge(count: count, toolbar: true)),
        ),
      ),
    );

    await pump(3);
    await pump(444);
    expect(find.text('3'), findsNothing);
    final text = tester.widget<Text>(find.text('444'));
    expect(text.style!.color, AppScheme.dark.bg);
    final badge = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(CountBadge),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = badge.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.red300);
    expect(decoration.border, Border.all(color: AppScheme.dark.fg));
    expect(find.byType(AnimatedSwitcher), findsNothing);
  });

  testWidgets(
    'animates via AnimatedSwitcher and settles to the new count when it changes',
    (tester) async {
      int count = 3;
      late StateSetter setState;

      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return CountBadge(count: count);
            },
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsOneWidget);

      setState(() => count = 4);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('4'), findsOneWidget);
      expect(find.text('3'), findsNothing);
    },
  );
}
