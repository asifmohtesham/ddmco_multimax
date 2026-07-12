import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/shake_on_trigger.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ShakeOnTrigger', () {
    testWidgets('renders the child untransformed when trigger is unchanged',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ShakeOnTrigger(trigger: 0, child: Text('Barcode')),
      ));
      expect(find.text('Barcode'), findsOneWidget);
      final transform = tester.widget<Transform>(
          find.byKey(const ValueKey('shakeOnTriggerTransform')));
      expect(transform.transform.getTranslation().x, 0.0);
    });

    testWidgets(
        'offsets the child horizontally mid-animation after the trigger '
        'changes, then settles back to zero', (tester) async {
      int trigger = 0;
      late StateSetter setState;

      await tester.pumpWidget(_wrap(StatefulBuilder(builder: (context, setter) {
        setState = setter;
        return ShakeOnTrigger(trigger: trigger, child: const Text('Barcode'));
      })));

      setState(() => trigger = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final midTransform = tester.widget<Transform>(
          find.byKey(const ValueKey('shakeOnTriggerTransform')));
      expect(midTransform.transform.getTranslation().x, isNot(0.0));

      await tester.pumpAndSettle();
      final settledTransform = tester.widget<Transform>(
          find.byKey(const ValueKey('shakeOnTriggerTransform')));
      expect(settledTransform.transform.getTranslation().x, 0.0);
    });

    testWidgets('does not shake when rebuilt with the same trigger value',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const ShakeOnTrigger(trigger: 2, child: Text('Barcode'))));
      await tester.pumpWidget(
          _wrap(const ShakeOnTrigger(trigger: 2, child: Text('Barcode'))));

      final transform = tester.widget<Transform>(
          find.byKey(const ValueKey('shakeOnTriggerTransform')));
      expect(transform.transform.getTranslation().x, 0.0);
    });
  });
}
