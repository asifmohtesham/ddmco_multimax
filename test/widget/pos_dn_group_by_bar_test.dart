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
}
