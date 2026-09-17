import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/modules/pricing/widgets/money_field.dart';
import 'package:multimax/app/modules/pricing/widgets/priority_picker_sheet.dart';
import 'package:multimax/app/modules/pricing/widgets/rule_summary_card.dart';
import 'package:multimax/app/modules/pricing/widgets/scope_tag.dart';
import 'package:multimax/app/modules/pricing/widgets/target_list_editor.dart';

Future<void> pumpIn(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light}) {
  return tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

void main() {
  testWidgets('MoneyField formats to 2 decimals on blur', (tester) async {
    final money = TextEditingController(text: '25');
    await pumpIn(
      tester,
      Column(children: [
        MoneyField(label: 'Rate', controller: money, prefix: 'AED', suffix: '/ Nos'),
        const TextField(key: ValueKey('other')),
      ]),
    );
    expect(find.text('AED'), findsOneWidget);
    expect(find.text('/ Nos'), findsOneWidget);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(money.text, '25.00');
  });

  testWidgets('MoneyField percent mode does not reformat; shows error', (tester) async {
    final pct = TextEditingController(text: '10');
    await pumpIn(
      tester,
      Column(children: [
        MoneyField(
            label: 'Discount',
            controller: pct,
            suffix: '%',
            decimals: null,
            errorText: 'Discount Percentage can not be negative'),
        const TextField(key: ValueKey('other')),
      ]),
    );
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(pct.text, '10');
    expect(find.text('Discount Percentage can not be negative'), findsOneWidget);
  });

  testWidgets('tags, badge and summary render in dark mode', (tester) async {
    await pumpIn(
      tester,
      Builder(
        builder: (context) => Column(children: [
          const ScopeTag(label: 'Customer: Al Noor', icon: Icons.person_outline),
          priceListTag(context, 'Standard Selling', selling: true),
          sideTag(context, selling: false, buying: true),
          const PriorityBadge(priority: '5'),
          const RuleSummaryCard(text: '10% off for everyone', showLabel: true),
        ]),
      ),
      brightness: Brightness.dark,
    );
    expect(find.text('Customer: Al Noor'), findsOneWidget);
    expect(find.text('Standard Selling'), findsOneWidget);
    expect(find.text('Buying'), findsOneWidget);
    expect(find.text('P5'), findsOneWidget);
    expect(find.text('THIS RULE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('priority picker returns the tapped priority', (tester) async {
    String? result = 'untouched';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showPriorityPicker(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('priority-7')));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, '7');
  });

  testWidgets('priority picker "No priority" returns empty string', (tester) async {
    String? result = 'untouched';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showPriorityPicker(context, current: '3'),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No priority'));
    await tester.pumpAndSettle();
    expect(result, '');
  });

  testWidgets('TargetListEditor add/remove/uom callbacks', (tester) async {
    var added = 0;
    int? removed;
    int? uomTapped;
    await pumpIn(
      tester,
      TargetListEditor(
        applyOn: 'Item Code',
        readOnly: false,
        targets: [
          PricingRuleTarget(value: '1000001', label: 'WALLETS COW', uom: 'Nos'),
          PricingRuleTarget(value: '2001490'),
        ],
        onAdd: () => added++,
        onRemove: (i) => removed = i,
        onPickUom: (i) => uomTapped = i,
      ),
    );
    expect(find.text('WALLETS COW'), findsOneWidget);
    expect(find.text('Any unit'), findsOneWidget);
    await tester.tap(find.text('Add item'));
    await tester.tap(find.byTooltip('Remove').last);
    await tester.tap(find.text('Nos'));
    expect(added, 1);
    expect(removed, 1);
    expect(uomTapped, 0);
  });

  testWidgets('TargetListEditor read-only hides add and remove', (tester) async {
    await pumpIn(
      tester,
      TargetListEditor(
        applyOn: 'Item Group',
        readOnly: true,
        targets: [PricingRuleTarget(value: 'Belts')],
        onAdd: () {},
        onRemove: (_) {},
        onPickUom: (_) {},
      ),
    );
    expect(find.text('Belts'), findsOneWidget);
    expect(find.text('Add item group'), findsNothing);
    expect(find.byTooltip('Remove'), findsNothing);
  });
}
