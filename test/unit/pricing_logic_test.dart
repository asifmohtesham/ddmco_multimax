import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';

final today = DateTime(2026, 9, 17, 15, 30);

PricingRule validRule() => PricingRule()
  ..title = 'T'
  ..currency = 'AED'
  ..discountPercentage = 10
  ..targets = [PricingRuleTarget(value: '1000001')];

void main() {
  group('validityOf', () {
    test('no dates → active', () {
      expect(validityOf(null, null, today), ValidityState.active);
    });
    test('from today and upto today are inclusive', () {
      expect(validityOf(DateTime(2026, 9, 17), DateTime(2026, 9, 17), today),
          ValidityState.active);
    });
    test('from tomorrow → upcoming', () {
      expect(validityOf(DateTime(2026, 9, 18), null, today),
          ValidityState.upcoming);
    });
    test('upto yesterday → expired', () {
      expect(validityOf(null, DateTime(2026, 9, 16), today),
          ValidityState.expired);
    });
  });

  test('pricingStatusLabel: disabled wins', () {
    expect(pricingStatusLabel(disabled: true, validity: ValidityState.active),
        'Disabled');
    expect(pricingStatusLabel(disabled: false, validity: ValidityState.upcoming),
        'Upcoming');
    expect(pricingStatusLabel(disabled: false, validity: ValidityState.expired),
        'Expired');
    expect(pricingStatusLabel(disabled: false, validity: ValidityState.active),
        'Active');
  });

  test('itemPriceValidity / pricingRuleStatus read the string dates', () {
    expect(itemPriceValidity(ItemPrice(validFrom: '2026-10-01'), today),
        ValidityState.upcoming);
    expect(pricingRuleStatus(PricingRule(validUpto: '2026-09-01'), today),
        'Expired');
    expect(pricingRuleStatus(PricingRule(disable: true), today), 'Disabled');
  });

  group('validityQuery', () {
    test('upcoming', () {
      final q = validityQuery('Item Price', ValidityState.upcoming, today);
      expect(q.filters, [
        ['Item Price', 'valid_from', '>', '2026-09-17']
      ]);
      expect(q.orFilters, isEmpty);
    });
    test('expired guards null valid_upto (Frappe ifnull fallback)', () {
      final q = validityQuery('Item Price', ValidityState.expired, today);
      expect(q.filters, [
        ['Item Price', 'valid_upto', 'is', 'set'],
        ['Item Price', 'valid_upto', '<', '2026-09-17'],
      ]);
    });
    test('active uses or-filters for open-ended upto', () {
      final q = validityQuery('Pricing Rule', ValidityState.active, today);
      expect(q.filters, [
        ['Pricing Rule', 'valid_from', '<=', '2026-09-17']
      ]);
      expect(q.orFilters, [
        ['Pricing Rule', 'valid_upto', 'is', 'not set'],
        ['Pricing Rule', 'valid_upto', '>=', '2026-09-17'],
      ]);
    });
  });

  test('itemPriceSearchFilter: digits → item_code, text → item_name', () {
    expect(itemPriceSearchFilter(' 1000 '),
        ['Item Price', 'item_code', 'like', '%1000%']);
    expect(itemPriceSearchFilter('wallet'),
        ['Item Price', 'item_name', 'like', '%wallet%']);
  });

  test('buildItemPriceQuery combines every filter', () {
    final q = buildItemPriceQuery(
      priceList: 'Standard Selling',
      search: 'belt',
      validity: ValidityState.active,
      scoped: true,
      hasBatch: true,
      zeroRate: true,
      today: today,
    );
    expect(q.filters, [
      ['Item Price', 'price_list', '=', 'Standard Selling'],
      ['Item Price', 'item_name', 'like', '%belt%'],
      ['Item Price', 'valid_from', '<=', '2026-09-17'],
      ['Item Price', 'reference', 'is', 'set'],
      ['Item Price', 'batch_no', 'is', 'set'],
      ['Item Price', 'price_list_rate', '=', 0],
    ]);
    expect(q.orFilters, hasLength(2));
    expect(buildItemPriceQuery(today: today).filters, isEmpty);
  });

  group('buildPricingRuleQuery', () {
    test('Disabled', () {
      expect(buildPricingRuleQuery(status: 'Disabled', today: today).filters, [
        ['Pricing Rule', 'disable', '=', 1]
      ]);
    });
    test('Upcoming + Buying + search', () {
      final q = buildPricingRuleQuery(
          status: 'Upcoming', side: 'Buying', search: 'eid', today: today);
      expect(q.filters, [
        ['Pricing Rule', 'disable', '=', 0],
        ['Pricing Rule', 'valid_from', '>', '2026-09-17'],
        ['Pricing Rule', 'buying', '=', 1],
        ['Pricing Rule', 'title', 'like', '%eid%'],
      ]);
    });
  });

  test('applicableForOptions follows the side', () {
    expect(applicableForOptions(selling: true, buying: false), kSellingParties);
    expect(applicableForOptions(selling: false, buying: true), kBuyingParties);
    expect(applicableForOptions(selling: true, buying: true),
        [...kSellingParties, ...kBuyingParties]);
  });

  group('describePricingRule (designer grammar)', () {
    test('Discount %', () {
      final r = PricingRule()
        ..currency = 'AED'
        ..discountPercentage = 10
        ..forPriceList = 'Standard Selling'
        ..applicableFor = 'Customer Group'
        ..party = 'Retail'
        ..targets = [
          PricingRuleTarget(value: '1000001'),
          PricingRuleTarget(value: '2001490'),
          PricingRuleTarget(value: '2002943'),
        ]
        ..minQty = 12
        ..validFrom = '2026-10-01'
        ..validUpto = '2026-12-31';
      expect(describePricingRule(r),
          '10% off Standard Selling for customer group Retail on 3 items, min 12 pcs, 1 Oct 2026 – 31 Dec 2026');
    });
    test('Rate', () {
      final r = PricingRule()
        ..currency = 'AED'
        ..rateOrDiscount = 'Rate'
        ..rate = 22
        ..applicableFor = 'Customer'
        ..party = 'Al Noor Trading'
        ..targets = [PricingRuleTarget(value: '1000001')]
        ..validFrom = '2026-11-01'
        ..validUpto = '2027-01-31';
      expect(describePricingRule(r),
          'AED 22.00 for customer Al Noor Trading on item 1000001, 1 Nov 2026 – 31 Jan 2027');
    });
    test('Discount Amount on a group, min amount drops .00', () {
      final r = PricingRule()
        ..currency = 'AED'
        ..applyOn = 'Item Group'
        ..rateOrDiscount = 'Discount Amount'
        ..discountAmount = 5
        ..targets = [PricingRuleTarget(value: 'Belts')]
        ..minAmt = 200
        ..validFrom = '2026-06-01'
        ..validUpto = '2026-08-31';
      expect(describePricingRule(r),
          'AED 5.00 off for everyone on item group Belts, min AED 200, 1 Jun 2026 – 31 Aug 2026');
    });
    test('Transaction', () {
      final r = PricingRule()
        ..currency = 'AED'
        ..applyOn = 'Transaction'
        ..discountPercentage = 5
        ..applicableFor = 'Territory'
        ..party = 'Dubai'
        ..minAmt = 1000;
      expect(describePricingRule(r),
          '5% off the whole transaction for territory Dubai, min AED 1,000');
    });
    test('Product rule', () {
      final r = PricingRule()
        ..priceOrProductDiscount = 'Product'
        ..targets = [
          PricingRuleTarget(value: '1000001'),
          PricingRuleTarget(value: '1000114'),
        ]
        ..freeItem = '2001490'
        ..freeQty = 1
        ..minQty = 3;
      expect(describePricingRule(r),
          'Buy any of 2 items, get 1 × 2001490 free for everyone, min 3 pcs');
    });
    test('targets not loaded → plural noun, open-ended dates', () {
      final r = PricingRule()
        ..applyOn = 'Item Group'
        ..discountPercentage = 7.5
        ..validFrom = '2026-10-01';
      expect(describePricingRule(r),
          '7.5% off for everyone on item groups, from 1 Oct 2026');
      r
        ..validFrom = null
        ..validUpto = '2026-12-31';
      expect(describePricingRule(r),
          '7.5% off for everyone on item groups, until 31 Dec 2026');
    });
  });

  test('pricingRuleDates', () {
    expect(pricingRuleDates(PricingRule()), 'No end date');
    expect(pricingRuleDates(PricingRule(validFrom: '2026-10-01')),
        'from 1 Oct 2026');
    expect(pricingRuleDates(PricingRule(validUpto: '2026-12-31')),
        'until 31 Dec 2026');
    expect(
        pricingRuleDates(
            PricingRule(validFrom: '2026-10-01', validUpto: '2026-12-31')),
        '1 Oct 2026 – 31 Dec 2026');
  });

  test('groupTargetRows groups by parent name and skips empty values', () {
    final grouped = groupTargetRows([
      {'name': 'PRLE-1', 'item_code': 'A', 'uom': 'Nos'},
      {'name': 'PRLE-1', 'item_code': 'B', 'uom': null},
      {'name': 'PRLE-2', 'item_code': null, 'uom': null},
    ], 'item_code');
    expect(grouped.keys, ['PRLE-1']);
    expect(grouped['PRLE-1']!.map((t) => t.value), ['A', 'B']);
    expect(grouped['PRLE-1']!.first.uom, 'Nos');
  });

  test('uomsFromItem: stock uom first, deduped', () {
    expect(
        uomsFromItem({
          'stock_uom': 'Nos',
          'uoms': [
            {'uom': 'Nos'},
            {'uom': 'Box'},
          ],
        }),
        ['Nos', 'Box']);
    expect(uomsFromItem({}), isEmpty);
  });

  group('validatePricingRule', () {
    test('valid rule has no errors', () {
      expect(validatePricingRule(validRule()), isEmpty);
    });
    test('title, side, party, targets', () {
      final r = validRule()
        ..title = ' '
        ..selling = false
        ..applicableFor = 'Customer'
        ..targets = [];
      final e = validatePricingRule(r);
      expect(e['title'], 'Title is required');
      expect(e['selling'], 'Atleast one of the Selling or Buying must be selected');
      expect(e['applicable_for'],
          'Selling must be checked, if Applicable For is selected as Customer');
      expect(e['targets'], 'Item Code is not added in the table');
    });
    test('party missing', () {
      final r = validRule()..applicableFor = 'Customer Group';
      expect(validatePricingRule(r)['party'], 'Customer Group is required');
    });
    test('buying party needs buying', () {
      final r = validRule()..applicableFor = 'Supplier';
      expect(validatePricingRule(r)['applicable_for'],
          'Buying must be checked, if Applicable For is selected as Supplier');
    });
    test('duplicate target and variant+template', () {
      final dup = validRule()
        ..targets = [
          PricingRuleTarget(value: 'A'),
          PricingRuleTarget(value: 'A'),
        ];
      expect(validatePricingRule(dup)['targets'],
          'Duplicate Item Code found in the table');
      final vt = validRule()
        ..targets = [
          PricingRuleTarget(value: 'TPL'),
          PricingRuleTarget(value: 'TPL-RED', variantOf: 'TPL'),
        ];
      expect(validatePricingRule(vt)['targets'],
          'Variant TPL-RED and its template TPL cannot both be added to the same Pricing Rule');
    });
    test('discount checks', () {
      expect(
          validatePricingRule(validRule()..rateOrDiscount = '')['rate_or_discount'],
          'Rate or Discount is required for the price discount.');
      expect(
          validatePricingRule(validRule()
            ..rateOrDiscount = 'Rate'
            ..rate = -1)['rate'],
          'Rate can not be negative');
    });
    test('min/max, dates, cumulative, priority', () {
      final r = validRule()
        ..minQty = 50
        ..maxQty = 12
        ..minAmt = 10
        ..maxAmt = 5
        ..validFrom = '2026-10-01'
        ..validUpto = '2026-09-01'
        ..hasPriority = true
        ..priority = '';
      final e = validatePricingRule(r);
      expect(e['max_qty'], 'Min Qty can not be greater than Max Qty');
      expect(e['max_amt'], 'Min Amt can not be greater than Max Amt');
      expect(e['valid_upto'], 'Valid Upto must be after Valid From');
      expect(e['priority'], 'Priority is mandatory');
      final c = validRule()..isCumulative = true;
      expect(validatePricingRule(c)['valid_from'],
          'Valid from and valid upto fields are mandatory for the cumulative');
    });
    test('Transaction needs no targets', () {
      expect(
          validatePricingRule(validRule()
            ..applyOn = 'Transaction'
            ..targets = []),
          isEmpty);
    });
  });

  test('validateItemPrice', () {
    expect(validateItemPrice(ItemPrice()), {
      'item_code': 'Item is required',
      'price_list': 'Price list is required',
      'uom': 'Unit is required',
    });
    final e = validateItemPrice(ItemPrice(
      itemCode: 'A',
      priceList: 'Standard Selling',
      uom: 'Nos',
      rate: -1,
      validFrom: '2026-10-01',
      validUpto: '2026-09-01',
    ));
    expect(e['price_list_rate'], 'Rate can not be negative');
    expect(e['valid_upto'], 'Valid Upto must be after Valid From');
  });

  test('every validation field maps to a form tab', () {
    for (final f in [
      'title', 'selling', 'applicable_for', 'party', 'targets',
      'rate_or_discount', 'rate', 'discount_percentage', 'discount_amount',
      'max_qty', 'max_amt', 'valid_from', 'valid_upto', 'priority',
    ]) {
      expect(kPricingRuleFieldTab.containsKey(f), isTrue, reason: f);
    }
  });
}
