import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
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
