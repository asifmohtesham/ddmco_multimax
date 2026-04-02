// Regression test for the triple assertion crash:
//
//   1. "TextEditingController used after being disposed"
//      (_AnimatedState.didUpdateWidget / initState)
//   2. "dependents.isEmpty is not true"
//      (Overlay InheritedElement deactivated with live dependents)
//   3. "attached is not true" x5
//      (RenderEditable caret callbacks after RenderObject detach)
//
// Root cause: QuantityInputWidget used UniqueKey() as instance fields,
// generating new keys on every parent rebuild. Fixed by:
//   C-1 — ValueKey derived from widgetTag/label (stable across rebuilds)
//   C-2 — boxShadow removed (severed _AnimatedState listener path)
//   C-4 — widgetTag: itemCode passed from GlobalItemFormSheet
//
// This test reproduces the crash scenario: a QuantityInputWidget is
// rendered with an active TextEditingController, its parent rebuilds
// (simulating a GetX reactive list mutation from addItemLocally), and
// the controller must still be alive and readable after the rebuild.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';

void main() {
  group('QuantityInputWidget — controller lifecycle', () {
    // -------------------------------------------------------------------------
    // Helper: wraps QuantityInputWidget in a minimal testable scaffold.
    // [rebuildTrigger] is a ValueNotifier<int>; incrementing it forces the
    // parent StatefulWidget to call setState, simulating a GetX Obx rebuild.
    // -------------------------------------------------------------------------
    Widget buildHarness({
      required TextEditingController ctrl,
      required ValueNotifier<int> rebuildTrigger,
      String itemCode = 'ITEM-001',
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: rebuildTrigger,
            builder: (_, __, ___) => QuantityInputWidget(
              controller: ctrl,
              onIncrement: () {},
              onDecrement: () {},
              widgetTag: itemCode,
              label: 'Quantity',
            ),
          ),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // T-1: Controller survives a single parent rebuild.
    //
    // Sequence mirrors the crash path:
    //   build → user types qty → parent rebuilds (addItem) → read ctrl.text
    // -------------------------------------------------------------------------
    testWidgets(
      'T-1: controller.text is readable after parent rebuild (no assertion)',
      (WidgetTester tester) async {
        final ctrl = TextEditingController(text: '1');
        final trigger = ValueNotifier<int>(0);
        addTearDown(ctrl.dispose);
        addTearDown(trigger.dispose);

        await tester.pumpWidget(buildHarness(ctrl: ctrl, rebuildTrigger: trigger));

        // Verify initial render.
        expect(find.byType(QuantityInputWidget), findsOneWidget);
        expect(ctrl.text, '1');

        // Simulate addItemLocally() triggering a parent rebuild.
        trigger.value++;
        await tester.pump();

        // Controller must still be alive — this line threw before the fix.
        expect(ctrl.text, '1',
            reason: 'TextEditingController must survive parent rebuild');
      },
    );

    // -------------------------------------------------------------------------
    // T-2: Controller survives five rapid successive rebuilds.
    //
    // Covers the case where the user scans multiple items quickly,
    // each scan triggering addItemLocally() and a reactive rebuild.
    // -------------------------------------------------------------------------
    testWidgets(
      'T-2: controller survives 5 rapid successive parent rebuilds',
      (WidgetTester tester) async {
        final ctrl = TextEditingController(text: '3');
        final trigger = ValueNotifier<int>(0);
        addTearDown(ctrl.dispose);
        addTearDown(trigger.dispose);

        await tester.pumpWidget(buildHarness(ctrl: ctrl, rebuildTrigger: trigger));

        for (int i = 1; i <= 5; i++) {
          trigger.value = i;
          await tester.pump();
        }

        // All five rebuilds must complete without assertion errors.
        expect(ctrl.text, '3');
        expect(find.byType(TextFormField), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // T-3: widgetTag change produces new stable ValueKeys without crash.
    //
    // Simulates the sheet being reused for a different item (e.g. editing
    // an existing item after adding a new one). The widgetTag changes but
    // the same controller instance is passed — no disposal must occur.
    // -------------------------------------------------------------------------
    testWidgets(
      'T-3: changing widgetTag re-keys buttons without disposing controller',
      (WidgetTester tester) async {
        final ctrl = TextEditingController(text: '2');
        final tagNotifier = ValueNotifier<String>('ITEM-001');
        addTearDown(ctrl.dispose);
        addTearDown(tagNotifier.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<String>(
                valueListenable: tagNotifier,
                builder: (_, tag, ___) => QuantityInputWidget(
                  controller: ctrl,
                  onIncrement: () {},
                  onDecrement: () {},
                  widgetTag: tag,
                  label: 'Quantity',
                ),
              ),
            ),
          ),
        );

        expect(ctrl.text, '2');

        // Switch to a different item — simulates editItem() on a second item.
        tagNotifier.value = 'ITEM-002';
        await tester.pump();

        // Controller must not be disposed; text must still be readable.
        expect(ctrl.text, '2',
            reason: 'Changing widgetTag must not dispose the controller');
        expect(find.byType(QuantityInputWidget), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // T-4: No boxShadow means no AnimatedContainer wrapping TextFormField.
    //
    // Verifies that the Container decoration has an empty boxShadow list
    // (C-2 fix). An animated BoxShadow would register _AnimatedState as
    // a listener on the controller, which was the crash path.
    // -------------------------------------------------------------------------
    testWidgets(
      'T-4: rendered Container has empty boxShadow (C-2 regression guard)',
      (WidgetTester tester) async {
        final ctrl = TextEditingController();
        addTearDown(ctrl.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuantityInputWidget(
                controller: ctrl,
                onIncrement: () {},
                onDecrement: () {},
                widgetTag: 'ITEM-TEST',
                label: 'Quantity',
              ),
            ),
          ),
        );

        // Find the Container that wraps the input row.
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) =>
                c.decoration is BoxDecoration &&
                (c.decoration! as BoxDecoration).boxShadow != null)
            .toList();

        for (final c in containers) {
          final shadows = (c.decoration! as BoxDecoration).boxShadow!;
          expect(
            shadows,
            isEmpty,
            reason:
                'boxShadow must be empty — non-empty list enables '
                '_AnimatedState listener registration on the controller '
                '(C-2 regression)',
          );
        }
      },
    );
  });
}
