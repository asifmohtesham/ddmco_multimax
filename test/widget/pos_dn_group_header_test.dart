// test/widget/pos_dn_group_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_header.dart';

void main() {
  GroupNode node() => GroupNode('Straps')
    ..count = 3
    ..posQty = 12
    ..dnQty = 10;

  testWidgets('shows value, count and qty totals; tap toggles', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupHeader(
          node: node(),
          isSecondary: false,
          isExpanded: true,
          onToggle: () => toggled++,
        ),
      ),
    ));

    expect(find.text('Straps'), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets);   // count
    expect(find.textContaining('12'), findsWidgets);  // POS qty
    expect(find.textContaining('10'), findsWidgets);  // DN qty

    await tester.tap(find.byType(PosDnGroupHeader));
    expect(toggled, 1);
  });
}
