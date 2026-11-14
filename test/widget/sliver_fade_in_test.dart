import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/sliver_fade_in.dart';

Widget _wrap(Widget sliver, {Key? key}) => MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [SliverFadeIn(key: key, sliver: sliver)],
        ),
      ),
    );

void main() {
  group('SliverFadeIn', () {
    testWidgets('starts at zero opacity and settles to full opacity',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const SliverToBoxAdapter(child: Text('Hello'))));

      final initial =
          tester.widget<SliverOpacity>(find.byType(SliverOpacity));
      expect(initial.opacity, 0.0);

      await tester.pumpAndSettle();

      final settled = tester.widget<SliverOpacity>(find.byType(SliverOpacity));
      expect(settled.opacity, 1.0);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('restarts the fade when remounted under a new key',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const SliverToBoxAdapter(child: Text('A')),
        key: const ValueKey('a'),
      ));
      await tester.pumpAndSettle();
      expect(
          tester.widget<SliverOpacity>(find.byType(SliverOpacity)).opacity,
          1.0);

      await tester.pumpWidget(_wrap(
        const SliverToBoxAdapter(child: Text('B')),
        key: const ValueKey('b'),
      ));

      expect(
          tester.widget<SliverOpacity>(find.byType(SliverOpacity)).opacity,
          0.0);
      expect(find.text('B'), findsOneWidget);
    });
  });
}
