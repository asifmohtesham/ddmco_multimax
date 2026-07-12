import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ResultCountPill', () {
    testWidgets('singular noun when count == 1 and no more pages',
        (tester) async {
      await tester.pumpWidget(_wrap(const ResultCountPill(
        count: 1,
        hasMore: false,
        hasActiveFilters: false,
        noun: 'item',
        icon: Icons.inventory_2_outlined,
      )));
      expect(find.text('1 item'), findsOneWidget);
    });

    testWidgets('pluralises noun when count != 1', (tester) async {
      await tester.pumpWidget(_wrap(const ResultCountPill(
        count: 3,
        hasMore: false,
        hasActiveFilters: false,
        noun: 'note',
        icon: Icons.description_outlined,
      )));
      expect(find.text('3 notes'), findsOneWidget);
    });

    testWidgets('renders N+ form when hasMore', (tester) async {
      await tester.pumpWidget(_wrap(const ResultCountPill(
        count: 20,
        hasMore: true,
        hasActiveFilters: false,
        noun: 'order',
        icon: Icons.precision_manufacturing_outlined,
      )));
      expect(find.text('20+ orders'), findsOneWidget);
    });

    testWidgets('uses explicit pluralNoun for irregular nouns',
        (tester) async {
      await tester.pumpWidget(_wrap(const ResultCountPill(
        count: 4,
        hasMore: false,
        hasActiveFilters: false,
        noun: 'entry',
        pluralNoun: 'entries',
        icon: Icons.receipt_long_outlined,
      )));
      expect(find.text('4 entries'), findsOneWidget);

      await tester.pumpWidget(_wrap(const ResultCountPill(
        count: 1,
        hasMore: false,
        hasActiveFilters: false,
        noun: 'entry',
        pluralNoun: 'entries',
        icon: Icons.receipt_long_outlined,
      )));
      expect(find.text('1 entry'), findsOneWidget);
    });

    testWidgets('shows filter indicator only when filters active',
        (tester) async {
      await tester.pumpWidget(_wrap(const ResultCountPill(
        count: 5,
        hasMore: false,
        hasActiveFilters: false,
        noun: 'item',
        icon: Icons.inventory_2_outlined,
      )));
      expect(find.byIcon(Icons.filter_alt), findsNothing);

      await tester.pumpWidget(_wrap(const ResultCountPill(
        count: 5,
        hasMore: false,
        hasActiveFilters: true,
        noun: 'item',
        icon: Icons.inventory_2_outlined,
      )));
      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
    });

    testWidgets('animates via AnimatedSwitcher and settles to the new label when count changes',
        (tester) async {
      int count = 5;
      late StateSetter setState;

      await tester.pumpWidget(_wrap(StatefulBuilder(builder: (context, setter) {
        setState = setter;
        return ResultCountPill(
          count: count,
          hasMore: false,
          hasActiveFilters: false,
          noun: 'item',
          icon: Icons.inventory_2_outlined,
        );
      })));

      expect(find.text('5 items'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsOneWidget);

      setState(() => count = 6);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('6 items'), findsOneWidget);
      expect(find.text('5 items'), findsNothing);
    });
  });
}
