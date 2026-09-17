import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';

void main() {
  Map<String, dynamic> ruleJson() => {
        'name': 'PRLE-0001',
        'title': 'Retail winter 10%',
        'disable': 0,
        'apply_on': 'Item Code',
        'price_or_product_discount': 'Price',
        'selling': 1,
        'buying': 0,
        'applicable_for': 'Customer Group',
        'customer_group': 'Retail',
        'rate_or_discount': 'Discount Percentage',
        'discount_percentage': 10,
        'for_price_list': 'Standard Selling',
        'min_qty': 12,
        'valid_from': '2026-10-01',
        'valid_upto': '2026-12-31',
        'currency': 'AED',
        'company': 'Multimax',
        'has_priority': 1,
        'priority': '5',
        'margin_type': 'Percentage',
        'margin_rate_or_amount': 0,
        'modified': '2026-09-17 10:00:00',
        'items': [
          {'name': 'row1', 'item_code': '1000001', 'uom': 'Nos'},
          {'name': 'row2', 'item_code': '2001490', 'uom': null},
        ],
        'item_groups': [],
        'brands': [],
      };

  test('fromJson reads party from the applicable_for field', () {
    final r = PricingRule.fromJson(ruleJson());
    expect(r.applicableFor, 'Customer Group');
    expect(r.party, 'Retail');
    expect(r.priority, '5');
    expect(r.hasPriority, isTrue);
    expect(r.targets.map((t) => t.value), ['1000001', '2001490']);
    expect(r.targets.first.uom, 'Nos');
    expect(r.targets.last.uom, isNull);
    expect(r.isLocked, isFalse);
    expect(r.hasAdvanced, isFalse, reason: 'margin 0 is not advanced');
  });

  test('toJson: matching table only, priority stays a String, names kept', () {
    final out = PricingRule.fromJson(ruleJson()).toJson();
    expect(out['items'], [
      {'name': 'row1', 'item_code': '1000001', 'uom': 'Nos'},
      {'name': 'row2', 'item_code': '2001490', 'uom': null},
    ]);
    expect(out['item_groups'], isEmpty);
    expect(out['brands'], isEmpty);
    expect(out['priority'], '5');
    expect(out['customer_group'], 'Retail');
    expect(out.containsKey('naming_series'), isFalse);
    expect(out.containsKey('apply_discount_on'), isFalse);
    expect(out.containsKey('condition'), isFalse);
  });

  test('new rule: naming series, new rows omit name, Rate clears price list', () {
    final r = PricingRule()
      ..title = 'T'
      ..rateOrDiscount = 'Rate'
      ..rate = 22
      ..forPriceList = 'Standard Selling'
      ..targets = [PricingRuleTarget(value: '1000001')];
    final out = r.toJson();
    expect(out['naming_series'], 'PRLE-.####');
    expect(out['items'], [
      {'item_code': '1000001', 'uom': null}
    ]);
    expect(out['for_price_list'], isNull);
    expect(out['priority'], isNull);
  });

  test('Transaction sends apply_discount_on and no warehouse', () {
    final r = PricingRule()
      ..applyOn = 'Transaction'
      ..warehouse = 'Stores - KA';
    final out = r.toJson();
    expect(out['apply_discount_on'], 'Grand Total');
    expect(out['warehouse'], isNull);
  });

  test('locked when promotional scheme or product rule', () {
    expect((PricingRule()..promotionalScheme = 'Eid').isLocked, isTrue);
    expect((PricingRule()..priceOrProductDiscount = 'Product').isLocked, isTrue);
  });

  test('hasAdvanced for condition / coupon / margin', () {
    expect((PricingRule()..condition = 'territory != "X"').hasAdvanced, isTrue);
    expect((PricingRule()..couponCodeBased = true).hasAdvanced, isTrue);
    expect((PricingRule()..marginRateOrAmount = 5).hasAdvanced, isTrue);
  });
}
