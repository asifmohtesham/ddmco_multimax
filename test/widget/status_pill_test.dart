import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('wrapLabel opts compact pills into readable wrapping text', (
    tester,
  ) async {
    const status = 'On Hold (Payments) until 2027-01-01';
    await tester.pumpWidget(
      _wrap(
        const Center(
          child: SizedBox(
            width: 125,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(
                  key: ValueKey('default'),
                  status: status,
                  compact: true,
                ),
                StatusPill(
                  key: ValueKey('wrap'),
                  status: status,
                  compact: true,
                  wrapLabel: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final ordinary = find.descendant(
      of: find.byKey(const ValueKey('default')),
      matching: find.text(status),
    );
    final wrapping = find.descendant(
      of: find.byKey(const ValueKey('wrap')),
      matching: find.text(status),
    );
    expect(tester.widget<Text>(ordinary).style!.fontSize, 9);
    expect(tester.widget<Text>(ordinary).overflow, TextOverflow.ellipsis);
    expect(tester.widget<Text>(wrapping).style!.fontSize, 11);
    expect(
      tester.getSize(wrapping).height,
      greaterThan(tester.getSize(ordinary).height),
    );
  });

  group('StatusPill status-change animation', () {
    testWidgets('wraps its content in an AnimatedSwitcher for a cross-fade',
        (tester) async {
      await tester.pumpWidget(_wrap(const StatusPill(status: 'Draft')));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
    });

    testWidgets(
        'animates and settles to the new status text when status changes',
        (tester) async {
      String status = 'Draft';
      late StateSetter setState;

      await tester.pumpWidget(_wrap(StatefulBuilder(builder: (context, setter) {
        setState = setter;
        return StatusPill(status: status);
      })));

      expect(find.text('Draft'), findsOneWidget);

      setState(() => status = 'Completed');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Draft'), findsNothing);
    });
  });
}
