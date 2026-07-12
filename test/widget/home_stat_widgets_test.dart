import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/home_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('PulseStat count-up animation', () {
    testWidgets('animates the actual count up and settles at the final value',
        (tester) async {
      await tester.pumpWidget(_wrap(PulseStat(
        title: 'Delivered',
        icon: Icons.local_shipping,
        actual: 42,
        target: 100,
        onTap: () {},
      )));

      // Immediately after the first frame the count-up animation is still
      // running toward 42 — an instant, unanimated render would already
      // show '42' here.
      await tester.pump();
      expect(find.text('42'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('BomCountCard count-up animation', () {
    testWidgets('animates count up and settles at the final value',
        (tester) async {
      await tester.pumpWidget(_wrap(BomCountCard(count: 7, onTap: () {})));

      await tester.pump();
      expect(find.text('7'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
    });
  });
}
