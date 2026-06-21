import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';

Widget _host(Widget child, {Brightness b = Brightness.light}) =>
    MaterialApp(theme: ThemeData(brightness: b), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('renders the count', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 3)));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('default variant uses red500 background', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 1)));
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('1'), matching: find.byType(Container)).first);
    expect((box.decoration as BoxDecoration).color, AppColors.red500);
  });

  testWidgets('muted variant uses scheme.textSubtle background', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 9, muted: true)));
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('9'), matching: find.byType(Container)).first);
    expect((box.decoration as BoxDecoration).color, AppScheme.light.textSubtle);
  });
}
