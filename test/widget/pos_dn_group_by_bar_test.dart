// test/widget/pos_dn_group_by_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_by_bar.dart';

void main() {
  testWidgets('picking a primary field fires onPrimaryChanged', (tester) async {
    PosDnGroupField? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupByBar(
          primary: null,
          secondary: null,
          onPrimaryChanged: (f) => picked = f,
          onSecondaryChanged: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
        ),
      ),
    ));

    // Open the primary menu (the chip shows the placeholder label).
    await tester.tap(find.text('Group by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Item Group').last);
    await tester.pumpAndSettle();

    expect(picked, PosDnGroupField.itemGroup);
  });

  testWidgets('secondary controls appear only when primary is set',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupByBar(
          primary: PosDnGroupField.itemGroup,
          secondary: null,
          onPrimaryChanged: (_) {},
          onSecondaryChanged: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
        ),
      ),
    ));
    // Expand/collapse-all affordance present when grouped.
    expect(find.byIcon(Icons.unfold_less), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
  });

  testWidgets('dismissing the sheet does NOT fire onPrimaryChanged',
      (tester) async {
    int callCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupByBar(
          primary: null,
          secondary: null,
          onPrimaryChanged: (_) => callCount++,
          onSecondaryChanged: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
        ),
      ),
    ));

    // Open the primary menu.
    await tester.tap(find.text('Group by'));
    await tester.pumpAndSettle();

    // Dismiss the sheet by tapping the barrier (scrim area).
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(callCount, 0);
  });

  testWidgets('picking "None" fires onPrimaryChanged(null)', (tester) async {
    bool called = false;
    PosDnGroupField? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupByBar(
          primary: PosDnGroupField.itemGroup,
          secondary: null,
          onPrimaryChanged: (f) {
            called = true;
            captured = f;
          },
          onSecondaryChanged: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
        ),
      ),
    ));

    // Open the primary menu (the chip now shows 'Item Group').
    await tester.tap(find.text('Item Group').first);
    await tester.pumpAndSettle();

    // Tap 'None'.
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();

    expect(called, true);
    expect(captured, isNull);
  });

  testWidgets('controls absent when primary is null; secondary excludes primary',
      (tester) async {
    // Scenario 1: primary is null.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupByBar(
          primary: null,
          secondary: null,
          onPrimaryChanged: (_) {},
          onSecondaryChanged: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
        ),
      ),
    ));

    expect(find.byIcon(Icons.unfold_less), findsNothing);
    expect(find.byIcon(Icons.unfold_more), findsNothing);
    expect(find.text('+ Then by'), findsNothing);

    // Scenario 2: primary is set, secondary excludes primary.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupByBar(
          primary: PosDnGroupField.itemGroup,
          secondary: null,
          onPrimaryChanged: (_) {},
          onSecondaryChanged: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
        ),
      ),
    ));

    // Open the secondary sheet.
    await tester.tap(find.text('+ Then by'));
    await tester.pumpAndSettle();

    // Item Group should NOT be offered in the secondary sheet.
    expect(find.widgetWithText(ListTile, 'Item Group'), findsNothing);
  });
}
