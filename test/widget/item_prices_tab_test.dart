import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/modules/item/form/widgets/item_prices_tab.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool isTemplate = false,
    List<ItemPrice> prices = const [],
    List<PricingRule> rules = const [],
    bool pricesVisible = true,
    bool rulesVisible = true,
    bool canAddPrice = true,
    VoidCallback? onAdd,
    Brightness brightness = Brightness.light,
  }) =>
      tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness, useMaterial3: true),
        home: Scaffold(
          body: ItemPricesTab(
            isTemplate: isTemplate,
            isLoading: false,
            prices: prices,
            rules: rules,
            pricesVisible: pricesVisible,
            rulesVisible: rulesVisible,
            canAddPrice: canAddPrice,
            onOpenPrice: (_) {},
            onAddPrice: onAdd ?? () {},
            onOpenRule: (_) {},
          ),
        ),
      ));

  testWidgets('no price: calm empty state with Add price', (tester) async {
    var added = 0;
    await pump(tester, onAdd: () => added++);
    expect(find.text('No price set'), findsOneWidget);
    expect(find.text('No rules name this item'), findsOneWidget);
    await tester.tap(find.text('Add price'));
    expect(added, 1);
  });

  testWidgets('template: prices are set on variants, no add button',
      (tester) async {
    await pump(tester, isTemplate: true, brightness: Brightness.dark);
    expect(find.text('Prices are set on variants'), findsOneWidget);
    expect(find.text('Add price'), findsNothing);
    expect(find.text('No rules name this template'), findsOneWidget);
  });

  testWidgets('lists prices and rules', (tester) async {
    await pump(
      tester,
      prices: [
        ItemPrice(
          name: 'h1',
          itemCode: '1000001',
          itemName: 'WALLETS COW',
          uom: 'Nos',
          priceList: 'Standard Selling',
          selling: true,
          currency: 'AED',
          rate: 25,
        ),
      ],
      rules: [
        PricingRule(name: 'PRLE-1', title: 'Retail winter 10%', currency: 'AED')
          ..discountPercentage = 10
          ..targets = [PricingRuleTarget(value: '1000001')],
      ],
    );
    expect(find.text('Standard Selling'), findsOneWidget);
    expect(find.text('25.00'), findsOneWidget);
    expect(find.text('Retail winter 10%'), findsOneWidget);
    expect(find.text('Rules on item groups are not listed here.'), findsOneWidget);
  });

  testWidgets('denied sections are hidden', (tester) async {
    await pump(tester, pricesVisible: false, rulesVisible: false);
    expect(find.text('No price set'), findsNothing);
    expect(find.text('No rules name this item'), findsNothing);
    expect(find.textContaining("don't have access"), findsOneWidget);
  });
}
