# Item Price + Pricing Rule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manager-facing list + form CRUD for ERPNext v15 `Item Price` and `Pricing Rule`, plus a read-mostly "Prices" tab on the Item form.

**Architecture:** Pure, unit-tested logic (`lib/app/modules/pricing/pricing_logic.dart`) owns validity, server filter building, the rule summary sentence and client validation. Mutable models are edited in place through `Rx.update` in GetX form controllers (ToDo form pattern: mode `new|edit|view`, JSON dirty snapshot, `OptimisticLockingMixin`). Screens reuse the shared list/form widgets; five small new pricing widgets live in `lib/app/modules/pricing/widgets/`.

**Tech Stack:** Flutter 3.44 / Dart 3, GetX 4.7.2, Dio, intl, flutter_test (hand-written fakes, no mockito).

**Spec:** `docs/design_handoff_item_price_pricing_rule/README.md` (server contract — wins on behaviour), `docs/design_handoff_item_price_pricing_rule/DESIGN_SPEC.md` (visual contract), `docs/design_handoff_item_price_pricing_rule/CLAUDE_CODE_PROMPT.md` (build brief).

## Global Constraints

- Branch `claude/item-price-pricing-rule-fc930e`, based on `origin/release/play-store` @ `273447f1`. Run `git branch --show-current` before every commit.
- No new packages. Never run `dart format` on EXISTING files (hand-indent edits). New files may be formatted.
- Run `flutter analyze` and `flutter test` sequentially — never at the same time.
- Colours: `context.scheme` (fg/subtle/text/textMuted/textSubtle/border/borderStrong/primary) + `AppColors` x700 light / x300 dark for status ink. Never `Colors.grey`/`Colors.white` surfaces. Both themes.
- Money: `'<CURRENCY CODE> #,##0.00'` (e.g. `AED 25.00`), never summed across rows.
- Dates shown as `d MMM yyyy`; sent as `yyyy-MM-dd`.
- Item Price save payload keys ONLY: `item_code, uom, packing_unit, price_list, customer, supplier, batch_no, price_list_rate, valid_from, valid_upto, lead_time_days, note` (+ `modified` on update). Unset links → `null`.
- Pricing Rule `priority` is a String `"1".."20"`. New rules send `naming_series: 'PRLE-.####'`.
- Delete is gated on `permType: 'write'` (PermissionService has no delete check; delete roles == write roles for both DocTypes — say so in a comment).
- Explicit Save only (no realtime auto-save). Unsaved-changes guard on back.
- `ListTile`/`CheckboxListTile` inside a colour-painted Container must be wrapped in `Material(type: MaterialType.transparency)`.
- Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Out of scope: free-item (Product) rule editing, condition/coupon/recursion/margin editing, effective-price preview, items-without-price report, bulk update, Price List CRUD.

## File map

| File | Responsibility |
|---|---|
| `lib/app/data/models/item_price_model.dart` (new) | `ItemPrice`, `PriceListInfo`, parse helpers `pricingLink/pricingDouble/pricingBool/pricingScrub` |
| `lib/app/data/models/pricing_rule_model.dart` (new) | `PricingRule`, `PricingRuleTarget`, `kPricingRuleTargetTables` |
| `lib/app/modules/pricing/pricing_logic.dart` (new) | validity, filters, summary sentence, validators (pure) |
| `lib/app/data/providers/item_price_provider.dart` (new) | Item Price / Price List / Item REST |
| `lib/app/data/providers/pricing_rule_provider.dart` (new) | Pricing Rule REST, child targets, rules for item, company |
| `lib/app/modules/global_widgets/option_picker_sheet.dart` (new, extracted from ToDo) | single-choice sheet |
| `lib/app/modules/pricing/widgets/*.dart` (new) | MoneyField+FieldErrorText, ScopeTag+PriorityBadge, RuleSummaryCard, PriorityPicker, TargetListEditor, ItemPriceRow, PricingRuleRow |
| `lib/app/modules/pricing/item_price/**` (new) | list + form |
| `lib/app/modules/pricing/pricing_rule/**` (new) | list + form |
| `lib/app/modules/item/form/widgets/item_prices_tab.dart` (new) | Prices tab body |
| Modified | `status_pill.dart`, `generic_document_card.dart`, `api_provider.dart` (getDocumentCount), `item_model.dart` (hasVariants), `todo_form_screen.dart` (use extracted sheet), item form controller/screen/tab controller, routes, pages, drawer, permission_entries, global_search_targets, README |

---

### Task 1: Models

**Files:**
- Create: `lib/app/data/models/item_price_model.dart`
- Create: `lib/app/data/models/pricing_rule_model.dart`
- Test: `test/unit/item_price_model_test.dart`, `test/unit/pricing_rule_model_test.dart`

**Interfaces:**
- Produces: `String? pricingLink(dynamic)`, `double pricingDouble(dynamic)`, `bool pricingBool(dynamic)`, `String pricingScrub(String)`; `class PriceListInfo {name, currency, buying, selling; String get kind}`; mutable `class ItemPrice` (fields below, `fromJson`, `toJson`); mutable `class PricingRuleTarget {String value; String? uom; String? name; String? variantOf; String? label; Map toJson(String field)}`; mutable `class PricingRule` (fields below, `fromJson`, `toJson`, `bool get isLocked`, `bool get hasAdvanced`); `const kPricingRuleTargetTables`.

- [ ] **Step 1: Write the failing tests**

`test/unit/item_price_model_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_price_model.dart';

void main() {
  group('parse helpers', () {
    test('pricingLink turns empty/null into null', () {
      expect(pricingLink(null), isNull);
      expect(pricingLink(''), isNull);
      expect(pricingLink('X'), 'X');
    });
    test('pricingDouble / pricingBool', () {
      expect(pricingDouble(3), 3.0);
      expect(pricingDouble('2.5'), 2.5);
      expect(pricingDouble(null), 0.0);
      expect(pricingBool(1), isTrue);
      expect(pricingBool('1'), isTrue);
      expect(pricingBool(0), isFalse);
    });
    test('pricingScrub', () {
      expect(pricingScrub('Customer Group'), 'customer_group');
    });
  });

  group('ItemPrice', () {
    final json = {
      'name': '5dfs7bls6g',
      'item_code': '1000001',
      'item_name': 'WALLETS COW',
      'uom': 'Nos',
      'packing_unit': 0,
      'price_list': 'Standard Selling',
      'customer': null,
      'supplier': '',
      'batch_no': null,
      'buying': 0,
      'selling': 1,
      'currency': 'AED',
      'price_list_rate': 25,
      'valid_from': '2026-04-22',
      'valid_upto': null,
      'lead_time_days': 0,
      'note': null,
      'brand': null,
      'reference': null,
      'modified': '2026-04-22 17:36:55.939816',
    };

    test('fromJson reads every field', () {
      final p = ItemPrice.fromJson(json);
      expect(p.name, '5dfs7bls6g');
      expect(p.itemCode, '1000001');
      expect(p.itemName, 'WALLETS COW');
      expect(p.selling, isTrue);
      expect(p.buying, isFalse);
      expect(p.rate, 25.0);
      expect(p.supplier, isNull);
      expect(p.validFrom, '2026-04-22');
      expect(p.modified, '2026-04-22 17:36:55.939816');
    });

    test('toJson sends only the client-settable fields', () {
      final out = ItemPrice.fromJson(json).toJson();
      expect(out.keys.toSet(), {
        'item_code', 'uom', 'packing_unit', 'price_list', 'customer',
        'supplier', 'batch_no', 'price_list_rate', 'valid_from',
        'valid_upto', 'lead_time_days', 'note',
      });
      expect(out['supplier'], isNull);
      expect(out['price_list_rate'], 25.0);
    });

    test('PriceListInfo.kind', () {
      final l = PriceListInfo.fromJson(
          {'name': 'Standard Buying', 'currency': 'AED', 'buying': 1, 'selling': 0});
      expect(l.kind, 'Buying');
      expect(l.buying, isTrue);
    });
  });
}
```

`test/unit/pricing_rule_model_test.dart`:
```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/item_price_model_test.dart test/unit/pricing_rule_model_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Implement `lib/app/data/models/item_price_model.dart`**

```dart
/// Frappe Link/Data value → `null` when unset (`null` or `''`).
String? pricingLink(dynamic v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? null : s;
}

double pricingDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

bool pricingBool(dynamic v) => v == 1 || v == true || v == '1';

/// Frappe `scrub`: 'Customer Group' → 'customer_group'.
String pricingScrub(String label) => label.toLowerCase().replaceAll(' ', '_');

class PriceListInfo {
  final String name;
  final String currency;
  final bool buying;
  final bool selling;

  const PriceListInfo({
    required this.name,
    this.currency = '',
    this.buying = false,
    this.selling = false,
  });

  factory PriceListInfo.fromJson(Map<String, dynamic> j) => PriceListInfo(
        name: (j['name'] ?? '').toString(),
        currency: (j['currency'] ?? '').toString(),
        buying: pricingBool(j['buying']),
        selling: pricingBool(j['selling']),
      );

  String get kind => selling ? 'Selling' : 'Buying';
}

/// ERPNext v15 `Item Price`. Mutable working copy: the form controller edits
/// it in place through `Rx.update`.
class ItemPrice {
  String name;
  String itemCode;
  String itemName;
  String uom;
  int packingUnit;
  String priceList;
  String? customer;
  String? supplier;
  String? batchNo;
  bool buying;
  bool selling;
  String currency;
  double rate;
  String? validFrom;
  String? validUpto;
  int leadTimeDays;
  String? note;
  String? brand;
  String modified;

  ItemPrice({
    this.name = '',
    this.itemCode = '',
    this.itemName = '',
    this.uom = '',
    this.packingUnit = 0,
    this.priceList = '',
    this.customer,
    this.supplier,
    this.batchNo,
    this.buying = false,
    this.selling = false,
    this.currency = '',
    this.rate = 0,
    this.validFrom,
    this.validUpto,
    this.leadTimeDays = 0,
    this.note,
    this.brand,
    this.modified = '',
  });

  factory ItemPrice.fromJson(Map<String, dynamic> j) => ItemPrice(
        name: (j['name'] ?? '').toString(),
        itemCode: (j['item_code'] ?? '').toString(),
        itemName: (j['item_name'] ?? '').toString(),
        uom: (j['uom'] ?? '').toString(),
        packingUnit: pricingDouble(j['packing_unit']).toInt(),
        priceList: (j['price_list'] ?? '').toString(),
        customer: pricingLink(j['customer']),
        supplier: pricingLink(j['supplier']),
        batchNo: pricingLink(j['batch_no']),
        buying: pricingBool(j['buying']),
        selling: pricingBool(j['selling']),
        currency: (j['currency'] ?? '').toString(),
        rate: pricingDouble(j['price_list_rate']),
        validFrom: pricingLink(j['valid_from']),
        validUpto: pricingLink(j['valid_upto']),
        leadTimeDays: pricingDouble(j['lead_time_days']).toInt(),
        note: pricingLink(j['note']),
        brand: pricingLink(j['brand']),
        modified: (j['modified'] ?? '').toString(),
      );

  /// Save payload — ONLY the fields ERPNext lets a client set. The server
  /// overwrites buying/selling/currency/item_name/item_description/reference.
  Map<String, dynamic> toJson() => {
        'item_code': itemCode,
        'uom': uom,
        'packing_unit': packingUnit,
        'price_list': priceList,
        'customer': pricingLink(customer),
        'supplier': pricingLink(supplier),
        'batch_no': pricingLink(batchNo),
        'price_list_rate': rate,
        'valid_from': pricingLink(validFrom),
        'valid_upto': pricingLink(validUpto),
        'lead_time_days': leadTimeDays,
        'note': pricingLink(note),
      };
}
```

- [ ] **Step 4: Implement `lib/app/data/models/pricing_rule_model.dart`**

```dart
import 'package:multimax/app/data/models/item_price_model.dart';

/// apply_on → (child table fieldname on Pricing Rule, link field in the row,
/// child DocType name). Transaction has no table.
const Map<String, ({String table, String field, String childDoctype})>
    kPricingRuleTargetTables = {
  'Item Code': (
    table: 'items',
    field: 'item_code',
    childDoctype: 'Pricing Rule Item Code'
  ),
  'Item Group': (
    table: 'item_groups',
    field: 'item_group',
    childDoctype: 'Pricing Rule Item Group'
  ),
  'Brand': (table: 'brands', field: 'brand', childDoctype: 'Pricing Rule Brand'),
};

class PricingRuleTarget {
  String value;
  String? uom;

  /// Child row name; null for rows added in this session.
  final String? name;

  /// Client-only: the target item's template (for the variant+template check).
  String? variantOf;

  /// Client-only: display name (item_name) when known.
  String? label;

  PricingRuleTarget({
    required this.value,
    this.uom,
    this.name,
    this.variantOf,
    this.label,
  });

  Map<String, dynamic> toJson(String field) => {
        if (name != null) 'name': name,
        field: value,
        'uom': pricingLink(uom),
      };
}

/// ERPNext v15 `Pricing Rule`. Mutable working copy edited via `Rx.update`.
class PricingRule {
  String name;
  String title;
  bool disable;
  String applyOn;
  String priceOrProductDiscount;
  bool selling;
  bool buying;

  /// '' = everyone.
  String applicableFor;
  String? party;
  String rateOrDiscount;
  double rate;
  double discountPercentage;
  double discountAmount;
  String? forPriceList;
  String applyDiscountOn;
  double minQty;
  double maxQty;
  double minAmt;
  double maxAmt;
  String? validFrom;
  String? validUpto;
  String? company;
  String currency;
  String? warehouse;
  bool mixedConditions;
  bool isCumulative;
  bool hasPriority;

  /// Select value "1".."20" or ''.
  String priority;
  bool applyMultiplePricingRules;
  List<PricingRuleTarget> targets;
  String modified;

  // ── Read-only in the app (displayed, never sent) ──
  String? promotionalScheme;
  String? freeItem;
  double freeQty;
  bool sameItem;
  String? condition;
  bool couponCodeBased;
  bool isRecursive;
  String? marginType;
  double marginRateOrAmount;
  bool validateAppliedRule;
  double thresholdPercentage;
  bool applyDiscountOnRate;

  PricingRule({
    this.name = '',
    this.title = '',
    this.disable = false,
    this.applyOn = 'Item Code',
    this.priceOrProductDiscount = 'Price',
    this.selling = true,
    this.buying = false,
    this.applicableFor = '',
    this.party,
    this.rateOrDiscount = 'Discount Percentage',
    this.rate = 0,
    this.discountPercentage = 0,
    this.discountAmount = 0,
    this.forPriceList,
    this.applyDiscountOn = 'Grand Total',
    this.minQty = 0,
    this.maxQty = 0,
    this.minAmt = 0,
    this.maxAmt = 0,
    this.validFrom,
    this.validUpto,
    this.company,
    this.currency = '',
    this.warehouse,
    this.mixedConditions = false,
    this.isCumulative = false,
    this.hasPriority = false,
    this.priority = '',
    this.applyMultiplePricingRules = false,
    List<PricingRuleTarget>? targets,
    this.modified = '',
    this.promotionalScheme,
    this.freeItem,
    this.freeQty = 0,
    this.sameItem = false,
    this.condition,
    this.couponCodeBased = false,
    this.isRecursive = false,
    this.marginType,
    this.marginRateOrAmount = 0,
    this.validateAppliedRule = false,
    this.thresholdPercentage = 0,
    this.applyDiscountOnRate = false,
  }) : targets = targets ?? [];

  factory PricingRule.fromJson(Map<String, dynamic> j) {
    final applyOn = (j['apply_on'] ?? 'Item Code').toString();
    final applicableFor = (j['applicable_for'] ?? '').toString();
    final table = kPricingRuleTargetTables[applyOn];
    final rows = table == null ? const [] : (j[table.table] as List? ?? const []);
    return PricingRule(
      name: (j['name'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      disable: pricingBool(j['disable']),
      applyOn: applyOn,
      priceOrProductDiscount:
          (j['price_or_product_discount'] ?? 'Price').toString(),
      selling: pricingBool(j['selling']),
      buying: pricingBool(j['buying']),
      applicableFor: applicableFor,
      party: applicableFor.isEmpty
          ? null
          : pricingLink(j[pricingScrub(applicableFor)]),
      rateOrDiscount: (j['rate_or_discount'] ?? '').toString(),
      rate: pricingDouble(j['rate']),
      discountPercentage: pricingDouble(j['discount_percentage']),
      discountAmount: pricingDouble(j['discount_amount']),
      forPriceList: pricingLink(j['for_price_list']),
      applyDiscountOn: (j['apply_discount_on'] ?? 'Grand Total').toString(),
      minQty: pricingDouble(j['min_qty']),
      maxQty: pricingDouble(j['max_qty']),
      minAmt: pricingDouble(j['min_amt']),
      maxAmt: pricingDouble(j['max_amt']),
      validFrom: pricingLink(j['valid_from']),
      validUpto: pricingLink(j['valid_upto']),
      company: pricingLink(j['company']),
      currency: (j['currency'] ?? '').toString(),
      warehouse: pricingLink(j['warehouse']),
      mixedConditions: pricingBool(j['mixed_conditions']),
      isCumulative: pricingBool(j['is_cumulative']),
      hasPriority: pricingBool(j['has_priority']),
      priority: (j['priority'] ?? '').toString(),
      applyMultiplePricingRules: pricingBool(j['apply_multiple_pricing_rules']),
      targets: [
        for (final row in rows)
          if (table != null && pricingLink((row as Map)[table.field]) != null)
            PricingRuleTarget(
              value: row[table.field].toString(),
              uom: pricingLink(row['uom']),
              name: pricingLink(row['name']),
            ),
      ],
      modified: (j['modified'] ?? '').toString(),
      promotionalScheme: pricingLink(j['promotional_scheme']),
      freeItem: pricingLink(j['free_item']),
      freeQty: pricingDouble(j['free_qty']),
      sameItem: pricingBool(j['same_item']),
      condition: pricingLink(j['condition']),
      couponCodeBased: pricingBool(j['coupon_code_based']),
      isRecursive: pricingBool(j['is_recursive']),
      marginType: pricingLink(j['margin_type']),
      marginRateOrAmount: pricingDouble(j['margin_rate_or_amount']),
      validateAppliedRule: pricingBool(j['validate_applied_rule']),
      thresholdPercentage: pricingDouble(j['threshold_percentage']),
      applyDiscountOnRate: pricingBool(j['apply_discount_on_rate']),
    );
  }

  /// Rules generated by a Promotional Scheme are overwritten when the scheme
  /// is saved; free-item rules are desktop-only in v1.
  bool get isLocked =>
      (promotionalScheme ?? '').isNotEmpty || priceOrProductDiscount == 'Product';

  bool get hasAdvanced =>
      (condition ?? '').isNotEmpty ||
      couponCodeBased ||
      isRecursive ||
      marginRateOrAmount != 0 ||
      validateAppliedRule ||
      thresholdPercentage != 0 ||
      applyDiscountOnRate;

  /// Save payload — the v1-editable fields only. The server clears the fields
  /// of unselected options itself (pricing_rule.py cleanup_fields_value).
  Map<String, dynamic> toJson() => {
        if (name.isEmpty) 'naming_series': 'PRLE-.####',
        'title': title.trim(),
        'disable': disable ? 1 : 0,
        'apply_on': applyOn,
        'price_or_product_discount': priceOrProductDiscount,
        'selling': selling ? 1 : 0,
        'buying': buying ? 1 : 0,
        'applicable_for': pricingLink(applicableFor),
        if (applicableFor.isNotEmpty) pricingScrub(applicableFor): pricingLink(party),
        'rate_or_discount': pricingLink(rateOrDiscount),
        'rate': rate,
        'discount_percentage': discountPercentage,
        'discount_amount': discountAmount,
        'for_price_list':
            rateOrDiscount == 'Rate' ? null : pricingLink(forPriceList),
        if (applyOn == 'Transaction') 'apply_discount_on': applyDiscountOn,
        'min_qty': minQty,
        'max_qty': maxQty,
        'min_amt': minAmt,
        'max_amt': maxAmt,
        'valid_from': pricingLink(validFrom),
        'valid_upto': pricingLink(validUpto),
        'company': pricingLink(company),
        'currency': currency,
        'warehouse': applyOn == 'Transaction' ? null : pricingLink(warehouse),
        'mixed_conditions': mixedConditions ? 1 : 0,
        'is_cumulative': isCumulative ? 1 : 0,
        'has_priority': hasPriority ? 1 : 0,
        'priority': hasPriority ? pricingLink(priority) : null,
        'apply_multiple_pricing_rules': applyMultiplePricingRules ? 1 : 0,
        for (final e in kPricingRuleTargetTables.entries)
          e.value.table: e.key == applyOn
              ? [for (final t in targets) t.toJson(e.value.field)]
              : <Map<String, dynamic>>[],
      };
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/unit/item_price_model_test.dart test/unit/pricing_rule_model_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/models/item_price_model.dart lib/app/data/models/pricing_rule_model.dart test/unit/item_price_model_test.dart test/unit/pricing_rule_model_test.dart
git commit -m "feat(pricing): Item Price and Pricing Rule models

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 2: Pure pricing logic

**Files:**
- Create: `lib/app/modules/pricing/pricing_logic.dart`
- Test: `test/unit/pricing_logic_test.dart`

**Interfaces:**
- Consumes: Task 1 models + helpers.
- Produces (all top-level):
  - `enum ValidityState { active, upcoming, expired }`
  - `typedef FrappeQuery = ({List<List<dynamic>> filters, List<List<dynamic>> orFilters});`
  - `String frappeDate(DateTime)`, `DateTime? parseFrappeDate(String?)`, `String displayDate(String?)`, `String formatMoney(double, String currency)`
  - `ValidityState validityOf(DateTime? from, DateTime? upto, DateTime today)`
  - `String pricingStatusLabel({required bool disabled, required ValidityState validity})`
  - `ValidityState itemPriceValidity(ItemPrice, DateTime today)`, `String pricingRuleStatus(PricingRule, DateTime today)`
  - `FrappeQuery validityQuery(String doctype, ValidityState, DateTime today)`
  - `List<dynamic> itemPriceSearchFilter(String query)`
  - `FrappeQuery buildItemPriceQuery({String priceList, String search, ValidityState? validity, bool scoped, bool hasBatch, bool zeroRate, required DateTime today})`
  - `FrappeQuery buildPricingRuleQuery({String status, String side, String search, required DateTime today})`
  - `const kSellingParties`, `const kBuyingParties`, `List<String> applicableForOptions({required bool selling, required bool buying})`
  - `String describePricingRule(PricingRule)`, `String pricingRuleDates(PricingRule)`
  - `Map<String, List<PricingRuleTarget>> groupTargetRows(List<dynamic> rows, String field)`
  - `List<String> uomsFromItem(Map<String, dynamic> item)`
  - `Map<String, String> validatePricingRule(PricingRule)` and `Map<String, String> validateItemPrice(ItemPrice)` — fieldname → message, insertion-ordered
  - `const Map<String, int> kPricingRuleFieldTab` (field → tab 0 Rule / 1 Discount / 2 Conditions)

- [ ] **Step 1: Write the failing test** — `test/unit/pricing_logic_test.dart`

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/pricing_logic_test.dart`
Expected: FAIL — `pricing_logic.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/app/modules/pricing/pricing_logic.dart`**

```dart
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';

/// Pure pricing logic shared by the Item Price and Pricing Rule screens.
/// No Flutter/GetX imports — everything here is unit-tested.

enum ValidityState { active, upcoming, expired }

typedef FrappeQuery = ({
  List<List<dynamic>> filters,
  List<List<dynamic>> orFilters,
});

final _frappeDateFmt = DateFormat('yyyy-MM-dd');
final _displayDateFmt = DateFormat('d MMM yyyy');
final _amountFmt = NumberFormat('#,##0.00');

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String frappeDate(DateTime d) => _frappeDateFmt.format(d);

DateTime? parseFrappeDate(String? s) =>
    (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

String displayDate(String? s) {
  final d = parseFrappeDate(s);
  return d == null ? '' : _displayDateFmt.format(d);
}

/// `AED 25.00` — the currency CODE, as the mockups show it.
String formatMoney(double v, String currency) => currency.isEmpty
    ? _amountFmt.format(v)
    : '$currency ${_amountFmt.format(v)}';

String _shortMoney(double v, String currency) {
  final s = formatMoney(v, currency);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String _plural(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

// ── Validity ─────────────────────────────────────────────────────────────

/// Both bounds inclusive, compared by calendar day.
ValidityState validityOf(DateTime? from, DateTime? upto, DateTime today) {
  final t = _day(today);
  if (from != null && _day(from).isAfter(t)) return ValidityState.upcoming;
  if (upto != null && _day(upto).isBefore(t)) return ValidityState.expired;
  return ValidityState.active;
}

String pricingStatusLabel({
  required bool disabled,
  required ValidityState validity,
}) {
  if (disabled) return 'Disabled';
  return switch (validity) {
    ValidityState.active => 'Active',
    ValidityState.upcoming => 'Upcoming',
    ValidityState.expired => 'Expired',
  };
}

ValidityState itemPriceValidity(ItemPrice p, DateTime today) => validityOf(
    parseFrappeDate(p.validFrom), parseFrappeDate(p.validUpto), today);

String pricingRuleStatus(PricingRule r, DateTime today) => pricingStatusLabel(
      disabled: r.disable,
      validity: validityOf(
          parseFrappeDate(r.validFrom), parseFrappeDate(r.validUpto), today),
    );

// ── Server filters ───────────────────────────────────────────────────────

/// Frappe wraps date comparisons in `ifnull(col, '0001-01-01')`: a NULL
/// `valid_from` satisfies `<= today` (open start) but a NULL `valid_upto`
/// would also satisfy `< today` — hence the `is set` guard on expired and the
/// or-filter pair on active.
FrappeQuery validityQuery(String doctype, ValidityState state, DateTime today) {
  final d = frappeDate(today);
  switch (state) {
    case ValidityState.upcoming:
      return (
        filters: [
          [doctype, 'valid_from', '>', d]
        ],
        orFilters: const <List<dynamic>>[],
      );
    case ValidityState.expired:
      return (
        filters: [
          [doctype, 'valid_upto', 'is', 'set'],
          [doctype, 'valid_upto', '<', d],
        ],
        orFilters: const <List<dynamic>>[],
      );
    case ValidityState.active:
      return (
        filters: [
          [doctype, 'valid_from', '<=', d]
        ],
        orFilters: [
          [doctype, 'valid_upto', 'is', 'not set'],
          [doctype, 'valid_upto', '>=', d],
        ],
      );
  }
}

/// ponytail: this site's item codes are numeric, so a digits-only query
/// searches item_code and anything else item_name. A single AND clause keeps
/// or_filters free for the Active validity filter.
List<dynamic> itemPriceSearchFilter(String query) {
  final q = query.trim();
  final field = RegExp(r'^\d+$').hasMatch(q) ? 'item_code' : 'item_name';
  return ['Item Price', field, 'like', '%$q%'];
}

FrappeQuery buildItemPriceQuery({
  String priceList = '',
  String search = '',
  ValidityState? validity,
  bool scoped = false,
  bool hasBatch = false,
  bool zeroRate = false,
  required DateTime today,
}) {
  const dt = 'Item Price';
  final filters = <List<dynamic>>[];
  var orFilters = <List<dynamic>>[];
  if (priceList.isNotEmpty) filters.add([dt, 'price_list', '=', priceList]);
  if (search.trim().isNotEmpty) filters.add(itemPriceSearchFilter(search));
  if (validity != null) {
    final v = validityQuery(dt, validity, today);
    filters.addAll(v.filters);
    orFilters = [...v.orFilters];
  }
  // item_price.py before_save copies customer/supplier into `reference`.
  if (scoped) filters.add([dt, 'reference', 'is', 'set']);
  if (hasBatch) filters.add([dt, 'batch_no', 'is', 'set']);
  if (zeroRate) filters.add([dt, 'price_list_rate', '=', 0]);
  return (filters: filters, orFilters: orFilters);
}

/// [status] '' | Active | Upcoming | Expired | Disabled; [side] '' | Selling | Buying.
FrappeQuery buildPricingRuleQuery({
  String status = '',
  String side = '',
  String search = '',
  required DateTime today,
}) {
  const dt = 'Pricing Rule';
  final filters = <List<dynamic>>[];
  var orFilters = <List<dynamic>>[];
  if (status == 'Disabled') {
    filters.add([dt, 'disable', '=', 1]);
  } else if (status.isNotEmpty) {
    filters.add([dt, 'disable', '=', 0]);
    final v = validityQuery(
        dt, ValidityState.values.byName(status.toLowerCase()), today);
    filters.addAll(v.filters);
    orFilters = [...v.orFilters];
  }
  if (side == 'Selling') filters.add([dt, 'selling', '=', 1]);
  if (side == 'Buying') filters.add([dt, 'buying', '=', 1]);
  if (search.trim().isNotEmpty) {
    filters.add([dt, 'title', 'like', '%${search.trim()}%']);
  }
  return (filters: filters, orFilters: orFilters);
}

// ── Party options (pricing_rule.js set_options_for_applicable_for) ───────

const List<String> kSellingParties = [
  'Customer',
  'Customer Group',
  'Territory',
  'Sales Partner',
  'Campaign',
];
const List<String> kBuyingParties = ['Supplier', 'Supplier Group'];

List<String> applicableForOptions({
  required bool selling,
  required bool buying,
}) =>
    [if (selling) ...kSellingParties, if (buying) ...kBuyingParties];

// ── Summary sentence (Claude Design notes grammar) ───────────────────────

const Map<String, String> _targetNoun = {
  'Item Code': 'item',
  'Item Group': 'item group',
  'Brand': 'brand',
};

String _targetsClause(PricingRule r) {
  final noun = _targetNoun[r.applyOn] ?? 'item';
  if (r.targets.isEmpty) return '${noun}s';
  if (r.targets.length == 1) return '$noun ${r.targets.first.value}';
  return _plural(r.targets.length, noun);
}

String _dateClause(PricingRule r) {
  final f = displayDate(r.validFrom);
  final u = displayDate(r.validUpto);
  if (f.isNotEmpty && u.isNotEmpty) return '$f – $u';
  if (f.isNotEmpty) return 'from $f';
  return 'until $u';
}

String describePricingRule(PricingRule r) {
  final isProduct = r.priceOrProductDiscount == 'Product';
  final isTransaction = r.applyOn == 'Transaction';
  final parts = <String>[];

  if (isProduct) {
    final what = isTransaction
        ? 'anything'
        : 'any of ${_plural(r.targets.length, _targetNoun[r.applyOn] ?? 'item')}';
    final free = r.sameItem ? 'the same item' : (r.freeItem ?? 'an item');
    parts.add('Buy $what, get ${_num(r.freeQty)} × $free free');
  } else {
    parts.add(switch (r.rateOrDiscount) {
      'Rate' => formatMoney(r.rate, r.currency),
      'Discount Amount' => '${formatMoney(r.discountAmount, r.currency)} off',
      _ => '${_num(r.discountPercentage)}% off',
    });
    if (isTransaction) {
      parts.add('the whole transaction');
    } else if ((r.forPriceList ?? '').isNotEmpty) {
      parts.add('${r.rateOrDiscount == 'Rate' ? 'on ' : ''}${r.forPriceList}');
    }
  }

  final party = r.party ?? '';
  parts.add(r.applicableFor.isEmpty || party.isEmpty
      ? 'for everyone'
      : 'for ${r.applicableFor.toLowerCase()} $party');

  if (!isProduct && !isTransaction) parts.add('on ${_targetsClause(r)}');

  final constraints = <String>[
    if (r.minQty > 0) 'min ${_num(r.minQty)} pcs',
    if (r.maxQty > 0) 'max ${_num(r.maxQty)} pcs',
    if (r.minAmt > 0) 'min ${_shortMoney(r.minAmt, r.currency)}',
    if (r.maxAmt > 0) 'max ${_shortMoney(r.maxAmt, r.currency)}',
    if (r.validFrom != null || r.validUpto != null) _dateClause(r),
  ];
  final sentence = parts.join(' ');
  return constraints.isEmpty ? sentence : '$sentence, ${constraints.join(', ')}';
}

/// Validity line on list rows.
String pricingRuleDates(PricingRule r) =>
    (r.validFrom == null && r.validUpto == null) ? 'No end date' : _dateClause(r);

// ── Response shaping ─────────────────────────────────────────────────────

/// Rows of a Pricing Rule query joined with one child table
/// (`name` = parent, [field] + `uom` from the child) → targets per rule.
Map<String, List<PricingRuleTarget>> groupTargetRows(
    List<dynamic> rows, String field) {
  final out = <String, List<PricingRuleTarget>>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final value = pricingLink(row[field]);
    final parent = pricingLink(row['name']);
    if (value == null || parent == null) continue;
    out
        .putIfAbsent(parent, () => [])
        .add(PricingRuleTarget(value: value, uom: pricingLink(row['uom'])));
  }
  return out;
}

/// Units an Item Price may use: stock UOM + UOM Conversion rows
/// (item_price.py validate_item rejects any other UOM).
List<String> uomsFromItem(Map<String, dynamic> item) {
  final out = <String>[];
  void add(String? u) {
    if (u != null && !out.contains(u)) out.add(u);
  }

  add(pricingLink(item['stock_uom']));
  for (final row in (item['uoms'] as List? ?? const [])) {
    if (row is Map) add(pricingLink(row['uom']));
  }
  return out;
}

// ── Validation (mirrors pricing_rule.py / item_price.py messages) ────────

const Map<String, int> kPricingRuleFieldTab = {
  'title': 0,
  'selling': 0,
  'applicable_for': 0,
  'party': 0,
  'targets': 0,
  'rate_or_discount': 1,
  'rate': 1,
  'discount_percentage': 1,
  'discount_amount': 1,
  'max_qty': 2,
  'max_amt': 2,
  'valid_from': 2,
  'valid_upto': 2,
  'priority': 2,
};

Map<String, String> validatePricingRule(PricingRule r) {
  final e = <String, String>{};

  if (r.title.trim().isEmpty) e['title'] = 'Title is required';
  if (!r.selling && !r.buying) {
    e['selling'] = 'Atleast one of the Selling or Buying must be selected';
  }

  if (r.applicableFor.isNotEmpty) {
    if (kSellingParties.contains(r.applicableFor) && !r.selling) {
      e['applicable_for'] =
          'Selling must be checked, if Applicable For is selected as ${r.applicableFor}';
    } else if (kBuyingParties.contains(r.applicableFor) && !r.buying) {
      e['applicable_for'] =
          'Buying must be checked, if Applicable For is selected as ${r.applicableFor}';
    } else if ((r.party ?? '').isEmpty) {
      e['party'] = '${r.applicableFor} is required';
    }
  }

  if (r.applyOn != 'Transaction') {
    final values = r.targets.map((t) => t.value).toList();
    if (values.isEmpty) {
      e['targets'] = '${r.applyOn} is not added in the table';
    } else if (values.toSet().length != values.length) {
      e['targets'] = 'Duplicate ${r.applyOn} found in the table';
    } else {
      for (final t in r.targets) {
        if (t.variantOf != null && values.contains(t.variantOf)) {
          e['targets'] =
              'Variant ${t.value} and its template ${t.variantOf} cannot both be added to the same Pricing Rule';
          break;
        }
      }
    }
  }

  if (r.priceOrProductDiscount == 'Price') {
    switch (r.rateOrDiscount) {
      case '':
        e['rate_or_discount'] =
            'Rate or Discount is required for the price discount.';
      case 'Rate':
        if (r.rate < 0) e['rate'] = 'Rate can not be negative';
      case 'Discount Amount':
        if (r.discountAmount < 0) {
          e['discount_amount'] = 'Discount Amount can not be negative';
        }
      default:
        if (r.discountPercentage < 0) {
          e['discount_percentage'] = 'Discount Percentage can not be negative';
        }
    }
  }

  if (r.minQty > 0 && r.maxQty > 0 && r.minQty > r.maxQty) {
    e['max_qty'] = 'Min Qty can not be greater than Max Qty';
  }
  if (r.minAmt > 0 && r.maxAmt > 0 && r.minAmt > r.maxAmt) {
    e['max_amt'] = 'Min Amt can not be greater than Max Amt';
  }

  if (r.isCumulative && (r.validFrom == null || r.validUpto == null)) {
    e['valid_from'] =
        'Valid from and valid upto fields are mandatory for the cumulative';
  }
  final from = parseFrappeDate(r.validFrom);
  final upto = parseFrappeDate(r.validUpto);
  if (from != null && upto != null && upto.isBefore(from)) {
    e['valid_upto'] = 'Valid Upto must be after Valid From';
  }

  if (r.hasPriority && r.priority.isEmpty) {
    e['priority'] = 'Priority is mandatory';
  }
  return e;
}

Map<String, String> validateItemPrice(ItemPrice p) {
  final e = <String, String>{};
  if (p.itemCode.isEmpty) e['item_code'] = 'Item is required';
  if (p.priceList.isEmpty) e['price_list'] = 'Price list is required';
  if (p.uom.isEmpty) e['uom'] = 'Unit is required';
  if (p.rate < 0) e['price_list_rate'] = 'Rate can not be negative';
  final from = parseFrappeDate(p.validFrom);
  final upto = parseFrappeDate(p.validUpto);
  if (from != null && upto != null && upto.isBefore(from)) {
    e['valid_upto'] = 'Valid Upto must be after Valid From';
  }
  return e;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/pricing_logic_test.dart`
Expected: PASS. If a `describePricingRule` expectation fails, fix the implementation — the expected strings are the designer's grammar.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/pricing/pricing_logic.dart test/unit/pricing_logic_test.dart
git commit -m "feat(pricing): validity, filters, summary sentence and validation logic

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Shared widget + API tweaks

**Files:**
- Modify: `lib/app/modules/global_widgets/status_pill.dart` (orange branch of `_ramp`)
- Modify: `lib/app/modules/global_widgets/generic_document_card.dart` (fields, constructor, header Row)
- Modify: `lib/app/data/providers/api_provider.dart` (`getDocumentCount`, ~line 1948)
- Modify: `lib/app/data/models/item_model.dart` (`Item` class, ~lines 120-200)
- Create: `lib/app/modules/global_widgets/option_picker_sheet.dart`
- Modify: `lib/app/modules/todo/form/todo_form_screen.dart` (use the extracted sheet)
- Test: `test/unit/status_pill_colour_test.dart` (extend), `test/widget/generic_document_card_slots_test.dart` (new), `test/unit/item_has_variants_test.dart` (new)

**Interfaces:**
- Produces:
  - `StatusPill` maps `'Upcoming'` → orange.
  - `GenericDocumentCard({..., Widget? trailing, Widget? body})` — `trailing` replaces the status pill slot, `body` renders between the header and the stats row; an empty `subtitle` is not rendered.
  - `ApiProvider.getDocumentCount(String doctype, {Map<String, dynamic>? filters, List<List<dynamic>>? filterTuples})` — tuples win.
  - `Item.hasVariants` (bool).
  - `void showOptionPickerSheet(BuildContext context, {required String title, required List<String> options, required String selected, required ValueChanged<String> onSelected})` and `class OptionPickerSheetShell` (public rename of ToDo's `_PickerSheetShell`, same params: `title`, `child`, `mainAxisSize`).

- [ ] **Step 1: Write the failing tests**

In `test/unit/status_pill_colour_test.dart`, add `'Upcoming'` at the end of the `AppColors.orange700:` list inside the `every status routes to the correct hue` group (after `'Material Returned from WIP',`).

Create `test/widget/generic_document_card_slots_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget card) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card))));

  testWidgets('trailing replaces the status pill; body renders', (tester) async {
    await pump(
      tester,
      GenericDocumentCard(
        title: 'WALLETS COW',
        subtitle: '1000001',
        status: 'Active',
        isExpanded: false,
        navigatesOnTap: true,
        onTap: () {},
        trailing: const Text('AED 25.00'),
        body: const Text('10% off for everyone'),
      ),
    );
    expect(find.text('AED 25.00'), findsOneWidget);
    expect(find.text('10% off for everyone'), findsOneWidget);
    expect(find.byType(StatusPill), findsNothing);
  });

  testWidgets('empty subtitle is not rendered', (tester) async {
    await pump(
      tester,
      GenericDocumentCard(
        title: 'Rule',
        subtitle: '',
        isExpanded: false,
        onTap: () {},
      ),
    );
    expect(find.byType(Text), findsOneWidget);
  });
}
```

Create `test/unit/item_has_variants_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_model.dart';

void main() {
  test('Item.hasVariants reads has_variants', () {
    expect(Item.fromJson({'name': 'T', 'has_variants': 1}).hasVariants, isTrue);
    expect(Item.fromJson({'name': 'V', 'has_variants': 0}).hasVariants, isFalse);
    expect(Item.fromJson({'name': 'X'}).hasVariants, isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/status_pill_colour_test.dart test/widget/generic_document_card_slots_test.dart test/unit/item_has_variants_test.dart`
Expected: FAIL — Upcoming resolves gray; `trailing`/`body`/`hasVariants` undefined.

- [ ] **Step 3: StatusPill** — in `_ramp`, add `case 'Upcoming':` directly after `case 'Late':` (the orange branch).

- [ ] **Step 4: GenericDocumentCard** — hand-edit (no `dart format`):

Add fields after `final Widget? leading;`:
```dart
  /// Optional widget shown in place of the [status] pill at the header's
  /// trailing edge (e.g. a rate block on price rows).
  final Widget? trailing;

  /// Optional block rendered between the header and the stats row
  /// (e.g. a two-line summary sentence).
  final Widget? body;
```
Add `this.trailing,` and `this.body,` to the constructor after `this.leading,`.

In `build`, replace the subtitle pair
```dart
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
```
…through the end of that `Text(...)` with:
```dart
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontFamily: 'ShureTechMono',
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
```
Replace the status slot
```dart
                          if (status != null) ...[
                            const SizedBox(width: 8),
                            StatusPill(status: status!),
                          ],
```
with
```dart
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            trailing!,
                          ] else if (status != null) ...[
                            const SizedBox(width: 8),
                            StatusPill(status: status!),
                          ],
```
Immediately after the header `Row(...)` closes (before `// ── Row 1: primary stats`), insert:
```dart
                      if (body != null) ...[
                        const SizedBox(height: 6),
                        body!,
                      ],
```

- [ ] **Step 5: getDocumentCount** — change the signature and query map in `api_provider.dart`:
```dart
  Future<Response> getDocumentCount(
    String doctype, {
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
  }) async {
    if (!_dioInitialised) await _initDio();
    return _dio.get(
      '/api/method/frappe.client.get_count',
      queryParameters: {
        'doctype': doctype,
        if (filterTuples != null && filterTuples.isNotEmpty)
          'filters': jsonEncode(filterTuples)
        else if (filters != null && filters.isNotEmpty)
          'filters': jsonEncode(filters),
      },
    );
  }
```

- [ ] **Step 6: Item.hasVariants** — in `class Item` add `final bool hasVariants;` next to `isStockItem`, constructor param `this.hasVariants = false,`, and in `fromJson`:
```dart
      hasVariants: json['has_variants'] == 1 || json['has_variants'] == true,
```

- [ ] **Step 7: Extract the option picker** — create `lib/app/modules/global_widgets/option_picker_sheet.dart` by MOVING `_showOptionPicker` and `_PickerSheetShell` out of `todo_form_screen.dart` unchanged in behaviour:
```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Single-choice bottom sheet: title + close, one row per option, a check on
/// [selected]. Extracted from the ToDo form so the pricing forms reuse it.
void showOptionPickerSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String selected,
  required ValueChanged<String> onSelected,
}) {
  Get.bottomSheet(
    SafeArea(
      child: OptionPickerSheetShell(
        title: title,
        mainAxisSize: MainAxisSize.min,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              ListTile(
                title: Text(option),
                trailing: option == selected ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.of(context).pop();
                  onSelected(option);
                },
              ),
          ],
        ),
      ),
    ),
    isScrollControlled: true,
  );
}

/// Rounded surface sheet chrome with a title row and close button.
class OptionPickerSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final MainAxisSize mainAxisSize;

  const OptionPickerSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.mainAxisSize = MainAxisSize.max,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: Column(
        mainAxisSize: mainAxisSize,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
```
In `todo_form_screen.dart`: delete the `_showOptionPicker` method and the `_PickerSheetShell` class, add `import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';`, replace every `_showOptionPicker(` with `showOptionPickerSheet(` and every `_PickerSheetShell(` with `OptionPickerSheetShell(`. Verify with `grep -n "_showOptionPicker\|_PickerSheetShell" lib/app/modules/todo/form/todo_form_screen.dart` → no output.

- [ ] **Step 8: Run tests**

Run: `flutter test test/unit/status_pill_colour_test.dart test/widget/generic_document_card_slots_test.dart test/unit/item_has_variants_test.dart test/widget/todo_form_screen_test.dart test/widget/status_pill_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/app/modules/global_widgets/status_pill.dart lib/app/modules/global_widgets/generic_document_card.dart lib/app/data/providers/api_provider.dart lib/app/data/models/item_model.dart lib/app/modules/global_widgets/option_picker_sheet.dart lib/app/modules/todo/form/todo_form_screen.dart test/unit/status_pill_colour_test.dart test/widget/generic_document_card_slots_test.dart test/unit/item_has_variants_test.dart
git commit -m "refactor(widgets): card trailing/body slots, Upcoming pill, shared option sheet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Providers + pricing widgets

**Files:**
- Create: `lib/app/data/providers/item_price_provider.dart`
- Create: `lib/app/data/providers/pricing_rule_provider.dart`
- Create: `lib/app/modules/pricing/widgets/money_field.dart` (MoneyField + FieldErrorText)
- Create: `lib/app/modules/pricing/widgets/scope_tag.dart` (ScopeTag, priceListTag, sideTag, PriorityBadge)
- Create: `lib/app/modules/pricing/widgets/rule_summary_card.dart`
- Create: `lib/app/modules/pricing/widgets/priority_picker_sheet.dart`
- Create: `lib/app/modules/pricing/widgets/target_list_editor.dart`
- Test: `test/widget/pricing_widgets_test.dart`

**Interfaces:**
- Consumes: Task 1 models, Task 2 `groupTargetRows`, Task 3 `getDocumentCount(filterTuples:)`.
- Produces:
  - `class ItemPriceProvider { static const List<String> listFields; Future<Response> getItemPrices({int limit = 20, int limitStart = 0, List<List<dynamic>>? filters, List<List<dynamic>>? orFilters, String orderBy = 'modified desc'}); Future<Response> getItemPrice(String name); Future<Response> createItemPrice(Map<String, dynamic>); Future<Response> updateItemPrice(String name, Map<String, dynamic>); Future<Response> deleteItemPrice(String name); Future<int> count(List<List<dynamic>> filters); Future<Response> getPriceLists(); Future<Response> getItem(String itemCode); }`
  - `class PricingRuleProvider { static const List<String> listFields; Future<Response> getRules({int limit = 20, int limitStart = 0, List<List<dynamic>>? filters, List<List<dynamic>>? orFilters}); Future<Response> getRule(String name); Future<Response> createRule(Map<String, dynamic>); Future<Response> updateRule(String name, Map<String, dynamic>); Future<Response> deleteRule(String name); Future<int> count(List<List<dynamic>> filters); Future<void> attachTargets(List<PricingRule> rules); Future<List<PricingRule>> rulesForItem(String itemCode, String? variantOf); Future<({String name, String currency})?> getDefaultCompany(); }`
  - `MoneyField({required String label, required TextEditingController controller, String? prefix, String? suffix, bool readOnly = false, String? errorText, int? decimals = 2})` — `decimals: null` = no reformat on blur (percent).
  - `FieldErrorText(String? message)` — renders nothing when null.
  - `ScopeTag({required String label, IconData? icon, Color? ink})`, `Widget priceListTag(BuildContext, String name, {required bool selling})`, `Widget sideTag(BuildContext, {required bool selling, required bool buying})`, `PriorityBadge({required String priority})`
  - `RuleSummaryCard({required String text, bool showLabel = false})`
  - `Future<String?> showPriorityPicker(BuildContext context, {String current = ''})` → `'1'..'20'`, `''` for "No priority", `null` if dismissed. Grid cells keyed `ValueKey('priority-$i')`.
  - `TargetListEditor({required List<PricingRuleTarget> targets, required String applyOn, required bool readOnly, required VoidCallback onAdd, required ValueChanged<int> onRemove, required ValueChanged<int> onPickUom})` — remove buttons have tooltip `'Remove'`.

- [ ] **Step 1: Write the failing widget test** — `test/widget/pricing_widgets_test.dart`

```dart
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
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/widget/pricing_widgets_test.dart`
Expected: FAIL — widget files don't exist.

- [ ] **Step 3: `lib/app/data/providers/item_price_provider.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class ItemPriceProvider {
  final ApiProvider _api = Get.find<ApiProvider>();

  static const List<String> listFields = [
    'name',
    'item_code',
    'item_name',
    'uom',
    'price_list',
    'price_list_rate',
    'currency',
    'customer',
    'supplier',
    'batch_no',
    'valid_from',
    'valid_upto',
    'selling',
    'buying',
    'modified',
  ];

  Future<Response> getItemPrices({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    String orderBy = 'modified desc',
  }) =>
      _api.getDocumentList(
        'Item Price',
        limit: limit,
        limitStart: limitStart,
        fields: listFields,
        filterTuples: filters,
        orFilterTuples: orFilters,
        orderBy: orderBy,
      );

  Future<Response> getItemPrice(String name) =>
      _api.getDocument('Item Price', name);

  Future<Response> createItemPrice(Map<String, dynamic> data) =>
      _api.createDocument('Item Price', data);

  Future<Response> updateItemPrice(String name, Map<String, dynamic> data) =>
      _api.updateDocument('Item Price', name, data);

  Future<Response> deleteItemPrice(String name) =>
      _api.deleteDocument('Item Price', name);

  Future<int> count(List<List<dynamic>> filters) async {
    final res = await _api.getDocumentCount('Item Price', filterTuples: filters);
    return (res.data['message'] as num?)?.toInt() ?? 0;
  }

  /// Enabled price lists (3 on the live site).
  Future<Response> getPriceLists() => _api.getDocumentList(
        'Price List',
        limit: 0,
        fields: const ['name', 'currency', 'buying', 'selling'],
        filters: const {'enabled': 1},
        orderBy: 'name asc',
      );

  /// Full Item doc — the form needs `uoms`, `stock_uom`, `has_variants`.
  Future<Response> getItem(String itemCode) =>
      _api.getDocument('Item', itemCode);
}
```

- [ ] **Step 4: `lib/app/data/providers/pricing_rule_provider.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';

class PricingRuleProvider {
  final ApiProvider _api = Get.find<ApiProvider>();

  static const List<String> listFields = [
    'name', 'title', 'disable', 'apply_on', 'price_or_product_discount',
    'selling', 'buying', 'applicable_for', 'customer', 'customer_group',
    'territory', 'sales_partner', 'campaign', 'supplier', 'supplier_group',
    'rate_or_discount', 'rate', 'discount_percentage', 'discount_amount',
    'for_price_list', 'min_qty', 'max_qty', 'min_amt', 'max_amt',
    'valid_from', 'valid_upto', 'currency', 'has_priority', 'priority',
    'free_item', 'free_qty', 'same_item', 'promotional_scheme', 'modified',
  ];

  // Qualified with the table name: child-table joins below make bare
  // `name`/`modified` ambiguous.
  static List<String> get _qualifiedFields =>
      [for (final f in listFields) '`tabPricing Rule`.`$f`'];

  Future<Response> getRules({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) =>
      _api.getDocumentList(
        'Pricing Rule',
        limit: limit,
        limitStart: limitStart,
        fields: listFields,
        filterTuples: filters,
        orFilterTuples: orFilters,
        orderBy: 'modified desc',
      );

  Future<Response> getRule(String name) => _api.getDocument('Pricing Rule', name);

  Future<Response> createRule(Map<String, dynamic> data) =>
      _api.createDocument('Pricing Rule', data);

  Future<Response> updateRule(String name, Map<String, dynamic> data) =>
      _api.updateDocument('Pricing Rule', name, data);

  Future<Response> deleteRule(String name) =>
      _api.deleteDocument('Pricing Rule', name);

  Future<int> count(List<List<dynamic>> filters) async {
    final res =
        await _api.getDocumentCount('Pricing Rule', filterTuples: filters);
    return (res.data['message'] as num?)?.toInt() ?? 0;
  }

  /// Fills [PricingRule.targets] for list rows: one parent query joined with
  /// each child table. Best-effort — on failure rows keep empty targets and
  /// the summary sentence falls back to "on items".
  /// UNVERIFIED on the live site: child-table fields in /api/resource fields.
  Future<void> attachTargets(List<PricingRule> rules) async {
    for (final entry in kPricingRuleTargetTables.entries) {
      final owners = rules.where((r) => r.applyOn == entry.key).toList();
      if (owners.isEmpty) continue;
      final t = entry.value;
      try {
        final res = await _api.getDocumentList(
          'Pricing Rule',
          limit: 0,
          fields: [
            '`tabPricing Rule`.`name`',
            '`tab${t.childDoctype}`.`${t.field}`',
            '`tab${t.childDoctype}`.`uom`',
          ],
          filterTuples: [
            ['Pricing Rule', 'name', 'in', [for (final r in owners) r.name]],
          ],
          orderBy: '`tabPricing Rule`.`modified` desc',
        );
        final grouped =
            groupTargetRows((res.data['data'] as List?) ?? const [], t.field);
        for (final r in owners) {
          r.targets = grouped[r.name] ?? [];
        }
      } catch (_) {
        // Rows still render; see doc comment.
      }
    }
  }

  /// Rules whose Item Code table names [itemCode] or its template (ERPNext
  /// matches a variant's `variant_of` too). Group/brand rules are not listed.
  /// Throws DioException (e.g. 403) for the caller to hide the section.
  Future<List<PricingRule>> rulesForItem(String itemCode, String? variantOf) async {
    final codes = [itemCode, if ((variantOf ?? '').isNotEmpty) variantOf!];
    final res = await _api.getDocumentList(
      'Pricing Rule',
      limit: 0,
      fields: _qualifiedFields,
      filterTuples: [
        ['Pricing Rule Item Code', 'item_code', 'in', codes],
      ],
      orderBy: '`tabPricing Rule`.`modified` desc',
    );
    final seen = <String>{};
    final rules = <PricingRule>[
      for (final row in (res.data['data'] as List?) ?? const [])
        if (row is Map && seen.add((row['name'] ?? '').toString()))
          PricingRule.fromJson(Map<String, dynamic>.from(row)),
    ];
    await attachTargets(rules);
    return rules;
  }

  Future<({String name, String currency})?> getDefaultCompany() async {
    final res = await _api.getDocumentList(
      'Company',
      limit: 1,
      fields: const ['name', 'default_currency'],
      orderBy: 'creation asc',
    );
    final rows = (res.data['data'] as List?) ?? const [];
    if (rows.isEmpty) return null;
    final m = Map<String, dynamic>.from(rows.first as Map);
    return (
      name: (m['name'] ?? '').toString(),
      currency: (m['default_currency'] ?? '').toString(),
    );
  }
}
```

- [ ] **Step 5: `lib/app/modules/pricing/widgets/money_field.dart`**

```dart
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// Large tabular numeric input with an optional currency prefix and unit
/// suffix (DESIGN_SPEC "MoneyField"). Reformats to [decimals] places on blur;
/// pass `decimals: null` for percentages.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.prefix,
    this.suffix,
    this.readOnly = false,
    this.errorText,
    this.decimals = 2,
  });

  final String label;
  final TextEditingController controller;
  final String? prefix;
  final String? suffix;
  final bool readOnly;
  final String? errorText;
  final int? decimals;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus) _format();
    setState(() {});
  }

  void _format() {
    final d = widget.decimals;
    if (d == null || widget.readOnly) return;
    final v = double.tryParse(widget.controller.text.replaceAll(',', ''));
    if (v == null) return;
    final text = v.toStringAsFixed(d);
    if (text != widget.controller.text) widget.controller.text = text;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final focused = _focus.hasFocus && !widget.readOnly;
    final hasError = widget.errorText != null;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: widget.readOnly ? s.subtle : s.fg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasError
                  ? AppColors.red500
                  : focused
                      ? s.primary
                      : (widget.readOnly ? s.border : s.borderStrong),
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                        color: s.primary.withValues(alpha: 0.22),
                        spreadRadius: 3)
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.label,
                  style: TextStyle(fontSize: 10, color: s.textMuted)),
              Row(
                children: [
                  if (widget.prefix != null) ...[
                    Text(widget.prefix!,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: s.textMuted)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      readOnly: widget.readOnly,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: s.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (widget.suffix != null) ...[
                    const SizedBox(width: 6),
                    Text(widget.suffix!,
                        style: TextStyle(fontSize: 13, color: s.textMuted)),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(widget.errorText!,
                style: TextStyle(
                    fontSize: 11,
                    color: dark ? AppColors.red300 : AppColors.red700)),
          ),
      ],
    );
  }
}

/// Inline field error line used under DocPickerFields (which have no error
/// slot). Renders nothing for a null message.
class FieldErrorText extends StatelessWidget {
  const FieldErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.red300 : AppColors.red700;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 13, color: ink),
          const SizedBox(width: 5),
          Expanded(
            child: Text(message!, style: TextStyle(fontSize: 11, color: ink)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: `lib/app/modules/pricing/widgets/scope_tag.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// 20dp neutral tag (DESIGN_SPEC "ScopeTag"): customer / supplier / batch /
/// dates on list rows. [ink] recolours text + icon (price-list / side tags).
class ScopeTag extends StatelessWidget {
  const ScopeTag({super.key, required this.label, this.icon, this.ink});

  final String label;
  final IconData? icon;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final color = ink ?? s.textMuted;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: s.subtle,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

Color _sideInk(BuildContext context, {required bool selling}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (selling) return dark ? AppColors.green300 : AppColors.green700;
  return dark ? AppColors.blue300 : AppColors.blue700;
}

/// Price-list tag: green ink for selling lists, blue for buying.
Widget priceListTag(BuildContext context, String name, {required bool selling}) =>
    ScopeTag(label: name, ink: _sideInk(context, selling: selling));

/// "Selling" / "Buying" / "Selling & Buying" tag for rule rows.
Widget sideTag(BuildContext context,
        {required bool selling, required bool buying}) =>
    ScopeTag(
      label: selling && buying
          ? 'Selling & Buying'
          : buying
              ? 'Buying'
              : 'Selling',
      ink: _sideInk(context, selling: !(buying && !selling)),
    );

/// "P5" accent badge.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.fg),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'P$priority',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: s.primary),
      ),
    );
  }
}
```

- [ ] **Step 7: `lib/app/modules/pricing/widgets/rule_summary_card.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// Accent-tinted card holding the generated rule sentence; first child of
/// every Pricing Rule form tab.
class RuleSummaryCard extends StatelessWidget {
  const RuleSummaryCard({super.key, required this.text, this.showLabel = false});

  final String text;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Container(
      padding: showLabel
          ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
          : const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.fg),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Color.alphaBlend(s.primary.withValues(alpha: 0.40), s.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, size: 18, color: s.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showLabel)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('THIS RULE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: s.primary)),
                  ),
                Text(text,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: s.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: `lib/app/modules/pricing/widgets/priority_picker_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// 1–20 grid. Returns the chosen priority, `''` for "No priority", or `null`
/// when dismissed.
Future<String?> showPriorityPicker(BuildContext context, {String current = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PriorityPickerSheet(current: current),
  );
}

class _PriorityPickerSheet extends StatefulWidget {
  const _PriorityPickerSheet({required this.current});

  final String current;

  @override
  State<_PriorityPickerSheet> createState() => _PriorityPickerSheetState();
}

class _PriorityPickerSheetState extends State<_PriorityPickerSheet> {
  late String _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        decoration: BoxDecoration(
          color: s.fg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                    color: s.borderStrong,
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Row(
              children: [
                Text('Priority',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: s.text)),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, height: 1.45, color: s.textMuted),
                children: const [
                  TextSpan(
                      text:
                          'Higher number wins when several rules match the same line. Two matching rules with the '),
                  TextSpan(
                      text: 'same',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: ' priority block the Delivery Note from saving.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.4,
              children: [
                for (var i = 1; i <= 20; i++) _cell(context, '$i'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(''),
                    child: const Text('No priority'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_selected),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String value) {
    final s = context.scheme;
    final on = value == _selected;
    return InkWell(
      key: ValueKey('priority-$value'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selected = value),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? s.primary : s.fg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? s.primary : s.borderStrong),
        ),
        child: Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: on ? s.onPrimary : s.text)),
      ),
    );
  }
}
```

- [ ] **Step 9: `lib/app/modules/pricing/widgets/target_list_editor.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';

/// Rule targets (items / item groups / brands) with an optional unit chip,
/// remove button and an "Add …" footer row.
class TargetListEditor extends StatelessWidget {
  const TargetListEditor({
    super.key,
    required this.targets,
    required this.applyOn,
    required this.readOnly,
    required this.onAdd,
    required this.onRemove,
    required this.onPickUom,
  });

  final List<PricingRuleTarget> targets;
  final String applyOn;
  final bool readOnly;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onPickUom;

  static const _addLabel = {
    'Item Code': 'Add item',
    'Item Group': 'Add item group',
    'Brand': 'Add brand',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isItem = applyOn == 'Item Code';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < targets.length; i++)
              Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: EdgeInsets.fromLTRB(12, 3, readOnly ? 12 : 4, 3),
                decoration: BoxDecoration(
                  color: s.fg,
                  border: Border(bottom: BorderSide(color: s.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isItem && targets[i].label != null)
                            Text(targets[i].value,
                                style: TextStyle(
                                    fontFamily: 'ShureTechMono',
                                    fontSize: 11,
                                    color: s.textMuted)),
                          Text(
                            (isItem ? targets[i].label : null) ?? targets[i].value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: s.text),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _UomChip(
                      uom: targets[i].uom,
                      onTap: readOnly ? null : () => onPickUom(i),
                    ),
                    if (!readOnly)
                      IconButton(
                        tooltip: 'Remove',
                        icon: Icon(Icons.close, size: 20, color: s.textSubtle),
                        onPressed: () => onRemove(i),
                      ),
                  ],
                ),
              ),
            if (!readOnly)
              InkWell(
                onTap: onAdd,
                child: Container(
                  height: 44,
                  color: s.subtle,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 18, color: s.primary),
                      const SizedBox(width: 8),
                      Text(_addLabel[applyOn] ?? 'Add',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: s.primary)),
                      const Spacer(),
                      // The item picker listens for scans (enableBarcodeScan).
                      if (isItem)
                        Icon(Icons.qr_code_scanner, size: 20, color: s.primary),
                    ],
                  ),
                ),
              )
            else if (targets.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('None', style: TextStyle(color: s.textMuted)),
              ),
          ],
        ),
      ),
    );
  }
}

class _UomChip extends StatelessWidget {
  const _UomChip({required this.uom, required this.onTap});

  final String? uom;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: uom == null ? s.border : s.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(uom ?? 'Any unit',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: uom == null ? s.textSubtle : s.textMuted)),
            if (onTap != null)
              Icon(Icons.arrow_drop_down, size: 14, color: s.textSubtle),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 10: Run tests**

Run: `flutter test test/widget/pricing_widgets_test.dart`
Expected: PASS. Then `flutter analyze lib/app/data/providers/item_price_provider.dart lib/app/data/providers/pricing_rule_provider.dart lib/app/modules/pricing` → no issues.

- [ ] **Step 11: Commit**

```bash
git add lib/app/data/providers/item_price_provider.dart lib/app/data/providers/pricing_rule_provider.dart lib/app/modules/pricing/widgets test/widget/pricing_widgets_test.dart
git commit -m "feat(pricing): providers and shared pricing widgets

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Item Price list screen

**Files:**
- Create: `lib/app/modules/pricing/widgets/item_price_row.dart`
- Create: `lib/app/modules/pricing/item_price/item_price_binding.dart`
- Create: `lib/app/modules/pricing/item_price/item_price_controller.dart`
- Create: `lib/app/modules/pricing/item_price/item_price_screen.dart`
- Create: `lib/app/modules/pricing/item_price/widgets/item_price_list_app_bar.dart`
- Create: `lib/app/modules/pricing/item_price/widgets/item_price_filter_sheet.dart`
- Modify: `lib/app/data/routes/app_routes.dart` (add ITEM_PRICE, ITEM_PRICE_FORM, PRICING_RULE, PRICING_RULE_FORM constants now so later tasks compile)
- Modify: `lib/app/data/routes/app_pages.dart` (ITEM_PRICE page only)
- Test: `test/widget/item_price_screen_test.dart`

**Interfaces:**
- Consumes: `ItemPriceProvider` (Task 4), `buildItemPriceQuery`, `itemPriceValidity`, `pricingStatusLabel`, `displayDate`, `formatMoney` (Task 2), `ScopeTag`, `priceListTag` (Task 4), `GenericDocumentCard(trailing:)` (Task 3).
- Produces:
  - `AppRoutes.ITEM_PRICE = '/item-price'`, `ITEM_PRICE_FORM = '/item-price/form'`, `PRICING_RULE = '/pricing-rule'`, `PRICING_RULE_FORM = '/pricing-rule/form'`.
  - `ItemPriceRow({required ItemPrice price, required VoidCallback onTap, DateTime? today})` (reused by Task 9).
  - `ItemPriceController` (fields listed in code) with `openPrice(ItemPrice?)`.
  - Form route arguments contract: `{'name': String, 'mode': 'new'|'edit'|'view', 'item_code'?: String}`.

- [ ] **Step 1: Routes** — in `app_routes.dart` add to `AppRoutes` (after `MATERIAL_REQUEST_FORM`):
```dart
  static const ITEM_PRICE            = _Paths.ITEM_PRICE;
  static const ITEM_PRICE_FORM       = _Paths.ITEM_PRICE_FORM;
  static const PRICING_RULE          = _Paths.PRICING_RULE;
  static const PRICING_RULE_FORM     = _Paths.PRICING_RULE_FORM;
```
and to `_Paths` (after `MATERIAL_REQUEST_FORM`):
```dart
  static const ITEM_PRICE            = '/item-price';
  static const ITEM_PRICE_FORM       = '/item-price/form';
  static const PRICING_RULE          = '/pricing-rule';
  static const PRICING_RULE_FORM     = '/pricing-rule/form';
```

- [ ] **Step 2: Write the failing widget test** — `test/widget/item_price_screen_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_screen.dart';

class _FakeItemPriceProvider extends ItemPriceProvider {
  _FakeItemPriceProvider(this.rows);
  final List<Map<String, dynamic>> rows;

  Response _ok(dynamic data) =>
      Response(requestOptions: RequestOptions(path: '/'), statusCode: 200, data: data);

  @override
  Future<Response> getItemPrices({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    String orderBy = 'modified desc',
  }) async =>
      _ok({'data': rows});

  @override
  Future<Response> getPriceLists() async => _ok({
        'data': [
          {'name': 'Standard Selling', 'currency': 'AED', 'selling': 1, 'buying': 0},
          {'name': 'Standard Buying', 'currency': 'AED', 'selling': 0, 'buying': 1},
        ]
      });

  @override
  Future<int> count(List<List<dynamic>> filters) async => rows.length;
}

class _StubPermissionService extends PermissionService {
  _StubPermissionService(bool? value) : grant = Rx<bool?>(value);
  final Rx<bool?> grant;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => grant.value;
}

Map<String, dynamic> _row(String code, String name, num rate,
        {String? upto, String? customer}) =>
    {
      'name': 'hash-$code',
      'item_code': code,
      'item_name': name,
      'uom': 'Nos',
      'price_list': 'Standard Selling',
      'price_list_rate': rate,
      'currency': 'AED',
      'selling': 1,
      'buying': 0,
      'valid_from': '2026-01-01',
      'valid_upto': upto,
      'customer': customer,
    };

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester,
      {required List<Map<String, dynamic>> rows, bool? grant = true}) async {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(AuthenticationController());
    Get.put<PermissionService>(_StubPermissionService(grant));
    Get.put<ItemPriceProvider>(_FakeItemPriceProvider(rows));
    Get.put(ItemPriceController());
    await tester.pumpWidget(const GetMaterialApp(home: ItemPriceScreen()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders rows with rate, scope tag, expired pill and zero hint',
      (tester) async {
    await pump(tester, rows: [
      _row('1000001', 'WALLETS COW', 25, customer: 'Al Noor Trading'),
      _row('2001528', 'BELTS CASUAL 35MM', 0, upto: '2026-02-01'),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('WALLETS COW'), findsOneWidget);
    expect(find.text('25.00'), findsOneWidget);
    expect(find.text('Customer: Al Noor Trading'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('zero · / Nos'), findsOneWidget);
    expect(find.text('New price'), findsOneWidget);
  });

  testWidgets('empty list shows the empty state; FAB hidden without create',
      (tester) async {
    await pump(tester, rows: const [], grant: false);
    expect(tester.takeException(), isNull);
    expect(find.text('No item prices'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/widget/item_price_screen_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 4: `lib/app/modules/pricing/widgets/item_price_row.dart`**

```dart
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/widgets/scope_tag.dart';

/// Item Price list row (DESIGN_SPEC §A). Navigational: tap opens the form.
class ItemPriceRow extends StatelessWidget {
  const ItemPriceRow({
    super.key,
    required this.price,
    required this.onTap,
    this.today,
  });

  final ItemPrice price;
  final VoidCallback onTap;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final validity = itemPriceValidity(price, today ?? DateTime.now());
    return GenericDocumentCard(
      title: price.itemName.isEmpty ? price.itemCode : price.itemName,
      subtitle: price.itemCode,
      isExpanded: false,
      navigatesOnTap: true,
      onTap: onTap,
      trailing: _RateBlock(price: price),
      stats: [
        priceListTag(context, price.priceList, selling: price.selling),
        if (validity != ValidityState.active)
          StatusPill(
            status: pricingStatusLabel(disabled: false, validity: validity),
            compact: true,
          ),
        if (price.customer != null)
          ScopeTag(icon: Icons.person_outline, label: 'Customer: ${price.customer}'),
        if (price.supplier != null)
          ScopeTag(
              icon: Icons.local_shipping_outlined,
              label: 'Supplier: ${price.supplier}'),
        if (price.batchNo != null)
          ScopeTag(icon: Icons.tag, label: 'Batch ${price.batchNo}'),
        if (validity == ValidityState.upcoming && price.validFrom != null)
          ScopeTag(
              icon: Icons.event_outlined,
              label: 'from ${displayDate(price.validFrom)}'),
        if (price.validUpto != null)
          ScopeTag(
              icon: Icons.event_outlined,
              label: 'until ${displayDate(price.validUpto)}'),
      ],
    );
  }
}

class _RateBlock extends StatelessWidget {
  const _RateBlock({required this.price});

  final ItemPrice price;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final zero = price.rate == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (price.currency.isNotEmpty) ...[
              Text(price.currency,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: s.textMuted)),
              const SizedBox(width: 3),
            ],
            Text(
              FormattingHelper.formatAmount(price.rate),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: s.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          zero ? 'zero · / ${price.uom}' : '/ ${price.uom}',
          style: TextStyle(fontSize: 11, color: zero ? s.textSubtle : s.textMuted),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: `lib/app/modules/pricing/item_price/item_price_controller.dart`**

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';

class ItemPriceController extends GetxController {
  final ItemPriceProvider _provider = Get.find<ItemPriceProvider>();

  final scrollController = ScrollController();

  final prices = <ItemPrice>[].obs;
  final isLoading = true.obs;
  final isFetchingMore = false.obs;
  final hasMore = true.obs;

  final priceLists = <PriceListInfo>[].obs;

  /// Row counts keyed by price list name; '' = all lists.
  final listCounts = <String, int>{}.obs;

  /// '' = all lists.
  final selectedPriceList = ''.obs;

  /// Filter-sheet state for DocTypeListHeader: 'validity' → Active|Upcoming|
  /// Expired; 'scoped' / 'batch' / 'zero' → true.
  final activeFilters = <String, dynamic>{}.obs;
  final searchQuery = ''.obs;

  static const int _limit = 20;
  int _page = 0;
  Timer? _debounce;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
  }

  @override
  void onReady() {
    super.onReady();
    loadPriceLists();
    fetchPrices();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    scrollController.dispose();
    super.onClose();
  }

  bool get hasActiveFilters =>
      activeFilters.isNotEmpty || searchQuery.value.isNotEmpty;

  /// Server total for the selected list when nothing narrows it; otherwise
  /// the loaded rows (with "more" affordance).
  int get displayCount {
    final key = selectedPriceList.value;
    if (!hasActiveFilters && listCounts.containsKey(key)) return listCounts[key]!;
    return prices.length;
  }

  bool get countHasMore {
    if (!hasActiveFilters && listCounts.containsKey(selectedPriceList.value)) {
      return false;
    }
    return hasMore.value;
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final p = scrollController.position;
    if (p.pixels >= p.maxScrollExtent * 0.9 &&
        hasMore.value &&
        !isFetchingMore.value &&
        !isLoading.value) {
      fetchPrices(isLoadMore: true);
    }
  }

  FrappeQuery _query() {
    final v = activeFilters['validity'] as String?;
    return buildItemPriceQuery(
      priceList: selectedPriceList.value,
      search: searchQuery.value,
      validity: v == null ? null : ValidityState.values.byName(v.toLowerCase()),
      scoped: activeFilters['scoped'] == true,
      hasBatch: activeFilters['batch'] == true,
      zeroRate: activeFilters['zero'] == true,
      today: DateTime.now(),
    );
  }

  Future<void> loadPriceLists() async {
    try {
      final res = await _provider.getPriceLists();
      priceLists.assignAll([
        for (final e in (res.data['data'] as List?) ?? const [])
          PriceListInfo.fromJson(Map<String, dynamic>.from(e as Map)),
      ]);
      final counts = await Future.wait([
        _provider.count(const []),
        for (final l in priceLists)
          _provider.count([
            ['Item Price', 'price_list', '=', l.name]
          ]),
      ]);
      listCounts.assignAll({
        '': counts.first,
        for (var i = 0; i < priceLists.length; i++)
          priceLists[i].name: counts[i + 1],
      });
    } catch (_) {
      // Chips still work without counts.
    }
  }

  Future<void> fetchPrices({bool isLoadMore = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      _page = 0;
      hasMore.value = true;
    }
    try {
      final q = _query();
      final res = await _provider.getItemPrices(
        limit: _limit,
        limitStart: _page * _limit,
        filters: q.filters,
        orFilters: q.orFilters,
      );
      final rows = [
        for (final e in (res.data['data'] as List?) ?? const [])
          ItemPrice.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      hasMore.value = rows.length == _limit;
      if (isLoadMore) {
        prices.addAll(rows);
      } else {
        prices.assignAll(rows);
      }
      _page++;
    } catch (_) {
      GlobalSnackbar.error(message: 'Failed to load item prices');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  void selectPriceList(String name) {
    if (selectedPriceList.value == name) return;
    selectedPriceList.value = name;
    fetchPrices();
  }

  void onSearchChanged(String query) {
    searchQuery.value = query;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), fetchPrices);
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.assignAll(filters);
    fetchPrices();
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchPrices();
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchPrices();
  }

  Future<void> openPrice(ItemPrice? price) async {
    await Get.toNamed(
      AppRoutes.ITEM_PRICE_FORM,
      arguments: {'name': price?.name ?? '', 'mode': price == null ? 'new' : 'edit'},
    );
    if (price == null) {
      loadPriceLists();
      fetchPrices();
    } else {
      await refreshPrice(price.name);
    }
  }

  /// Re-reads one row after the form; a 404 means it was deleted.
  Future<void> refreshPrice(String name) async {
    try {
      final res = await _provider.getItemPrice(name);
      final data = res.data is Map ? res.data['data'] : null;
      final i = prices.indexWhere((p) => p.name == name);
      if (i != -1 && data is Map) {
        prices[i] = ItemPrice.fromJson(Map<String, dynamic>.from(data));
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        prices.removeWhere((p) => p.name == name);
        loadPriceLists();
      }
    } catch (_) {}
  }
}
```

- [ ] **Step 6: `lib/app/modules/pricing/item_price/item_price_binding.dart`**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';

class ItemPriceBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ItemPriceProvider>()) {
      Get.lazyPut<ItemPriceProvider>(() => ItemPriceProvider(), fenix: true);
    }
    Get.lazyPut<ItemPriceController>(() => ItemPriceController());
  }
}
```

- [ ] **Step 7: `lib/app/modules/pricing/item_price/widgets/item_price_list_app_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/widgets/item_price_filter_sheet.dart';

class ItemPriceListAppBar extends StatelessWidget {
  const ItemPriceListAppBar({super.key});

  void _openFilters() => Get.bottomSheet(
        const ItemPriceFilterSheet(),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );

  List<Widget> _chips(ItemPriceController c) {
    final af = c.activeFilters;
    return [
      if (af['validity'] != null)
        FilterChipWidget(
          icon: Icons.event_outlined,
          label: '${af['validity']}',
          onDeleted: () => c.removeFilter('validity'),
        ),
      if (af['scoped'] == true)
        FilterChipWidget(
          icon: Icons.person_outline,
          label: 'Has customer or supplier',
          onDeleted: () => c.removeFilter('scoped'),
        ),
      if (af['batch'] == true)
        FilterChipWidget(
          icon: Icons.tag,
          label: 'Has batch',
          onDeleted: () => c.removeFilter('batch'),
        ),
      if (af['zero'] == true)
        FilterChipWidget(
          icon: Icons.exposure_zero,
          label: 'Zero rate',
          onDeleted: () => c.removeFilter('zero'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ItemPriceController>();
    return DocTypeListHeader(
      title: 'Item Price',
      automaticallyImplyLeading: false,
      searchQuery: c.searchQuery,
      onSearchChanged: c.onSearchChanged,
      onSearchClear: () => c.onSearchChanged(''),
      activeFilters: c.activeFilters,
      onFilterTap: _openFilters,
      filterChipsBuilder: (_) => _chips(c),
      onClearAllFilters: c.clearFilters,
      // Own Obx: the sliver header does not repaint on content-only changes.
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Obx(
          () => ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            children: [
              _chip(c, '', 'All'),
              for (final l in c.priceLists) _chip(c, l.name, l.name),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(ItemPriceController c, String value, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SelectableFilterChip(
          label: label,
          count: c.listCounts[value],
          selected: c.selectedPriceList.value == value,
          onSelected: (_) => c.selectPriceList(value),
        ),
      );
}
```

- [ ] **Step 8: `lib/app/modules/pricing/item_price/widgets/item_price_filter_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';

/// Validity (single choice) + scope checkboxes. Price list lives in the header
/// chips, not here.
class ItemPriceFilterSheet extends StatefulWidget {
  const ItemPriceFilterSheet({super.key});

  @override
  State<ItemPriceFilterSheet> createState() => _ItemPriceFilterSheetState();
}

class _ItemPriceFilterSheetState extends State<ItemPriceFilterSheet> {
  final c = Get.find<ItemPriceController>();
  late String validity = (c.activeFilters['validity'] as String?) ?? '';
  late bool scoped = c.activeFilters['scoped'] == true;
  late bool batch = c.activeFilters['batch'] == true;
  late bool zero = c.activeFilters['zero'] == true;

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: context.scheme.textMuted)),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        decoration: BoxDecoration(
          color: s.fg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        // CheckboxListTile inside a painted Container needs its own Material.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Filter prices',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: s.text)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              _label(context, 'VALIDITY'),
              SettingsSegmented<String>(
                options: const [
                  SegmentOption(value: '', label: 'Any'),
                  SegmentOption(value: 'Active', label: 'Active'),
                  SegmentOption(value: 'Upcoming', label: 'Upcoming'),
                  SegmentOption(value: 'Expired', label: 'Expired'),
                ],
                value: validity,
                onChanged: (v) => setState(() => validity = v),
              ),
              _label(context, 'SCOPE'),
              CheckboxListTile(
                value: scoped,
                onChanged: (v) => setState(() => scoped = v ?? false),
                title: const Text('Has customer or supplier'),
                subtitle: const Text('Price limited to one party'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: batch,
                onChanged: (v) => setState(() => batch = v ?? false),
                title: const Text('Has batch'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: zero,
                onChanged: (v) => setState(() => zero = v ?? false),
                title: const Text('Zero rate'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Get.back();
                        c.applyFilters({});
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Get.back();
                        c.applyFilters({
                          if (validity.isNotEmpty) 'validity': validity,
                          if (scoped) 'scoped': true,
                          if (batch) 'batch': true,
                          if (zero) 'zero': true,
                        });
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: `lib/app/modules/pricing/item_price/item_price_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/widgets/item_price_list_app_bar.dart';
import 'package:multimax/app/modules/pricing/widgets/item_price_row.dart';

/// Item Price list. Rows are navigational (`navigatesOnTap: true`).
class ItemPriceScreen extends GetView<ItemPriceController> {
  const ItemPriceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: DocTypeGuard(
        doctype: 'Item Price',
        permType: 'create',
        child: FloatingActionButton.extended(
          onPressed: () => controller.openPrice(null),
          tooltip: 'New price',
          icon: const Icon(Icons.add),
          label: const Text('New price'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
      ),
      body: RefreshIndicator(
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        onRefresh: () async {
          controller.loadPriceLists();
          await controller.fetchPrices();
        },
        child: Scrollbar(
          controller: controller.scrollController,
          child: CustomScrollView(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const ItemPriceListAppBar(),
              SliverToBoxAdapter(
                child: Obx(() => ResultCountPill(
                      count: controller.displayCount,
                      hasMore: controller.countHasMore,
                      hasActiveFilters: controller.hasActiveFilters,
                      noun: 'price',
                      icon: Icons.sell_outlined,
                    )),
              ),
              Obx(() {
                if (controller.isLoading.value && controller.prices.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (controller.prices.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: ListEmptyState(
                      hasActiveFilters: controller.hasActiveFilters,
                      emptyIcon: Icons.sell_outlined,
                      emptyTitle: 'No item prices',
                      emptyMessage:
                          'Prices added here or by Delivery Notes appear in this list.',
                      filteredTitle: 'No matching prices',
                      filteredMessage: 'Try another price list, search or filter.',
                      onClearFilters: controller.clearFilters,
                      onReload: controller.fetchPrices,
                    ),
                  );
                }
                final count = controller.prices.length;
                final hasMore = controller.hasMore.value;
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      if (i == count) {
                        return ListEndFooter(
                            hasMore: hasMore, bottomPadding: bottomInset + 80);
                      }
                      final p = controller.prices[i];
                      return ItemPriceRow(
                        key: ValueKey(p.name),
                        price: p,
                        onTap: () => controller.openPrice(p),
                      );
                    },
                    childCount: count + 1,
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 10: Page** — in `app_pages.dart` import `item_price_binding.dart` + `item_price_screen.dart` and add after the TODO_FORM page:
```dart
    GetPage(
      name: AppRoutes.ITEM_PRICE,
      page: () => const ItemPriceScreen(),
      binding: ItemPriceBinding(),
    ),
```

- [ ] **Step 11: Run tests**

Run: `flutter test test/widget/item_price_screen_test.dart`
Expected: PASS. If a `RenderFlex overflowed` appears only in tests (Ahem font inflates text), wrap the offending Row child in `Flexible`, don't shrink fonts.

- [ ] **Step 12: Commit**

```bash
git add lib/app/data/routes lib/app/modules/pricing/widgets/item_price_row.dart lib/app/modules/pricing/item_price test/widget/item_price_screen_test.dart
git commit -m "feat(pricing): Item Price list screen

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Item Price form

**Files:**
- Create: `lib/app/modules/pricing/item_price/form/item_price_form_binding.dart`
- Create: `lib/app/modules/pricing/item_price/form/item_price_form_controller.dart`
- Create: `lib/app/modules/pricing/item_price/form/item_price_form_screen.dart`
- Modify: `lib/app/data/routes/app_pages.dart` (ITEM_PRICE_FORM page)
- Test: `test/unit/item_price_form_controller_test.dart`, `test/widget/item_price_form_screen_test.dart`

**Interfaces:**
- Consumes: `ItemPriceProvider`, `ItemPrice`, `PriceListInfo`, `validateItemPrice`, `itemPriceValidity`, `pricingStatusLabel`, `frappeDate`, `displayDate`, `formatMoney`, `uomsFromItem`, `MoneyField`, `FieldErrorText`, `showOptionPickerSheet`, `ItemFormController.parseServerMessage` (existing static), `OptimisticLockingMixin`.
- Produces: `ItemPriceFormController` with `name`, `mode` (RxString), `price` (Rx<ItemPrice>), `priceLists`, `itemUoms`, `isLoading`, `isSaving`, `isDeleting`, `isDirty`, `notFound`, `moreOpen`, `saveResult`, `serverError`, `fieldErrors`, text controllers, `isEditable`, `isSellingList`, `currency`, `saveDocument()`, `performDelete()`, pickers.

- [ ] **Step 1: Write the failing controller test** — `test/unit/item_price_form_controller_test.dart`

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';

Response _res(int code, [dynamic data]) =>
    Response(requestOptions: RequestOptions(path: '/'), statusCode: code, data: data);

class _FakeProvider extends ItemPriceProvider {
  Map<String, dynamic>? lastCreate;
  Map<String, dynamic>? lastUpdate;
  Object? throwOnCreate;
  int deleteStatus = 202;

  @override
  Future<Response> getPriceLists() async => _res(200, {
        'data': [
          {'name': 'Credit Selling', 'currency': 'AED', 'selling': 1, 'buying': 0},
          {'name': 'Standard Buying', 'currency': 'AED', 'selling': 0, 'buying': 1},
          {'name': 'Standard Selling', 'currency': 'AED', 'selling': 1, 'buying': 0},
        ]
      });

  @override
  Future<Response> getItemPrice(String name) async => _res(200, {
        'data': {
          'name': name,
          'item_code': '1000001',
          'item_name': 'WALLETS COW',
          'uom': 'Nos',
          'price_list': 'Standard Selling',
          'selling': 1,
          'currency': 'AED',
          'price_list_rate': 25,
          'valid_from': '2026-04-22',
          'customer': 'Al Noor Trading',
          'modified': '2026-04-22 17:36:55',
        }
      });

  @override
  Future<Response> getItem(String itemCode) async => _res(200, {
        'data': {
          'name': itemCode,
          'item_name': 'WALLETS COW',
          'stock_uom': 'Nos',
          'has_variants': 0,
          'uoms': [
            {'uom': 'Nos'},
            {'uom': 'Box'},
          ],
        }
      });

  @override
  Future<Response> createItemPrice(Map<String, dynamic> data) async {
    lastCreate = data;
    if (throwOnCreate != null) throw throwOnCreate!;
    return _res(200, {'data': {...data, 'name': 'newhash'}});
  }

  @override
  Future<Response> updateItemPrice(String name, Map<String, dynamic> data) async {
    lastUpdate = data;
    return _res(200, {'data': data});
  }

  @override
  Future<Response> deleteItemPrice(String name) async => _res(deleteStatus);
}

class _Perms extends PermissionService {
  final _g = true.obs;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

void main() {
  late _FakeProvider provider;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<PermissionService>(_Perms());
    provider = _FakeProvider();
    Get.put<ItemPriceProvider>(provider);
  });

  tearDown(Get.reset);

  Future<ItemPriceFormController> newForm() async {
    final c = ItemPriceFormController()..mode.value = 'new';
    Get.put(c);
    await pumpEventQueue();
    return c;
  }

  Future<ItemPriceFormController> editForm() async {
    final c = ItemPriceFormController()
      ..name = 'hash1'
      ..mode.value = 'edit';
    Get.put(c);
    await pumpEventQueue();
    return c;
  }

  test('new: defaults to Standard Selling, today, dirty', () async {
    final c = await newForm();
    expect(c.price.value.priceList, 'Standard Selling');
    expect(c.price.value.validFrom, frappeDate(DateTime.now()));
    expect(c.isDirty.value, isTrue);
    expect(c.isLoading.value, isFalse);
  });

  test('new: save is blocked by client validation', () async {
    final c = await newForm();
    await c.saveDocument();
    expect(provider.lastCreate, isNull);
    expect(c.fieldErrors['item_code'], 'Item is required');
  });

  test('applyItem loads units and defaults to the stock uom', () async {
    final c = await newForm();
    await c.applyItem('1000001');
    expect(c.itemUoms, ['Nos', 'Box']);
    expect(c.price.value.uom, 'Nos');
    expect(c.price.value.itemName, 'WALLETS COW');
  });

  test('new: save sends only sendable keys and flips to edit', () async {
    final c = await newForm();
    await c.applyItem('1000001');
    c.rateController.text = '30';
    await c.saveDocument();
    expect(provider.lastCreate!.keys.toSet(), {
      'item_code', 'uom', 'packing_unit', 'price_list', 'customer',
      'supplier', 'batch_no', 'price_list_rate', 'valid_from', 'valid_upto',
      'lead_time_days', 'note',
    });
    expect(provider.lastCreate!['price_list_rate'], 30.0);
    expect(c.mode.value, 'edit');
    expect(c.name, 'newhash');
  });

  test('server error lands in serverError (verbatim, tags stripped)', () async {
    final c = await newForm();
    await c.applyItem('1000001');
    provider.throwOnCreate = DioException(
      requestOptions: RequestOptions(path: '/'),
      response: _res(417, {
        '_server_messages': jsonEncode([
          jsonEncode({
            'message':
                'Item Price appears multiple times based on <b>Price List</b>, Supplier/Customer, Currency, Item, Batch, UOM, Qty, and Dates.'
          })
        ])
      }),
    );
    await c.saveDocument();
    expect(c.serverError.value,
        'Item Price appears multiple times based on Price List, Supplier/Customer, Currency, Item, Batch, UOM, Qty, and Dates.');
  });

  test('edit: loads, not dirty, update sends modified', () async {
    final c = await editForm();
    expect(c.price.value.customer, 'Al Noor Trading');
    expect(c.rateController.text, '25.00');
    expect(c.isDirty.value, isFalse);
    c.rateController.text = '27.50';
    expect(c.isDirty.value, isTrue);
    await c.saveDocument();
    expect(provider.lastUpdate!['modified'], '2026-04-22 17:36:55');
    expect(provider.lastUpdate!['price_list_rate'], 27.5);
  });

  test('switching to a buying list clears the customer', () async {
    final c = await editForm();
    c.setPriceList('Standard Buying');
    expect(c.price.value.customer, isNull);
    expect(c.price.value.buying, isTrue);
    expect(c.isSellingList, isFalse);
  });

  test('performDelete accepts 202', () async {
    final c = await editForm();
    expect(await c.performDelete(), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/unit/item_price_form_controller_test.dart`
Expected: FAIL — controller missing.

- [ ] **Step 3: `lib/app/modules/pricing/item_price/form/item_price_form_controller.dart`**

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';

/// Item Price form. Modes from `Get.arguments`: `new` (optionally with
/// `item_code` prefill from the Item form), `edit`, `view`. Users without
/// write access get a read-only form regardless of mode.
class ItemPriceFormController extends GetxController with OptimisticLockingMixin {
  final ItemPriceProvider _provider = Get.find<ItemPriceProvider>();

  String name = (Get.arguments is Map ? Get.arguments['name'] : null) ?? '';
  final RxString mode =
      RxString((Get.arguments is Map ? Get.arguments['mode'] : null) ?? 'view');
  final String _prefillItem =
      (Get.arguments is Map ? Get.arguments['item_code'] : null) ?? '';

  final price = ItemPrice().obs;
  final priceLists = <PriceListInfo>[].obs;
  final itemUoms = <String>[].obs;

  final isLoading = true.obs;
  final isSaving = false.obs;
  final isDeleting = false.obs;
  final isDirty = false.obs;
  final notFound = false.obs;
  final moreOpen = false.obs;
  final saveResult = SaveResult.idle.obs;
  final serverError = ''.obs;
  final fieldErrors = <String, String>{}.obs;

  final rateController = TextEditingController();
  final packingUnitController = TextEditingController();
  final leadTimeController = TextEditingController();
  final noteController = TextEditingController();

  bool _seeding = false;
  String _originalJson = '';

  bool get canWrite =>
      Get.find<PermissionService>().hasAccess('Item Price',
          permType: mode.value == 'new' ? 'create' : 'write') ==
      true;

  bool get isEditable => mode.value != 'view' && canWrite;

  PriceListInfo? get selectedList =>
      priceLists.where((l) => l.name == price.value.priceList).firstOrNull;

  bool get isSellingList => selectedList?.selling ?? price.value.selling;

  String get currency => selectedList?.currency ?? price.value.currency;

  @override
  void onInit() {
    super.onInit();
    for (final c in [
      rateController,
      packingUnitController,
      leadTimeController,
      noteController,
    ]) {
      c.addListener(_syncText);
    }
    _start();
  }

  @override
  void onClose() {
    rateController.dispose();
    packingUnitController.dispose();
    leadTimeController.dispose();
    noteController.dispose();
    super.onClose();
  }

  Future<void> _start() async {
    await _loadPriceLists();
    if (mode.value == 'new') {
      await _initNew();
    } else {
      await fetchDocument();
    }
  }

  Future<void> _loadPriceLists() async {
    try {
      final res = await _provider.getPriceLists();
      priceLists.assignAll([
        for (final e in (res.data['data'] as List?) ?? const [])
          PriceListInfo.fromJson(Map<String, dynamic>.from(e as Map)),
      ]);
    } catch (_) {}
  }

  Future<void> _initNew() async {
    // 'Standard Selling' is the list ERPNext's setup wizard creates.
    final list = priceLists.where((l) => l.name == 'Standard Selling').firstOrNull ??
        priceLists.firstOrNull;
    price.value = ItemPrice(
      priceList: list?.name ?? '',
      selling: list?.selling ?? false,
      buying: list?.buying ?? false,
      currency: list?.currency ?? '',
      validFrom: frappeDate(DateTime.now()),
    );
    _seed();
    isDirty.value = true;
    isLoading.value = false;
    if (_prefillItem.isNotEmpty) await applyItem(_prefillItem);
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getItemPrice(name);
      price.value = ItemPrice.fromJson(
          Map<String, dynamic>.from(res.data['data'] as Map));
      _seed();
      _originalJson = jsonEncode(price.value.toJson());
      isDirty.value = false;
      notFound.value = false;
      serverError.value = '';
      fieldErrors.clear();
      _loadItemUoms(price.value.itemCode);
    } catch (_) {
      notFound.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Future<void> reloadDocument() => fetchDocument();

  void _seed() {
    _seeding = true;
    final p = price.value;
    rateController.text = p.rate.toStringAsFixed(2);
    packingUnitController.text = p.packingUnit == 0 ? '' : '${p.packingUnit}';
    leadTimeController.text = p.leadTimeDays == 0 ? '' : '${p.leadTimeDays}';
    noteController.text = p.note ?? '';
    _seeding = false;
  }

  void _syncText() {
    if (_seeding) return;
    final p = price.value;
    p.rate = double.tryParse(rateController.text.replaceAll(',', '')) ?? 0;
    p.packingUnit = int.tryParse(packingUnitController.text) ?? 0;
    p.leadTimeDays = int.tryParse(leadTimeController.text) ?? 0;
    p.note = noteController.text.isEmpty ? null : noteController.text;
    price.refresh();
    _checkDirty();
  }

  void _checkDirty() {
    if (mode.value == 'new') {
      isDirty.value = true;
      return;
    }
    isDirty.value = jsonEncode(price.value.toJson()) != _originalJson;
  }

  void _edit(void Function(ItemPrice p) change) {
    if (!isEditable) return;
    price.update((p) => change(p!));
    _checkDirty();
  }

  // ── Item + units ─────────────────────────────────────────────────────

  Future<void> applyItem(String code) async {
    try {
      final res = await _provider.getItem(code);
      final d = Map<String, dynamic>.from(res.data['data'] as Map);
      if (pricingBool(d['has_variants'])) {
        fieldErrors['item_code'] =
            'Item Price cannot be created for the template item $code';
        return;
      }
      final uoms = uomsFromItem(d);
      itemUoms.assignAll(uoms);
      price.update((p) {
        p!.itemCode = code;
        p.itemName = (d['item_name'] ?? code).toString();
        p.brand = pricingLink(d['brand']);
        if (!uoms.contains(p.uom)) {
          p.uom = pricingLink(d['stock_uom']) ?? (uoms.isEmpty ? '' : uoms.first);
        }
      });
      fieldErrors.remove('item_code');
      _checkDirty();
    } catch (_) {
      GlobalSnackbar.error(message: 'Could not load item $code');
    }
  }

  Future<void> _loadItemUoms(String code) async {
    if (code.isEmpty) return;
    try {
      final res = await _provider.getItem(code);
      itemUoms.assignAll(
          uomsFromItem(Map<String, dynamic>.from(res.data['data'] as Map)));
    } catch (_) {}
  }

  Future<void> pickItem() async {
    if (!isEditable || mode.value != 'new') return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Item',
        title: 'Select item',
        columns: [
          DocTypePickerColumn(fieldname: 'name', label: 'Item code', isPrimary: true),
          DocTypePickerColumn(fieldname: 'item_name', label: 'Name', isSecondary: true),
        ],
        filters: const [
          ['Item', 'has_variants', '=', 0],
          ['Item', 'disabled', '=', 0],
        ],
        enableBarcodeScan: true,
      ),
    );
    if (row != null) await applyItem(row['name'] as String);
  }

  void pickUom(BuildContext context) {
    if (!isEditable || itemUoms.isEmpty) return;
    showOptionPickerSheet(
      context,
      title: 'Unit',
      options: itemUoms.toList(),
      selected: price.value.uom,
      onSelected: (u) => _edit((p) => p.uom = u),
    );
  }

  // ── Price list / party / batch / dates ───────────────────────────────

  void pickPriceList(BuildContext context) {
    if (!isEditable) return;
    showOptionPickerSheet(
      context,
      title: 'Price list',
      options: [for (final l in priceLists) l.name],
      selected: price.value.priceList,
      onSelected: setPriceList,
    );
  }

  /// Mirrors item_price.py: the list decides selling/buying/currency; a
  /// selling list drops the supplier and a buying list drops the customer.
  void setPriceList(String listName) {
    final l = priceLists.where((x) => x.name == listName).firstOrNull;
    if (l == null) return;
    _edit((p) {
      p.priceList = l.name;
      p.selling = l.selling;
      p.buying = l.buying;
      p.currency = l.currency;
      if (!l.selling) p.customer = null;
      if (!l.buying) p.supplier = null;
    });
  }

  Future<void> pickParty() async {
    if (!isEditable) return;
    final doctype = isSellingList ? 'Customer' : 'Supplier';
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: doctype,
        title: 'Select ${doctype.toLowerCase()}',
        columns: [DocTypePickerColumn(fieldname: 'name', label: doctype, isPrimary: true)],
      ),
    );
    if (row == null) return;
    final v = row['name'] as String;
    _edit((p) => doctype == 'Customer' ? p.customer = v : p.supplier = v);
  }

  void clearParty() => _edit((p) {
        p.customer = null;
        p.supplier = null;
      });

  Future<void> pickBatch() async {
    final code = price.value.itemCode;
    if (!isEditable || code.isEmpty) return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Batch',
        title: 'Select batch',
        columns: [DocTypePickerColumn(fieldname: 'name', label: 'Batch', isPrimary: true)],
        filters: [
          ['Batch', 'item', '=', code]
        ],
      ),
    );
    if (row != null) _edit((p) => p.batchNo = row['name'] as String);
  }

  void clearBatch() => _edit((p) => p.batchNo = null);

  Future<void> pickDate(BuildContext context, String field) async {
    if (!isEditable) return;
    final current = parseFrappeDate(
        field == 'valid_from' ? price.value.validFrom : price.value.validUpto);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _edit((p) => field == 'valid_from'
        ? p.validFrom = frappeDate(picked)
        : p.validUpto = frappeDate(picked));
  }

  void clearValidUpto() => _edit((p) => p.validUpto = null);

  // ── Save / delete / discard ──────────────────────────────────────────

  Future<void> saveDocument() async {
    if (isSaving.value || !isEditable) return;
    final errors = validateItemPrice(price.value);
    final templateError = fieldErrors['item_code'];
    if (templateError != null && errors['item_code'] == null) {
      errors['item_code'] = templateError;
    }
    fieldErrors.assignAll(errors);
    if (errors.isNotEmpty) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: errors.values.first);
      return;
    }
    if (checkStaleAndBlock()) return;

    isSaving.value = true;
    serverError.value = '';
    final data = price.value.toJson();
    if (mode.value != 'new') data['modified'] = price.value.modified;

    try {
      final res = mode.value == 'new'
          ? await _provider.createItemPrice(data)
          : await _provider.updateItemPrice(name, data);
      final saved = res.data is Map ? res.data['data'] : null;
      if (saved is Map && saved['name'] != null) name = saved['name'].toString();
      mode.value = 'edit';
      await fetchDocument();
      saveResult.value = SaveResult.success;
      GlobalSnackbar.success(message: 'Item price saved');
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      saveResult.value = SaveResult.error;
      serverError.value = ItemFormController.parseServerMessage(e.response?.data);
    } catch (e) {
      saveResult.value = SaveResult.error;
      serverError.value = e.toString();
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(onDiscard: () {
      isDirty.value = false;
      Get.back();
    });
  }

  Future<void> deleteDocument() async {
    if (isDeleting.value) return;
    final p = price.value;
    final confirmed = await GlobalDialog.confirm(
      title: 'Delete this price?',
      message: '${p.itemName} · ${p.priceList} · '
          '${formatMoney(p.rate, p.currency)} / ${p.uom}. Delivery Notes already '
          'saved keep their rate; new ones will find no price.',
      confirmText: 'Delete',
      confirmColor: AppColors.red700,
      icon: Icons.delete_outline,
    );
    if (confirmed != true) return;
    if (await performDelete()) Get.back();
  }

  /// Network half of [deleteDocument], testable without the dialog.
  Future<bool> performDelete() async {
    if (isDeleting.value) return false;
    isDeleting.value = true;
    try {
      final res = await _provider.deleteItemPrice(name);
      final ok = res.statusCode == 200 || res.statusCode == 202 || res.statusCode == 204;
      if (ok) {
        isDirty.value = false;
        GlobalSnackbar.success(message: 'Item price deleted');
      } else {
        GlobalSnackbar.error(message: 'Failed to delete item price');
      }
      return ok;
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to delete item price: $e');
      return false;
    } finally {
      isDeleting.value = false;
    }
  }
}
```

- [ ] **Step 4: Run controller test**

Run: `flutter test test/unit/item_price_form_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: `lib/app/modules/pricing/item_price/form/item_price_form_binding.dart`**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';

class ItemPriceFormBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ItemPriceProvider>()) {
      Get.lazyPut<ItemPriceProvider>(() => ItemPriceProvider(), fenix: true);
    }
    Get.lazyPut<ItemPriceFormController>(() => ItemPriceFormController());
  }
}
```

- [ ] **Step 6: Write the failing widget test** — `test/widget/item_price_form_screen_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_screen.dart';

Response _res(dynamic data) =>
    Response(requestOptions: RequestOptions(path: '/'), statusCode: 200, data: data);

class _FakeProvider extends ItemPriceProvider {
  _FakeProvider(this.listName, {this.selling = true});
  final String listName;
  final bool selling;

  @override
  Future<Response> getPriceLists() async => _res({
        'data': [
          {'name': 'Standard Selling', 'currency': 'AED', 'selling': 1, 'buying': 0},
          {'name': 'Standard Buying', 'currency': 'AED', 'selling': 0, 'buying': 1},
        ]
      });

  @override
  Future<Response> getItemPrice(String name) async => _res({
        'data': {
          'name': name,
          'item_code': '1000001',
          'item_name': 'WALLETS COW',
          'uom': 'Nos',
          'price_list': listName,
          'selling': selling ? 1 : 0,
          'buying': selling ? 0 : 1,
          'currency': 'AED',
          'price_list_rate': 25,
          'valid_from': '2026-04-22',
          'modified': 'x',
        }
      });

  @override
  Future<Response> getItem(String itemCode) async => _res({
        'data': {'name': itemCode, 'stock_uom': 'Nos', 'uoms': []}
      });
}

class _Perms extends PermissionService {
  _Perms(bool v) : _g = v.obs;
  final RxBool _g;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  tearDown(Get.reset);

  Future<ItemPriceFormController> pump(
    WidgetTester tester, {
    String listName = 'Standard Selling',
    bool selling = true,
    bool canWrite = true,
    Brightness brightness = Brightness.light,
  }) async {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<PermissionService>(_Perms(canWrite));
    Get.put<ItemPriceProvider>(_FakeProvider(listName, selling: selling));
    final c = Get.put(ItemPriceFormController()
      ..name = 'hash1'
      ..mode.value = 'edit');
    final theme = ThemeData(brightness: brightness, useMaterial3: true);
    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      darkTheme: theme,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const ItemPriceFormScreen(),
    ));
    await tester.pump();
    await tester.pump();
    return c;
  }

  testWidgets('edit mode: title, rate, Save + Delete, More options toggles',
      (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('WALLETS COW'), findsWidgets);
    expect(find.text('25.00'), findsOneWidget);
    expect(find.byTooltip('Save'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.text('Customer'), findsNothing);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Supplier'), findsNothing);
  });

  testWidgets('buying list shows Supplier, not Customer', (tester) async {
    await pump(tester, listName: 'Standard Buying', selling: false);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('Customer'), findsNothing);
  });

  testWidgets('read-only user: no Save/Delete, read-only note', (tester) async {
    await pump(tester, canWrite: false);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.text('Read-only · you can view prices but not change them'),
        findsOneWidget);
  });

  testWidgets('server error banner shows the message', (tester) async {
    final c = await pump(tester);
    c.serverError.value = 'Item Price appears multiple times';
    await tester.pumpAndSettle();
    expect(find.textContaining('Item Price appears multiple times'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('25.00'), findsOneWidget);
  });
}
```

Note: if `DocTypeFormHeader` hides Save when `canSave` is false, change the first test to make the form dirty first (`c.rateController.text = '26'; await tester.pump();`) before asserting the Save tooltip — check `doctype_form_header.dart` (~line 430) for the exact rule and keep the assertion meaningful.

- [ ] **Step 7: Run to verify failure**

Run: `flutter test test/widget/item_price_form_screen_test.dart`
Expected: FAIL — screen missing.

- [ ] **Step 8: `lib/app/modules/pricing/item_price/form/item_price_form_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_detail_row.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/widgets/money_field.dart';

class ItemPriceFormScreen extends GetView<ItemPriceFormController> {
  const ItemPriceFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = controller.price.value;
      final isNew = controller.mode.value == 'new';
      final editable = controller.isEditable;
      final dirty = controller.isDirty.value;
      final loading = controller.isLoading.value;
      final status = dirty
          ? 'Not Saved'
          : pricingStatusLabel(
              disabled: false, validity: itemPriceValidity(p, DateTime.now()));
      final title = p.itemName.isNotEmpty
          ? p.itemName
          : (isNew ? 'New item price' : 'Item Price');

      return PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) await controller.confirmDiscard();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: NestedScrollView(
            headerSliverBuilder: (ctx, _) => [
              DocTypeFormHeader(
                title: title,
                docType: 'Item Price',
                statusLabel: loading ? null : status,
                canSave: editable && dirty,
                isSaving: controller.isSaving.value,
                saveResult: controller.saveResult.value,
                onSave: editable ? controller.saveDocument : null,
                onReload: isNew ? null : controller.reloadDocument,
                extraActions: [
                  if (!isNew && !loading && !controller.notFound.value)
                    // Item Price delete roles == write roles (v15 DocPerm);
                    // PermissionService has no real delete check.
                    DocTypeGuard(
                      doctype: 'Item Price',
                      permType: 'write',
                      child: AsyncIconButton(
                        busy: controller.isDeleting,
                        onPressed: controller.deleteDocument,
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
            ],
            body: loading
                ? const Center(child: CircularProgressIndicator())
                : controller.notFound.value
                    ? const Center(
                        child: FormEmptyState(
                          icon: Icons.search_off,
                          message: 'Item price not found or not accessible.',
                        ),
                      )
                    : _body(context, p, isNew, editable),
          ),
        ),
      );
    });
  }

  Widget _body(BuildContext context, ItemPrice p, bool isNew, bool editable) {
    final s = context.scheme;
    final e = controller.fieldErrors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 80 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineBanner(
            visible: controller.serverError.value.isNotEmpty,
            type: BannerType.error,
            message: "Couldn't save\n${controller.serverError.value}",
          ),
          if (controller.serverError.value.isNotEmpty) const SizedBox(height: 12),
          DocSectionCard(
            title: 'Price',
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              DocPickerField(
                label: 'Item',
                icon: Icons.inventory_2_outlined,
                value: p.itemCode.isEmpty ? null : '${p.itemCode} · ${p.itemName}',
                placeholder: 'Select item',
                trailingIcon: isNew ? Icons.search : Icons.lock_outline,
                onTap: editable && isNew ? controller.pickItem : null,
              ),
              FieldErrorText(e['item_code']),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Price list',
                icon: Icons.sell_outlined,
                value: p.priceList.isEmpty ? null : p.priceList,
                helperText: p.priceList.isEmpty
                    ? null
                    : (controller.isSellingList ? 'Selling' : 'Buying'),
                onTap: editable ? () => controller.pickPriceList(context) : null,
              ),
              FieldErrorText(e['price_list']),
              const SizedBox(height: 12),
              MoneyField(
                label: 'Rate',
                controller: controller.rateController,
                prefix: controller.currency.isEmpty ? null : controller.currency,
                suffix: p.uom.isEmpty ? null : '/ ${p.uom}',
                readOnly: !editable,
                errorText: e['price_list_rate'],
              ),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Unit',
                icon: Icons.straighten,
                value: p.uom.isEmpty ? null : p.uom,
                helperText: isNew
                    ? "Item's stock unit · only the item's units are offered"
                    : null,
                onTap: editable && controller.itemUoms.isNotEmpty
                    ? () => controller.pickUom(context)
                    : null,
              ),
              FieldErrorText(e['uom']),
            ],
          ),
          DocSectionCard(
            title: 'Validity',
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: DocPickerField(
                      label: 'Valid from',
                      icon: Icons.event_outlined,
                      value: p.validFrom == null ? null : displayDate(p.validFrom),
                      trailingIcon: Icons.edit_calendar_outlined,
                      onTap: editable
                          ? () => controller.pickDate(context, 'valid_from')
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DocPickerField(
                      label: 'Valid upto',
                      icon: Icons.event_outlined,
                      value: p.validUpto == null ? null : displayDate(p.validUpto),
                      placeholder: 'No end date',
                      trailingIcon: Icons.edit_calendar_outlined,
                      onTap: editable
                          ? () => controller.pickDate(context, 'valid_upto')
                          : null,
                    ),
                  ),
                ],
              ),
              FieldErrorText(e['valid_upto']),
              if (editable && p.validUpto != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: controller.clearValidUpto,
                    child: const Text('No end date'),
                  ),
                ),
            ],
          ),
          DocSectionCard(
            title: 'More options',
            margin: EdgeInsets.zero,
            headerAction: IconButton(
              tooltip: controller.moreOpen.value ? 'Collapse' : 'Expand',
              icon: Icon(controller.moreOpen.value
                  ? Icons.expand_less
                  : Icons.expand_more),
              onPressed: controller.moreOpen.toggle,
            ),
            children: controller.moreOpen.value
                ? _moreOptions(context, p, editable)
                : [
                    Text(_moreSummary(p, editable),
                        style: TextStyle(fontSize: 12, color: s.textMuted)),
                  ],
          ),
          if (!editable)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Read-only · you can view prices but not change them',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: s.textSubtle),
              ),
            ),
        ],
      ),
    );
  }

  String _moreSummary(ItemPrice p, bool editable) {
    final set = [
      if (p.customer != null) 'Customer ${p.customer}',
      if (p.supplier != null) 'Supplier ${p.supplier}',
      if (p.batchNo != null) 'Batch ${p.batchNo}',
      if (p.leadTimeDays > 0) '${p.leadTimeDays} days lead time',
      if (p.packingUnit > 0) 'Packing unit ${p.packingUnit}',
    ];
    if (set.isNotEmpty) return set.join(' · ');
    return editable ? 'Customer, batch, lead time…' : 'None set';
  }

  List<Widget> _moreOptions(BuildContext context, ItemPrice p, bool editable) {
    final selling = controller.isSellingList;
    final party = selling ? p.customer : p.supplier;
    return [
      DocPickerField(
        label: selling ? 'Customer' : 'Supplier',
        icon: selling ? Icons.person_outline : Icons.local_shipping_outlined,
        value: party,
        placeholder: selling ? 'Any customer' : 'Any supplier',
        helperText: selling
            ? 'Only for selling price lists'
            : 'Only for buying price lists',
        trailingIcon: Icons.search,
        onTap: editable ? controller.pickParty : null,
      ),
      if (editable && party != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: controller.clearParty, child: const Text('Clear')),
        ),
      const SizedBox(height: 12),
      DocPickerField(
        label: 'Batch',
        icon: Icons.tag,
        value: p.batchNo,
        placeholder: 'Any batch',
        onTap: editable && p.itemCode.isNotEmpty ? controller.pickBatch : null,
      ),
      if (editable && p.batchNo != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: controller.clearBatch, child: const Text('Clear')),
        ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
              child: _intField(
                  controller.leadTimeController, 'Lead time (days)', editable)),
          const SizedBox(width: 10),
          Expanded(
              child: _intField(
                  controller.packingUnitController, 'Packing unit', editable)),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: controller.noteController,
        readOnly: !editable,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Note',
          border: OutlineInputBorder(),
        ),
      ),
      if (p.brand != null) ...[
        const SizedBox(height: 12),
        DocDetailRow(label: 'Brand', value: p.brand!),
      ],
    ];
  }

  Widget _intField(TextEditingController c, String label, bool editable) =>
      TextField(
        controller: c,
        readOnly: !editable,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          hintText: '0',
          border: const OutlineInputBorder(),
        ),
      );
}
```

- [ ] **Step 9: Page** — in `app_pages.dart` import the form binding + screen and add after the ITEM_PRICE page:
```dart
    GetPage(
      name: AppRoutes.ITEM_PRICE_FORM,
      page: () => const ItemPriceFormScreen(),
      binding: ItemPriceFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
```

- [ ] **Step 10: Run tests**

Run: `flutter test test/unit/item_price_form_controller_test.dart test/widget/item_price_form_screen_test.dart`
Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add lib/app/modules/pricing/item_price/form lib/app/data/routes/app_pages.dart test/unit/item_price_form_controller_test.dart test/widget/item_price_form_screen_test.dart
git commit -m "feat(pricing): Item Price form

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Pricing Rule list screen

**Files:**
- Create: `lib/app/modules/pricing/widgets/pricing_rule_row.dart`
- Create: `lib/app/modules/pricing/pricing_rule/pricing_rule_binding.dart`
- Create: `lib/app/modules/pricing/pricing_rule/pricing_rule_controller.dart`
- Create: `lib/app/modules/pricing/pricing_rule/pricing_rule_screen.dart`
- Create: `lib/app/modules/pricing/pricing_rule/widgets/pricing_rule_list_app_bar.dart`
- Modify: `lib/app/data/routes/app_pages.dart` (PRICING_RULE page)
- Test: `test/widget/pricing_rule_screen_test.dart`

**Interfaces:**
- Consumes: `PricingRuleProvider` (Task 4), `buildPricingRuleQuery`, `describePricingRule`, `pricingRuleStatus`, `pricingRuleDates`, `frappeDate` (Task 2), `PriorityBadge`, `sideTag` (Task 4), `GenericDocumentCard(trailing:, body:)` (Task 3).
- Produces: `PricingRuleRow({required PricingRule rule, required VoidCallback onTap, DateTime? today})`, `IconData pricingRuleIcon(PricingRule)` (reused by Task 9); `PricingRuleController` with `openRule(PricingRule?)`.

- [ ] **Step 1: Write the failing widget test** — `test/widget/pricing_rule_screen_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_screen.dart';

class _FakeProvider extends PricingRuleProvider {
  _FakeProvider(this.rows);
  final List<Map<String, dynamic>> rows;

  @override
  Future<Response> getRules({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async =>
      Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: {'data': rows});

  @override
  Future<int> count(List<List<dynamic>> filters) async => 0;

  @override
  Future<void> attachTargets(List<PricingRule> rules) async {
    for (final r in rules) {
      r.targets = [PricingRuleTarget(value: 'Belts')];
    }
  }
}

class _Perms extends PermissionService {
  _Perms(bool? v) : _g = Rx<bool?>(v);
  final Rx<bool?> _g;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester,
      {required List<Map<String, dynamic>> rows, bool? grant = true}) async {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(AuthenticationController());
    Get.put<PermissionService>(_Perms(grant));
    Get.put<PricingRuleProvider>(_FakeProvider(rows));
    Get.put(PricingRuleController());
    await tester.pumpWidget(const GetMaterialApp(home: PricingRuleScreen()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('zero rules: explanatory empty state with create CTA',
      (tester) async {
    await pump(tester, rows: const []);
    expect(tester.takeException(), isNull);
    expect(find.text('No pricing rules yet'), findsOneWidget);
    expect(find.text('New pricing rule'), findsOneWidget);
  });

  testWidgets('empty state hides the CTA without create permission',
      (tester) async {
    await pump(tester, rows: const [], grant: false);
    expect(find.text('No pricing rules yet'), findsOneWidget);
    expect(find.text('New pricing rule'), findsNothing);
  });

  testWidgets('rows show title, summary sentence, status and priority badge',
      (tester) async {
    await pump(tester, rows: [
      {
        'name': 'PRLE-0001',
        'title': 'Belts clearance',
        'disable': 0,
        'apply_on': 'Item Group',
        'price_or_product_discount': 'Price',
        'selling': 1,
        'rate_or_discount': 'Discount Amount',
        'discount_amount': 5,
        'currency': 'AED',
        'valid_upto': '2026-08-31',
        'has_priority': 1,
        'priority': '3',
      },
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Belts clearance'), findsOneWidget);
    expect(find.text('AED 5.00 off for everyone on item group Belts, until 31 Aug 2026'),
        findsOneWidget);
    expect(find.text('Expired'), findsWidgets);
    expect(find.text('P3'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/widget/pricing_rule_screen_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: `lib/app/modules/pricing/widgets/pricing_rule_row.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/widgets/scope_tag.dart';

IconData pricingRuleIcon(PricingRule r) {
  if (r.priceOrProductDiscount == 'Product') return Icons.card_giftcard_outlined;
  if (r.rateOrDiscount == 'Discount Percentage') return Icons.percent;
  return Icons.sell_outlined;
}

/// Pricing Rule list row (DESIGN_SPEC §C). Disabled rules render at 60 %.
class PricingRuleRow extends StatelessWidget {
  const PricingRuleRow({
    super.key,
    required this.rule,
    required this.onTap,
    this.today,
  });

  final PricingRule rule;
  final VoidCallback onTap;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final card = GenericDocumentCard(
      title: rule.title.isEmpty ? rule.name : rule.title,
      subtitle: '',
      isExpanded: false,
      navigatesOnTap: true,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: rule.disable
              ? s.subtle
              : Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.fg),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(pricingRuleIcon(rule),
            size: 18, color: rule.disable ? s.textSubtle : s.primary),
      ),
      trailing: StatusPill(status: pricingRuleStatus(rule, today ?? DateTime.now())),
      body: Text(
        describePricingRule(rule),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, height: 1.4, color: s.textMuted),
      ),
      stats: [
        if (rule.hasPriority && rule.priority.isNotEmpty)
          PriorityBadge(priority: rule.priority),
        sideTag(context, selling: rule.selling, buying: rule.buying),
        GenericDocumentCard.buildIconStat(
            context, Icons.event_outlined, pricingRuleDates(rule)),
      ],
    );
    return rule.disable ? Opacity(opacity: 0.6, child: card) : card;
  }
}
```

- [ ] **Step 4: `lib/app/modules/pricing/pricing_rule/pricing_rule_controller.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';

class PricingRuleController extends GetxController {
  final PricingRuleProvider _provider = Get.find<PricingRuleProvider>();

  final scrollController = ScrollController();

  final rules = <PricingRule>[].obs;
  final isLoading = true.obs;
  final isFetchingMore = false.obs;
  final hasMore = true.obs;

  /// '' | Active | Upcoming | Expired | Disabled
  final status = ''.obs;

  /// For DocTypeListHeader: {'side': 'Selling' | 'Buying'}.
  final activeFilters = <String, dynamic>{}.obs;
  final searchQuery = ''.obs;

  /// Keyed by status ('' = all). Active is derived (all − others).
  final statusCounts = <String, int>{}.obs;

  static const List<String> statuses = ['Active', 'Upcoming', 'Expired', 'Disabled'];
  static const int _limit = 20;
  int _page = 0;
  Timer? _debounce;

  String get side => (activeFilters['side'] as String?) ?? '';

  bool get hasActiveFilters =>
      status.value.isNotEmpty || side.isNotEmpty || searchQuery.value.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
  }

  @override
  void onReady() {
    super.onReady();
    loadCounts();
    fetchRules();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    scrollController.dispose();
    super.onClose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final p = scrollController.position;
    if (p.pixels >= p.maxScrollExtent * 0.9 &&
        hasMore.value &&
        !isFetchingMore.value &&
        !isLoading.value) {
      fetchRules(isLoadMore: true);
    }
  }

  Future<void> loadCounts() async {
    const dt = 'Pricing Rule';
    final t = frappeDate(DateTime.now());
    try {
      final c = await Future.wait([
        _provider.count(const []),
        _provider.count([
          [dt, 'disable', '=', 1]
        ]),
        _provider.count([
          [dt, 'disable', '=', 0],
          [dt, 'valid_from', '>', t],
        ]),
        _provider.count([
          [dt, 'disable', '=', 0],
          [dt, 'valid_upto', 'is', 'set'],
          [dt, 'valid_upto', '<', t],
        ]),
      ]);
      final all = c[0], disabled = c[1], upcoming = c[2], expired = c[3];
      statusCounts.assignAll({
        '': all,
        'Active': (all - disabled - upcoming - expired).clamp(0, all).toInt(),
        'Upcoming': upcoming,
        'Expired': expired,
        'Disabled': disabled,
      });
    } catch (_) {}
  }

  Future<void> fetchRules({bool isLoadMore = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      _page = 0;
      hasMore.value = true;
    }
    try {
      final q = buildPricingRuleQuery(
        status: status.value,
        side: side,
        search: searchQuery.value,
        today: DateTime.now(),
      );
      final res = await _provider.getRules(
        limit: _limit,
        limitStart: _page * _limit,
        filters: q.filters,
        orFilters: q.orFilters,
      );
      final page = [
        for (final e in (res.data['data'] as List?) ?? const [])
          PricingRule.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      await _provider.attachTargets(page);
      hasMore.value = page.length == _limit;
      if (isLoadMore) {
        rules.addAll(page);
      } else {
        rules.assignAll(page);
      }
      _page++;
    } catch (_) {
      GlobalSnackbar.error(message: 'Failed to load pricing rules');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  void selectStatus(String value) {
    if (status.value == value) return;
    status.value = value;
    fetchRules();
  }

  void setSide(String value) {
    if (value.isEmpty) {
      activeFilters.remove('side');
    } else {
      activeFilters['side'] = value;
    }
    fetchRules();
  }

  void onSearchChanged(String query) {
    searchQuery.value = query;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), fetchRules);
  }

  void clearFilters() {
    status.value = '';
    activeFilters.clear();
    searchQuery.value = '';
    fetchRules();
  }

  /// Rules are few; refetch the page and counts after the form closes.
  Future<void> openRule(PricingRule? rule) async {
    await Get.toNamed(
      AppRoutes.PRICING_RULE_FORM,
      arguments: {'name': rule?.name ?? '', 'mode': rule == null ? 'new' : 'edit'},
    );
    loadCounts();
    fetchRules();
  }
}
```

- [ ] **Step 5: `lib/app/modules/pricing/pricing_rule/pricing_rule_binding.dart`**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';

class PricingRuleBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<PricingRuleProvider>()) {
      Get.lazyPut<PricingRuleProvider>(() => PricingRuleProvider(), fenix: true);
    }
    Get.lazyPut<PricingRuleController>(() => PricingRuleController());
  }
}
```

- [ ] **Step 6: `lib/app/modules/pricing/pricing_rule/widgets/pricing_rule_list_app_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';

class PricingRuleListAppBar extends StatelessWidget {
  const PricingRuleListAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<PricingRuleController>();
    return DocTypeListHeader(
      title: 'Pricing Rule',
      automaticallyImplyLeading: false,
      searchQuery: c.searchQuery,
      onSearchChanged: c.onSearchChanged,
      onSearchClear: () => c.onSearchChanged(''),
      activeFilters: c.activeFilters,
      onFilterTap: () => showOptionPickerSheet(
        context,
        title: 'Side',
        options: const ['All sides', 'Selling', 'Buying'],
        selected: c.side.isEmpty ? 'All sides' : c.side,
        onSelected: (v) => c.setSide(v == 'All sides' ? '' : v),
      ),
      filterChipsBuilder: (_) => [
        if (c.side.isNotEmpty)
          FilterChipWidget(
            icon: Icons.storefront_outlined,
            label: c.side,
            onDeleted: () => c.setSide(''),
          ),
      ],
      onClearAllFilters: c.clearFilters,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Obx(
          () => ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            children: [
              _chip(c, '', 'All'),
              for (final s in PricingRuleController.statuses) _chip(c, s, s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(PricingRuleController c, String value, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SelectableFilterChip(
          label: label,
          count: c.statusCounts[value],
          dotColor: value.isEmpty ? null : StatusPill.dotColorForStatus(value),
          selected: c.status.value == value,
          onSelected: (_) => c.selectStatus(value),
        ),
      );
}
```

- [ ] **Step 7: `lib/app/modules/pricing/pricing_rule/pricing_rule_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/widgets/pricing_rule_list_app_bar.dart';
import 'package:multimax/app/modules/pricing/widgets/pricing_rule_row.dart';

/// Pricing Rule list. Rows are navigational (`navigatesOnTap: true`).
class PricingRuleScreen extends GetView<PricingRuleController> {
  const PricingRuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: DocTypeGuard(
        doctype: 'Pricing Rule',
        permType: 'create',
        child: FloatingActionButton.extended(
          onPressed: () => controller.openRule(null),
          tooltip: 'New rule',
          icon: const Icon(Icons.add),
          label: const Text('New rule'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
      ),
      body: RefreshIndicator(
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        onRefresh: () async {
          controller.loadCounts();
          await controller.fetchRules();
        },
        child: Scrollbar(
          controller: controller.scrollController,
          child: CustomScrollView(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const PricingRuleListAppBar(),
              SliverToBoxAdapter(
                child: Obx(() => ResultCountPill(
                      count: controller.rules.length,
                      hasMore: controller.hasMore.value,
                      hasActiveFilters: controller.hasActiveFilters,
                      noun: 'rule',
                      icon: Icons.percent,
                    )),
              ),
              Obx(() {
                if (controller.isLoading.value && controller.rules.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (controller.rules.isEmpty && !controller.hasActiveFilters) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: FormEmptyState(
                        icon: Icons.percent,
                        title: 'No pricing rules yet',
                        message:
                            'Rules apply special rates or discounts automatically on Delivery Notes.',
                        action: DocTypeGuard(
                          doctype: 'Pricing Rule',
                          permType: 'create',
                          child: FilledButton.icon(
                            onPressed: () => controller.openRule(null),
                            icon: const Icon(Icons.add),
                            label: const Text('New pricing rule'),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                if (controller.rules.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: ListEmptyState(
                      hasActiveFilters: true,
                      emptyIcon: Icons.percent,
                      emptyTitle: 'No pricing rules yet',
                      emptyMessage: '',
                      filteredTitle: 'No matching rules',
                      filteredMessage: 'Try another status, side or search.',
                      onClearFilters: controller.clearFilters,
                      onReload: controller.fetchRules,
                    ),
                  );
                }
                final count = controller.rules.length;
                final hasMore = controller.hasMore.value;
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      if (i == count) {
                        return ListEndFooter(
                            hasMore: hasMore, bottomPadding: bottomInset + 80);
                      }
                      final r = controller.rules[i];
                      return PricingRuleRow(
                        key: ValueKey(r.name),
                        rule: r,
                        onTap: () => controller.openRule(r),
                      );
                    },
                    childCount: count + 1,
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
```

The empty-state FAB also shows when permitted — acceptable duplication with the CTA (design shows only the CTA; hide the FAB while `rules.isEmpty && !hasActiveFilters` only if the widget test in Step 1 needs it — it doesn't).

- [ ] **Step 8: Page** — import binding + screen in `app_pages.dart` and add after ITEM_PRICE_FORM:
```dart
    GetPage(
      name: AppRoutes.PRICING_RULE,
      page: () => const PricingRuleScreen(),
      binding: PricingRuleBinding(),
    ),
```

- [ ] **Step 9: Run tests**

Run: `flutter test test/widget/pricing_rule_screen_test.dart`
Expected: PASS. Note the "New pricing rule" assertion uses `findsOneWidget`; the FAB label is "New rule", so they don't collide.

- [ ] **Step 10: Commit**

```bash
git add lib/app/modules/pricing/widgets/pricing_rule_row.dart lib/app/modules/pricing/pricing_rule lib/app/data/routes/app_pages.dart test/widget/pricing_rule_screen_test.dart
git commit -m "feat(pricing): Pricing Rule list screen

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Pricing Rule form

**Files:**
- Create: `lib/app/modules/pricing/pricing_rule/form/pricing_rule_form_binding.dart`
- Create: `lib/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart`
- Create: `lib/app/modules/pricing/pricing_rule/form/pricing_rule_form_screen.dart`
- Modify: `lib/app/data/routes/app_pages.dart` (PRICING_RULE_FORM page)
- Test: `test/unit/pricing_rule_form_controller_test.dart`, `test/widget/pricing_rule_form_screen_test.dart`

**Interfaces:**
- Consumes: `PricingRuleProvider`, `PricingRule`, `PricingRuleTarget`, `validatePricingRule`, `applicableForOptions`, `describePricingRule`, `pricingRuleStatus`, `kPricingRuleFieldTab`, `frappeDate`, `parseFrappeDate`, `displayDate`, widgets from Task 4, `showOptionPickerSheet`, `ItemFormController.parseServerMessage`.
- Produces: `PricingRuleFormController` — `name`, `mode`, `rule` (Rx<PricingRule>), `isLoading/isSaving/isDeleting/isDirty/notFound`, `saveResult`, `serverError`, `fieldErrors`, text controllers (`titleController`, `valueController`, `minQtyController`, `maxQtyController`, `minAmtController`, `maxAmtController`), `isEditable`, `sideLabel`, `forOptions`, `tabHasError(int)`, `setEnabled`, `setSide`, `setApplicableFor`, `pickParty`, `setApplyOn`, `addTarget`, `removeTarget`, `toggleTargetUom`, `setRateOrDiscount`, `pickForPriceList`, `clearForPriceList`, `setApplyDiscountOn`, `pickDate`, `clearValidUpto`, `pickPriority`, `setApplyMultiple`, `setMixedConditions`, `setCumulative`, `pickWarehouse`, `clearWarehouse`, `saveDocument`, `deleteDocument`, `performDelete`, `confirmDiscard`; `static const kApplyOnLabels`.

- [ ] **Step 1: Write the failing controller test** — `test/unit/pricing_rule_form_controller_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart';

Response _res(int code, [dynamic data]) =>
    Response(requestOptions: RequestOptions(path: '/'), statusCode: code, data: data);

class _FakeProvider extends PricingRuleProvider {
  Map<String, dynamic> doc = {};
  Map<String, dynamic>? lastCreate;
  Map<String, dynamic>? lastUpdate;

  @override
  Future<({String name, String currency})?> getDefaultCompany() async =>
      (name: 'Multimax', currency: 'AED');

  @override
  Future<Response> getRule(String name) async => _res(200, {'data': doc});

  @override
  Future<Response> createRule(Map<String, dynamic> data) async {
    lastCreate = data;
    doc = {...data, 'name': 'PRLE-0001', 'modified': 'm1'};
    return _res(200, {'data': doc});
  }

  @override
  Future<Response> updateRule(String name, Map<String, dynamic> data) async {
    lastUpdate = data;
    return _res(200, {'data': doc});
  }

  @override
  Future<Response> deleteRule(String name) async => _res(202);
}

class _Perms extends PermissionService {
  final _g = true.obs;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

Map<String, dynamic> _existing({String? scheme, String pod = 'Price'}) => {
      'name': 'PRLE-0007',
      'title': 'Retail winter 10%',
      'apply_on': 'Item Code',
      'price_or_product_discount': pod,
      'selling': 1,
      'buying': 0,
      'applicable_for': 'Customer Group',
      'customer_group': 'Retail',
      'rate_or_discount': 'Discount Percentage',
      'discount_percentage': 10,
      'for_price_list': 'Standard Selling',
      'currency': 'AED',
      'promotional_scheme': scheme,
      'modified': '2026-09-17 10:00:00',
      'items': [
        {'name': 'r1', 'item_code': '1000001', 'uom': null}
      ],
    };

void main() {
  late _FakeProvider provider;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<PermissionService>(_Perms());
    provider = _FakeProvider();
    Get.put<PricingRuleProvider>(provider);
  });

  tearDown(Get.reset);

  Future<PricingRuleFormController> open({Map<String, dynamic>? doc}) async {
    final c = PricingRuleFormController();
    if (doc == null) {
      c.mode.value = 'new';
    } else {
      provider.doc = doc;
      c
        ..name = doc['name'] as String
        ..mode.value = 'edit';
    }
    Get.put(c);
    await pumpEventQueue();
    return c;
  }

  test('new: v15 defaults + company currency', () async {
    final c = await open();
    final r = c.rule.value;
    expect(r.applyOn, 'Item Code');
    expect(r.priceOrProductDiscount, 'Price');
    expect(r.rateOrDiscount, 'Discount Percentage');
    expect(r.selling, isTrue);
    expect(r.validFrom, frappeDate(DateTime.now()));
    expect(r.company, 'Multimax');
    expect(r.currency, 'AED');
    expect(c.isDirty.value, isTrue);
  });

  test('switching side to Buying clears a selling party', () async {
    final c = await open(doc: _existing());
    c.setSide('Buying');
    expect(c.rule.value.buying, isTrue);
    expect(c.rule.value.selling, isFalse);
    expect(c.rule.value.applicableFor, '');
    expect(c.rule.value.party, isNull);
    expect(c.forOptions, ['Everyone', 'Supplier', 'Supplier Group']);
  });

  test('Rate clears for_price_list and reseeds the value field', () async {
    final c = await open(doc: _existing());
    expect(c.valueController.text, '10');
    c.setRateOrDiscount('Rate');
    expect(c.rule.value.forPriceList, isNull);
    expect(c.valueController.text, '');
    c.valueController.text = '22';
    expect(c.rule.value.rate, 22);
  });

  test('setApplyOn resets targets', () async {
    final c = await open(doc: _existing());
    c.setApplyOn('Item Group');
    expect(c.rule.value.targets, isEmpty);
  });

  test('save blocked by validation and tab gets the error dot', () async {
    final c = await open();
    await c.saveDocument();
    expect(provider.lastCreate, isNull);
    expect(c.fieldErrors['title'], 'Title is required');
    expect(c.tabHasError(0), isTrue);
    expect(c.tabHasError(1), isFalse);
  });

  test('new save posts naming series, items table, string priority', () async {
    final c = await open();
    c.titleController.text = 'Retail 10%';
    c.valueController.text = '10';
    c.rule.update((r) => r!.targets = [PricingRuleTarget(value: '1000001')]);
    c.rule.update((r) {
      r!.hasPriority = true;
      r.priority = '5';
    });
    await c.saveDocument();
    expect(provider.lastCreate!['naming_series'], 'PRLE-.####');
    expect(provider.lastCreate!['items'], [
      {'item_code': '1000001', 'uom': null}
    ]);
    expect(provider.lastCreate!['priority'], '5');
    expect(provider.lastCreate!['discount_percentage'], 10.0);
    expect(c.mode.value, 'edit');
    expect(c.name, 'PRLE-0001');
  });

  test('edit: clean after load; update sends modified', () async {
    final c = await open(doc: _existing());
    expect(c.isDirty.value, isFalse);
    c.titleController.text = 'Retail winter 12%';
    expect(c.isDirty.value, isTrue);
    await c.saveDocument();
    expect(provider.lastUpdate!['modified'], '2026-09-17 10:00:00');
    expect(provider.lastUpdate!.containsKey('naming_series'), isFalse);
  });

  test('promotional scheme and product rules are read-only', () async {
    final promo = await open(doc: _existing(scheme: 'Eid 2026'));
    expect(promo.isEditable, isFalse);
    promo.setSide('Buying');
    expect(promo.rule.value.selling, isTrue, reason: 'edits ignored');
    Get.delete<PricingRuleFormController>();
    final product = await open(doc: _existing(pod: 'Product'));
    expect(product.isEditable, isFalse);
  });

  test('toggleTargetUom clears an existing unit', () async {
    final c = await open(doc: _existing());
    c.rule.update((r) => r!.targets.first.uom = 'Nos');
    await c.toggleTargetUom(0);
    expect(c.rule.value.targets.first.uom, isNull);
  });

  test('performDelete accepts 202', () async {
    final c = await open(doc: _existing());
    expect(await c.performDelete(), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/unit/pricing_rule_form_controller_test.dart`
Expected: FAIL — controller missing.

- [ ] **Step 3: `lib/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart`**

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/widgets/priority_picker_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';

/// Pricing Rule form (modes `new`/`edit`/`view`). Price-discount rules are
/// editable; promotional-scheme and free-item (Product) rules are read-only.
class PricingRuleFormController extends GetxController with OptimisticLockingMixin {
  final PricingRuleProvider _provider = Get.find<PricingRuleProvider>();

  static const Map<String, String> kApplyOnLabels = {
    'Item Code': 'Item',
    'Item Group': 'Group',
    'Brand': 'Brand',
    'Transaction': 'Transaction',
  };

  String name = (Get.arguments is Map ? Get.arguments['name'] : null) ?? '';
  final RxString mode =
      RxString((Get.arguments is Map ? Get.arguments['mode'] : null) ?? 'view');

  final rule = PricingRule().obs;
  final isLoading = true.obs;
  final isSaving = false.obs;
  final isDeleting = false.obs;
  final isDirty = false.obs;
  final notFound = false.obs;
  final saveResult = SaveResult.idle.obs;
  final serverError = ''.obs;
  final fieldErrors = <String, String>{}.obs;

  final titleController = TextEditingController();
  final valueController = TextEditingController();
  final minQtyController = TextEditingController();
  final maxQtyController = TextEditingController();
  final minAmtController = TextEditingController();
  final maxAmtController = TextEditingController();

  List<TextEditingController> get _textControllers => [
        titleController,
        valueController,
        minQtyController,
        maxQtyController,
        minAmtController,
        maxAmtController,
      ];

  bool _seeding = false;
  String _originalJson = '';

  bool get canWrite =>
      Get.find<PermissionService>().hasAccess('Pricing Rule',
          permType: mode.value == 'new' ? 'create' : 'write') ==
      true;

  bool get isEditable => mode.value != 'view' && !rule.value.isLocked && canWrite;

  String get sideLabel {
    final r = rule.value;
    if (r.selling && r.buying) return 'Selling & Buying';
    return r.buying ? 'Buying' : 'Selling';
  }

  List<String> get forOptions => [
        'Everyone',
        ...applicableForOptions(
            selling: rule.value.selling, buying: rule.value.buying),
      ];

  bool tabHasError(int tab) =>
      fieldErrors.keys.any((k) => kPricingRuleFieldTab[k] == tab);

  @override
  void onInit() {
    super.onInit();
    for (final c in _textControllers) {
      c.addListener(_syncText);
    }
    if (mode.value == 'new') {
      _initNew();
    } else {
      fetchDocument();
    }
  }

  @override
  void onClose() {
    for (final c in _textControllers) {
      c.dispose();
    }
    super.onClose();
  }

  // ── Load ─────────────────────────────────────────────────────────────

  Future<void> _initNew() async {
    rule.value = PricingRule(validFrom: frappeDate(DateTime.now()));
    _seedControllers();
    isDirty.value = true;
    isLoading.value = false;
    try {
      final company = await _provider.getDefaultCompany();
      if (company != null) {
        rule.update((r) {
          r!.company = company.name;
          r.currency = company.currency;
        });
      }
    } catch (_) {
      // Currency stays blank; the server's "Currency is required" surfaces
      // in the banner on save.
    }
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getRule(name);
      rule.value =
          PricingRule.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      _seedControllers();
      _originalJson = jsonEncode(rule.value.toJson());
      isDirty.value = false;
      notFound.value = false;
      serverError.value = '';
      fieldErrors.clear();
    } catch (_) {
      notFound.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Future<void> reloadDocument() => fetchDocument();

  static double _parse(String s) =>
      double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  static String _show(double v) => v == 0
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  double _value(PricingRule r) => switch (r.rateOrDiscount) {
        'Rate' => r.rate,
        'Discount Amount' => r.discountAmount,
        _ => r.discountPercentage,
      };

  void _seedControllers() {
    _seeding = true;
    final r = rule.value;
    titleController.text = r.title;
    valueController.text = _show(_value(r));
    minQtyController.text = _show(r.minQty);
    maxQtyController.text = _show(r.maxQty);
    minAmtController.text = _show(r.minAmt);
    maxAmtController.text = _show(r.maxAmt);
    _seeding = false;
  }

  void _syncText() {
    if (_seeding || !isEditable) return;
    final r = rule.value;
    r.title = titleController.text;
    final v = _parse(valueController.text);
    switch (r.rateOrDiscount) {
      case 'Rate':
        r.rate = v;
      case 'Discount Amount':
        r.discountAmount = v;
      default:
        r.discountPercentage = v;
    }
    r.minQty = _parse(minQtyController.text);
    r.maxQty = _parse(maxQtyController.text);
    r.minAmt = _parse(minAmtController.text);
    r.maxAmt = _parse(maxAmtController.text);
    rule.refresh();
    _checkDirty();
  }

  void _checkDirty() {
    if (mode.value == 'new') {
      isDirty.value = true;
      return;
    }
    isDirty.value = jsonEncode(rule.value.toJson()) != _originalJson;
  }

  void _edit(void Function(PricingRule r) change) {
    if (!isEditable) return;
    rule.update((r) => change(r!));
    _checkDirty();
  }

  // ── Rule tab ─────────────────────────────────────────────────────────

  void setEnabled(bool enabled) => _edit((r) => r.disable = !enabled);

  /// pricing_rule.js: a party type that no longer fits the side is cleared.
  void setSide(String label) => _edit((r) {
        r.selling = label != 'Buying';
        r.buying = label != 'Selling';
        if (r.applicableFor.isNotEmpty &&
            !applicableForOptions(selling: r.selling, buying: r.buying)
                .contains(r.applicableFor)) {
          r.applicableFor = '';
          r.party = null;
        }
      });

  void setApplicableFor(String option) => _edit((r) {
        final v = option == 'Everyone' ? '' : option;
        if (v != r.applicableFor) {
          r.applicableFor = v;
          r.party = null;
        }
      });

  Future<void> pickParty() async {
    final type = rule.value.applicableFor;
    if (!isEditable || type.isEmpty) return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: type,
        title: 'Select ${type.toLowerCase()}',
        columns: [DocTypePickerColumn(fieldname: 'name', label: type, isPrimary: true)],
      ),
    );
    if (row != null) _edit((r) => r.party = row['name'] as String);
  }

  void setApplyOn(String value) => _edit((r) {
        if (r.applyOn != value) {
          r.applyOn = value;
          r.targets = [];
        }
      });

  Future<void> addTarget() async {
    final current = rule.value;
    if (!isEditable || current.applyOn == 'Transaction') return;
    final isItem = current.applyOn == 'Item Code';
    final doctype = isItem ? 'Item' : current.applyOn;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: doctype,
        title: 'Add ${doctype.toLowerCase()}',
        columns: [
          DocTypePickerColumn(fieldname: 'name', label: doctype, isPrimary: true),
          if (isItem)
            DocTypePickerColumn(fieldname: 'item_name', label: 'Name', isSecondary: true),
        ],
        extraFields: isItem ? const ['variant_of'] : const [],
        filters: isItem
            ? const [
                ['Item', 'disabled', '=', 0]
              ]
            : const [],
        enableBarcodeScan: isItem,
      ),
    );
    if (row == null) return;
    final value = row['name'] as String;
    if (current.targets.any((t) => t.value == value)) {
      GlobalSnackbar.info(message: '$value is already in this rule');
      return;
    }
    _edit((r) => r.targets = [
          ...r.targets,
          PricingRuleTarget(
            value: value,
            label: pricingLink(row['item_name']),
            variantOf: pricingLink(row['variant_of']),
          ),
        ]);
  }

  void removeTarget(int index) =>
      _edit((r) => r.targets = [...r.targets]..removeAt(index));

  /// Tap on a unit chip: clears a set unit ("Any unit"), otherwise picks one.
  Future<void> toggleTargetUom(int index) async {
    if (!isEditable) return;
    if (rule.value.targets[index].uom != null) {
      _edit((r) => r.targets[index].uom = null);
      return;
    }
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'UOM',
        title: 'Select unit',
        columns: [DocTypePickerColumn(fieldname: 'name', label: 'Unit', isPrimary: true)],
      ),
    );
    if (row != null) _edit((r) => r.targets[index].uom = row['name'] as String);
  }

  // ── Discount tab ─────────────────────────────────────────────────────

  void setRateOrDiscount(String value) {
    _edit((r) {
      r.rateOrDiscount = value;
      if (value == 'Rate') r.forPriceList = null;
    });
    _seeding = true;
    valueController.text = _show(_value(rule.value));
    _seeding = false;
  }

  Future<void> pickForPriceList() async {
    final r0 = rule.value;
    if (!isEditable || r0.rateOrDiscount == 'Rate') return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Price List',
        title: 'Only for price list',
        columns: [
          DocTypePickerColumn(fieldname: 'name', label: 'Price list', isPrimary: true),
          DocTypePickerColumn(fieldname: 'currency', label: 'Currency', isSecondary: true),
        ],
        // Mirrors the desk query: same selling/buying flags and currency.
        filters: [
          ['Price List', 'enabled', '=', 1],
          ['Price List', 'selling', '=', r0.selling ? 1 : 0],
          ['Price List', 'buying', '=', r0.buying ? 1 : 0],
          if (r0.currency.isNotEmpty) ['Price List', 'currency', '=', r0.currency],
        ],
      ),
    );
    if (row != null) _edit((r) => r.forPriceList = row['name'] as String);
  }

  void clearForPriceList() => _edit((r) => r.forPriceList = null);

  void setApplyDiscountOn(String value) => _edit((r) => r.applyDiscountOn = value);

  // ── Conditions tab ───────────────────────────────────────────────────

  Future<void> pickDate(BuildContext context, String field) async {
    if (!isEditable) return;
    final current = parseFrappeDate(
        field == 'valid_from' ? rule.value.validFrom : rule.value.validUpto);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _edit((r) => field == 'valid_from'
        ? r.validFrom = frappeDate(picked)
        : r.validUpto = frappeDate(picked));
  }

  void clearValidUpto() => _edit((r) => r.validUpto = null);

  Future<void> pickPriority(BuildContext context) async {
    if (!isEditable) return;
    final v = await showPriorityPicker(context, current: rule.value.priority);
    if (v == null) return;
    _edit((r) {
      r.priority = v;
      r.hasPriority = v.isNotEmpty;
    });
  }

  void setApplyMultiple(bool v) => _edit((r) => r.applyMultiplePricingRules = v);

  void setMixedConditions(bool v) => _edit((r) => r.mixedConditions = v);

  void setCumulative(bool v) => _edit((r) => r.isCumulative = v);

  Future<void> pickWarehouse() async {
    if (!isEditable) return;
    final row = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Warehouse',
        title: 'Select warehouse',
        columns: [DocTypePickerColumn(fieldname: 'name', label: 'Warehouse', isPrimary: true)],
      ),
    );
    if (row != null) _edit((r) => r.warehouse = row['name'] as String);
  }

  void clearWarehouse() => _edit((r) => r.warehouse = null);

  // ── Save / delete / discard ──────────────────────────────────────────

  Future<void> saveDocument() async {
    if (isSaving.value || !isEditable) return;
    final errors = validatePricingRule(rule.value);
    fieldErrors.assignAll(errors);
    if (errors.isNotEmpty) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: errors.values.first);
      return;
    }
    if (checkStaleAndBlock()) return;

    isSaving.value = true;
    serverError.value = '';
    final data = rule.value.toJson();
    if (mode.value != 'new') data['modified'] = rule.value.modified;

    try {
      final res = mode.value == 'new'
          ? await _provider.createRule(data)
          : await _provider.updateRule(name, data);
      final saved = res.data is Map ? res.data['data'] : null;
      if (saved is Map && saved['name'] != null) name = saved['name'].toString();
      mode.value = 'edit';
      await fetchDocument();
      saveResult.value = SaveResult.success;
      GlobalSnackbar.success(message: 'Pricing rule saved');
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      saveResult.value = SaveResult.error;
      serverError.value = ItemFormController.parseServerMessage(e.response?.data);
    } catch (e) {
      saveResult.value = SaveResult.error;
      serverError.value = e.toString();
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(onDiscard: () {
      isDirty.value = false;
      Get.back();
    });
  }

  Future<void> deleteDocument() async {
    if (isDeleting.value) return;
    final confirmed = await GlobalDialog.confirm(
      title: 'Delete pricing rule?',
      message: '${rule.value.title}. Delivery Notes already saved keep their '
          'discount; new ones will not get it.',
      confirmText: 'Delete',
      confirmColor: AppColors.red700,
      icon: Icons.delete_outline,
    );
    if (confirmed != true) return;
    if (await performDelete()) Get.back();
  }

  Future<bool> performDelete() async {
    if (isDeleting.value) return false;
    isDeleting.value = true;
    try {
      final res = await _provider.deleteRule(name);
      final ok = res.statusCode == 200 || res.statusCode == 202 || res.statusCode == 204;
      if (ok) {
        isDirty.value = false;
        GlobalSnackbar.success(message: 'Pricing rule deleted');
      } else {
        GlobalSnackbar.error(message: 'Failed to delete pricing rule');
      }
      return ok;
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to delete pricing rule: $e');
      return false;
    } finally {
      isDeleting.value = false;
    }
  }
}
```

- [ ] **Step 4: Run controller test**

Run: `flutter test test/unit/pricing_rule_form_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: `lib/app/modules/pricing/pricing_rule/form/pricing_rule_form_binding.dart`**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart';

class PricingRuleFormBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<PricingRuleProvider>()) {
      Get.lazyPut<PricingRuleProvider>(() => PricingRuleProvider(), fenix: true);
    }
    Get.lazyPut<PricingRuleFormController>(() => PricingRuleFormController());
  }
}
```

- [ ] **Step 6: Write the failing widget test** — `test/widget/pricing_rule_form_screen_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_screen.dart';

class _FakeProvider extends PricingRuleProvider {
  _FakeProvider(this.doc);
  final Map<String, dynamic> doc;
  @override
  Future<Response> getRule(String name) async => Response(
      requestOptions: RequestOptions(path: '/'), statusCode: 200, data: {'data': doc});
}

class _Perms extends PermissionService {
  final _g = true.obs;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

Map<String, dynamic> _doc({String? scheme, String pod = 'Price', String rod = 'Discount Percentage'}) => {
      'name': 'PRLE-0007',
      'title': 'Retail winter 10%',
      'apply_on': 'Item Code',
      'price_or_product_discount': pod,
      'selling': 1,
      'applicable_for': 'Customer Group',
      'customer_group': 'Retail',
      'rate_or_discount': rod,
      'discount_percentage': 10,
      'rate': 22,
      'for_price_list': 'Standard Selling',
      'currency': 'AED',
      'free_item': '2001490',
      'free_qty': 1,
      'promotional_scheme': scheme,
      'modified': 'm',
      'items': [
        {'name': 'r1', 'item_code': '1000001', 'uom': null}
      ],
    };

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  tearDown(Get.reset);

  Future<PricingRuleFormController> pump(WidgetTester tester, Map<String, dynamic> doc,
      {Brightness brightness = Brightness.light}) async {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<PermissionService>(_Perms());
    Get.put<PricingRuleProvider>(_FakeProvider(doc));
    final c = Get.put(PricingRuleFormController()
      ..name = 'PRLE-0007'
      ..mode.value = 'edit');
    final theme = ThemeData(brightness: brightness, useMaterial3: true);
    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      darkTheme: theme,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const PricingRuleFormScreen(),
    ));
    await tester.pump();
    await tester.pump();
    return c;
  }

  const summary =
      '10% off Standard Selling for customer group Retail on item 1000001';

  testWidgets('Rule tab shows summary, party and target', (tester) async {
    await pump(tester, _doc());
    expect(tester.takeException(), isNull);
    expect(find.text(summary), findsOneWidget);
    expect(find.text('Retail'), findsOneWidget);
    expect(find.text('1000001'), findsOneWidget);
    expect(find.text('Add item'), findsOneWidget);
  });

  testWidgets('Discount tab: price list field only for discounts', (tester) async {
    final c = await pump(tester, _doc());
    await tester.tap(find.text('Discount'));
    await tester.pumpAndSettle();
    expect(find.text('Only for price list'), findsOneWidget);
    c.setRateOrDiscount('Rate');
    await tester.pumpAndSettle();
    expect(find.text('Only for price list'), findsNothing);
  });

  testWidgets('summary updates when the title-independent value changes',
      (tester) async {
    final c = await pump(tester, _doc());
    c.valueController.text = '15';
    await tester.pump();
    expect(find.textContaining('15% off'), findsOneWidget);
  });

  testWidgets('promotional scheme: locked banner, no Save', (tester) async {
    await pump(tester, _doc(scheme: 'Eid 2026'));
    expect(find.textContaining('Promotional Scheme “Eid 2026”'), findsOneWidget);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.text('Add item'), findsNothing);
  });

  testWidgets('product rule: read-only notice on Discount tab', (tester) async {
    await pump(tester, _doc(pod: 'Product'));
    await tester.tap(find.text('Discount'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Product rules are read-only in the app'),
        findsOneWidget);
  });

  testWidgets('Conditions tab warns when priority is not set (dark)',
      (tester) async {
    await pump(tester, _doc(), brightness: Brightness.dark);
    await tester.tap(find.text('Conditions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No priority set'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

Tabs: the header TabBar labels are `Rule`, `Discount`, `Conditions`. If `find.text('Discount')` is ambiguous (e.g. a segment label), use `find.descendant(of: find.byType(TabBar), matching: find.text('Discount'))`.

- [ ] **Step 7: Run to verify failure**

Run: `flutter test test/widget/pricing_rule_form_screen_test.dart`
Expected: FAIL — screen missing.

- [ ] **Step 8: `lib/app/modules/pricing/pricing_rule/form/pricing_rule_form_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_detail_row.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart';
import 'package:multimax/app/modules/pricing/widgets/money_field.dart';
import 'package:multimax/app/modules/pricing/widgets/rule_summary_card.dart';
import 'package:multimax/app/modules/pricing/widgets/target_list_editor.dart';

class PricingRuleFormScreen extends GetView<PricingRuleFormController> {
  const PricingRuleFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Obx(() {
        final r = controller.rule.value;
        final isNew = controller.mode.value == 'new';
        final editable = controller.isEditable;
        final dirty = controller.isDirty.value;
        final loading = controller.isLoading.value;
        final title = r.title.trim().isNotEmpty
            ? r.title
            : (isNew ? 'New pricing rule' : controller.name);

        return PopScope(
          canPop: !dirty || !editable,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) await controller.confirmDiscard();
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                DocTypeFormHeader(
                  title: title,
                  docType: 'Pricing Rule',
                  statusLabel: loading
                      ? null
                      : (dirty && editable)
                          ? 'Not Saved'
                          : pricingRuleStatus(r, DateTime.now()),
                  canSave: editable && dirty,
                  isSaving: controller.isSaving.value,
                  saveResult: controller.saveResult.value,
                  onSave: editable ? controller.saveDocument : null,
                  onReload: isNew ? null : controller.reloadDocument,
                  extraActions: [
                    if (!isNew && !loading && !controller.notFound.value)
                      // Pricing Rule delete roles == write roles (v15 DocPerm);
                      // PermissionService has no real delete check.
                      DocTypeGuard(
                        doctype: 'Pricing Rule',
                        permType: 'write',
                        child: AsyncIconButton(
                          busy: controller.isDeleting,
                          onPressed: controller.deleteDocument,
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                  bottom: TabBar(
                    tabs: [
                      Tab(child: _TabLabel('Rule', controller.tabHasError(0))),
                      Tab(child: _TabLabel('Discount', controller.tabHasError(1))),
                      Tab(child: _TabLabel('Conditions', controller.tabHasError(2))),
                    ],
                  ),
                ),
              ],
              body: loading
                  ? const Center(child: CircularProgressIndicator())
                  : controller.notFound.value
                      ? const Center(
                          child: FormEmptyState(
                            icon: Icons.search_off,
                            message: 'Pricing rule not found or not accessible.',
                          ),
                        )
                      : const TabBarView(
                          children: [_RuleTab(), _DiscountTab(), _ConditionsTab()],
                        ),
            ),
          ),
        );
      }),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, this.hasError);

  final String label;
  final bool hasError;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (hasError) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: AppColors.red300, shape: BoxShape.circle),
            ),
          ],
        ],
      );
}

EdgeInsets _tabPadding(BuildContext context) => EdgeInsets.fromLTRB(
    12, 12, 12, 24 + MediaQuery.of(context).padding.bottom);

/// Banners + summary card at the top of every tab.
List<Widget> _prelude(PricingRuleFormController c, PricingRule r,
    {bool showLabel = false}) {
  return [
    if ((r.promotionalScheme ?? '').isNotEmpty) ...[
      InlineBanner(
        visible: true,
        type: BannerType.info,
        icon: Icons.lock_outline,
        message:
            'Locked · Promotional Scheme “${r.promotionalScheme}” overwrites edits. Open it on desktop.',
      ),
      const SizedBox(height: 12),
    ],
    if (c.serverError.value.isNotEmpty) ...[
      InlineBanner(
        visible: true,
        type: BannerType.error,
        message: "Couldn't save\n${c.serverError.value}",
      ),
      const SizedBox(height: 12),
    ],
    RuleSummaryCard(text: describePricingRule(r), showLabel: showLabel),
    const SizedBox(height: 12),
  ];
}

Widget _numField(TextEditingController ctrl, String label, bool editable,
        {String? error, String? prefix}) =>
    TextField(
      controller: ctrl,
      readOnly: !editable,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        prefixText: prefix == null ? null : '$prefix ',
        errorText: error,
        errorMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );

class _RuleTab extends GetView<PricingRuleFormController> {
  const _RuleTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final r = controller.rule.value;
      final e = controller.fieldErrors;
      final editable = controller.isEditable;
      final s = context.scheme;
      final forValue = r.applicableFor.isEmpty ? 'Everyone' : r.applicableFor;
      return ListView(
        padding: _tabPadding(context),
        children: [
          ..._prelude(controller, r),
          DocSectionCard(
            title: 'Rule',
            margin: const EdgeInsets.only(bottom: 12),
            headerAction: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.disable ? 'Disabled' : 'Enabled',
                    style: TextStyle(fontSize: 11, color: s.textMuted)),
                Switch(
                  value: !r.disable,
                  onChanged: editable ? controller.setEnabled : null,
                ),
              ],
            ),
            children: [
              TextField(
                controller: controller.titleController,
                readOnly: !editable,
                decoration: InputDecoration(
                  labelText: 'Title',
                  errorText: e['title'],
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Side',
                icon: r.buying && !r.selling
                    ? Icons.local_shipping_outlined
                    : Icons.storefront_outlined,
                value: controller.sideLabel,
                onTap: editable
                    ? () => showOptionPickerSheet(
                          context,
                          title: 'Side',
                          options: const ['Selling', 'Buying', 'Selling & Buying'],
                          selected: controller.sideLabel,
                          onSelected: controller.setSide,
                        )
                    : null,
              ),
              FieldErrorText(e['selling']),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'For',
                icon: Icons.groups_outlined,
                value: forValue,
                onTap: editable
                    ? () => showOptionPickerSheet(
                          context,
                          title: 'For',
                          options: controller.forOptions,
                          selected: forValue,
                          onSelected: controller.setApplicableFor,
                        )
                    : null,
              ),
              FieldErrorText(e['applicable_for']),
              if (r.applicableFor.isNotEmpty) ...[
                const SizedBox(height: 12),
                DocPickerField(
                  label: r.applicableFor,
                  icon: Icons.search,
                  value: r.party,
                  placeholder: 'Select ${r.applicableFor.toLowerCase()}',
                  trailingIcon: Icons.search,
                  onTap: editable ? controller.pickParty : null,
                ),
                FieldErrorText(e['party']),
              ],
            ],
          ),
          DocSectionCard(
            title: 'Applies on',
            margin: EdgeInsets.zero,
            headerAction: r.applyOn == 'Transaction'
                ? null
                : Text('${r.targets.length}',
                    style: TextStyle(fontSize: 11, color: s.textSubtle)),
            children: [
              SettingsSegmented<String>(
                options: [
                  for (final entry
                      in PricingRuleFormController.kApplyOnLabels.entries)
                    SegmentOption(value: entry.key, label: entry.value),
                ],
                value: r.applyOn,
                onChanged: editable ? controller.setApplyOn : (_) {},
              ),
              const SizedBox(height: 12),
              if (r.applyOn == 'Transaction')
                Text('Applies to the whole Delivery Note.',
                    style: TextStyle(fontSize: 12, color: s.textMuted))
              else
                TargetListEditor(
                  targets: r.targets,
                  applyOn: r.applyOn,
                  readOnly: !editable,
                  onAdd: controller.addTarget,
                  onRemove: controller.removeTarget,
                  onPickUom: controller.toggleTargetUom,
                ),
              FieldErrorText(e['targets']),
            ],
          ),
        ],
      );
    });
  }
}

class _DiscountTab extends GetView<PricingRuleFormController> {
  const _DiscountTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final r = controller.rule.value;
      final e = controller.fieldErrors;
      final editable = controller.isEditable;
      final rod = r.rateOrDiscount.isEmpty ? 'Discount Percentage' : r.rateOrDiscount;
      return ListView(
        padding: _tabPadding(context),
        children: [
          ..._prelude(controller, r, showLabel: true),
          DocSectionCard(
            title: 'What it gives',
            margin: EdgeInsets.zero,
            children: [
              // Product (free item) editing is desktop-only in v1.
              SettingsSegmented<String>(
                options: const [
                  SegmentOption(value: 'Price', label: 'Price'),
                  SegmentOption(value: 'Product', label: 'Product'),
                ],
                value: r.priceOrProductDiscount,
                onChanged: (_) {},
              ),
              const SizedBox(height: 12),
              if (r.priceOrProductDiscount == 'Product') ...[
                DocPickerField(
                  label: 'Free item',
                  icon: Icons.card_giftcard_outlined,
                  value: r.sameItem ? 'Same item' : r.freeItem,
                  helperText: 'Qty ${r.freeQty == r.freeQty.roundToDouble() ? r.freeQty.toInt() : r.freeQty}',
                ),
                const SizedBox(height: 12),
                const InlineBanner(
                  visible: true,
                  type: BannerType.info,
                  message:
                      'Product rules are read-only in the app. Free-item rules are set up and changed on desktop.',
                ),
              ] else ...[
                SettingsSegmented<String>(
                  options: const [
                    SegmentOption(value: 'Rate', label: 'Rate'),
                    SegmentOption(value: 'Discount Percentage', label: 'Discount %'),
                    SegmentOption(value: 'Discount Amount', label: 'Amount'),
                  ],
                  value: rod,
                  onChanged: editable ? controller.setRateOrDiscount : (_) {},
                ),
                FieldErrorText(e['rate_or_discount']),
                const SizedBox(height: 12),
                MoneyField(
                  key: ValueKey(rod),
                  label: switch (rod) {
                    'Rate' => 'Rate',
                    'Discount Amount' => 'Discount amount',
                    _ => 'Discount',
                  },
                  controller: controller.valueController,
                  prefix: rod == 'Discount Percentage' || r.currency.isEmpty
                      ? null
                      : r.currency,
                  suffix: switch (rod) {
                    'Rate' => '/ unit',
                    'Discount Amount' => 'per unit',
                    _ => '%',
                  },
                  decimals: rod == 'Discount Percentage' ? null : 2,
                  readOnly: !editable,
                  errorText: e['rate'] ?? e['discount_percentage'] ?? e['discount_amount'],
                ),
                if (rod != 'Rate') ...[
                  const SizedBox(height: 12),
                  DocPickerField(
                    label: 'Only for price list',
                    icon: Icons.sell_outlined,
                    value: r.forPriceList,
                    placeholder: 'Any price list',
                    helperText: r.forPriceList == null
                        ? 'Leave empty to apply on every list'
                        : 'Lines priced from other lists are not discounted',
                    onTap: editable ? controller.pickForPriceList : null,
                  ),
                  if (editable && r.forPriceList != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: controller.clearForPriceList,
                        child: const Text('Any price list'),
                      ),
                    ),
                ],
                if (r.applyOn == 'Transaction' && rod != 'Rate') ...[
                  const SizedBox(height: 12),
                  DocPickerField(
                    label: 'Apply discount on',
                    icon: Icons.receipt_long_outlined,
                    value: r.applyDiscountOn,
                    onTap: editable
                        ? () => showOptionPickerSheet(
                              context,
                              title: 'Apply discount on',
                              options: const ['Grand Total', 'Net Total'],
                              selected: r.applyDiscountOn,
                              onSelected: controller.setApplyDiscountOn,
                            )
                        : null,
                  ),
                ],
              ],
            ],
          ),
        ],
      );
    });
  }
}

class _ConditionsTab extends GetView<PricingRuleFormController> {
  const _ConditionsTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final r = controller.rule.value;
      final e = controller.fieldErrors;
      final editable = controller.isEditable;
      final s = context.scheme;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final warnInk = dark ? AppColors.orange300 : AppColors.orange700;
      return ListView(
        padding: _tabPadding(context),
        children: [
          ..._prelude(controller, r),
          DocSectionCard(
            title: 'When',
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: DocPickerField(
                      label: 'Valid from',
                      icon: Icons.event_outlined,
                      value: r.validFrom == null ? null : displayDate(r.validFrom),
                      placeholder: 'Any date',
                      trailingIcon: Icons.edit_calendar_outlined,
                      onTap: editable
                          ? () => controller.pickDate(context, 'valid_from')
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DocPickerField(
                      label: 'Valid upto',
                      icon: Icons.event_outlined,
                      value: r.validUpto == null ? null : displayDate(r.validUpto),
                      placeholder: 'No end date',
                      trailingIcon: Icons.edit_calendar_outlined,
                      onTap: editable
                          ? () => controller.pickDate(context, 'valid_upto')
                          : null,
                    ),
                  ),
                ],
              ),
              FieldErrorText(e['valid_from'] ?? e['valid_upto']),
              if (editable && r.validUpto != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: controller.clearValidUpto,
                    child: const Text('No end date'),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _numField(controller.minQtyController, 'Min qty', editable)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _numField(controller.maxQtyController, 'Max qty', editable,
                          error: e['max_qty'])),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _numField(controller.minAmtController, 'Min amount', editable,
                          prefix: r.currency.isEmpty ? null : r.currency)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _numField(controller.maxAmtController, 'Max amount', editable,
                          prefix: r.currency.isEmpty ? null : r.currency,
                          error: e['max_amt'])),
                ],
              ),
              const SizedBox(height: 6),
              Text('0 = no limit', style: TextStyle(fontSize: 11, color: s.textMuted)),
            ],
          ),
          DocSectionCard(
            title: 'Priority',
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              DocPickerField(
                label: 'Priority',
                icon: Icons.swap_vert,
                value: r.hasPriority && r.priority.isNotEmpty ? r.priority : null,
                placeholder: 'Not set',
                helperText: '1–20. When several rules match one line, the higher number wins.',
                onTap: editable ? () => controller.pickPriority(context) : null,
              ),
              FieldErrorText(e['priority']),
              if (!r.hasPriority)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: warnInk),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          "No priority set. If another rule matches the same Delivery Note line at the same priority, that note can't be saved.",
                          style: TextStyle(fontSize: 11, height: 1.35, color: warnInk),
                        ),
                      ),
                    ],
                  ),
                ),
              SettingsSwitchRow(
                title: 'Apply multiple rules',
                subtitle: 'Let other matching rules stack on top of this one',
                value: r.applyMultiplePricingRules,
                onChanged: editable ? controller.setApplyMultiple : (_) {},
              ),
              if (r.applyOn != 'Transaction') ...[
                SettingsSwitchRow(
                  title: 'Mixed conditions',
                  subtitle: 'Apply the qty and amount limits to the selected items combined',
                  value: r.mixedConditions,
                  onChanged: editable ? controller.setMixedConditions : (_) {},
                ),
                SettingsSwitchRow(
                  title: 'Cumulative',
                  subtitle: 'Count quantities across transactions in the validity period',
                  value: r.isCumulative,
                  onChanged: editable ? controller.setCumulative : (_) {},
                ),
              ],
            ],
          ),
          if (r.applyOn != 'Transaction')
            DocSectionCard(
              title: 'Warehouse',
              margin: const EdgeInsets.only(bottom: 12),
              children: [
                DocPickerField(
                  label: 'Warehouse',
                  icon: Icons.warehouse_outlined,
                  value: r.warehouse,
                  placeholder: 'Any warehouse',
                  onTap: editable ? controller.pickWarehouse : null,
                ),
                if (editable && r.warehouse != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: controller.clearWarehouse,
                      child: const Text('Any warehouse'),
                    ),
                  ),
              ],
            ),
          if (r.hasAdvanced)
            DocSectionCard(
              title: 'Advanced (read-only)',
              margin: EdgeInsets.zero,
              children: [
                if ((r.condition ?? '').isNotEmpty)
                  DocDetailRow(label: 'Condition', value: r.condition!),
                if (r.couponCodeBased)
                  const DocDetailRow(label: 'Coupon code based', value: 'Yes'),
                if (r.isRecursive) const DocDetailRow(label: 'Recursive', value: 'Yes'),
                if (r.marginRateOrAmount != 0)
                  DocDetailRow(
                      label: 'Margin',
                      value: '${r.marginType ?? ''} ${r.marginRateOrAmount}'.trim()),
                if (r.validateAppliedRule)
                  const DocDetailRow(label: 'Validate applied rule', value: 'Yes'),
                if (r.thresholdPercentage != 0)
                  DocDetailRow(
                      label: 'Suggestion threshold', value: '${r.thresholdPercentage}%'),
                if (r.applyDiscountOnRate)
                  const DocDetailRow(label: 'Discount on discounted rate', value: 'Yes'),
              ],
            ),
        ],
      );
    });
  }
}
```

If `DocDetailRow` has no `const` constructor, drop the `const` keywords on those rows.

- [ ] **Step 9: Page** — import binding + screen in `app_pages.dart`, add after PRICING_RULE:
```dart
    GetPage(
      name: AppRoutes.PRICING_RULE_FORM,
      page: () => const PricingRuleFormScreen(),
      binding: PricingRuleFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
```

- [ ] **Step 10: Run tests**

Run: `flutter test test/unit/pricing_rule_form_controller_test.dart test/widget/pricing_rule_form_screen_test.dart`
Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add lib/app/modules/pricing/pricing_rule/form lib/app/data/routes/app_pages.dart test/unit/pricing_rule_form_controller_test.dart test/widget/pricing_rule_form_screen_test.dart
git commit -m "feat(pricing): Pricing Rule form

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Item form "Prices" tab

**Files:**
- Create: `lib/app/modules/item/form/widgets/item_prices_tab.dart`
- Modify: `lib/app/modules/item/form/item_tab_controller.dart` (length 5 → 6)
- Modify: `lib/app/modules/item/form/item_form_controller.dart` (state, `onTabChanged` case 5, `fetchPricing`, open/add actions)
- Modify: `lib/app/modules/item/form/item_form_screen.dart` (Tab + TabBarView child)
- Test: `test/widget/item_prices_tab_test.dart`

**Interfaces:**
- Consumes: `ItemPriceRow` (Task 5), `PricingRuleRow` (Task 7), `ItemPriceProvider.getItemPrices`, `PricingRuleProvider.rulesForItem` (Task 4), `Item.hasVariants` (Task 3), `AppRoutes.ITEM_PRICE_FORM/PRICING_RULE_FORM`.
- Produces: `ItemPricesTab({required bool isTemplate, required bool isLoading, required List<ItemPrice> prices, required List<PricingRule> rules, required bool pricesVisible, required bool rulesVisible, required bool canAddPrice, required ValueChanged<ItemPrice> onOpenPrice, required VoidCallback onAddPrice, required ValueChanged<PricingRule> onOpenRule})` — controller-free.

- [ ] **Step 1: Write the failing widget test** — `test/widget/item_prices_tab_test.dart`

```dart
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
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/widget/item_prices_tab_test.dart`
Expected: FAIL — widget missing.

- [ ] **Step 3: `lib/app/modules/item/form/widgets/item_prices_tab.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/pricing/widgets/item_price_row.dart';
import 'package:multimax/app/modules/pricing/widgets/pricing_rule_row.dart';

/// Body of the Item form's "Prices" tab (DESIGN_SPEC §E). Controller-free.
class ItemPricesTab extends StatelessWidget {
  const ItemPricesTab({
    super.key,
    required this.isTemplate,
    required this.isLoading,
    required this.prices,
    required this.rules,
    required this.pricesVisible,
    required this.rulesVisible,
    required this.canAddPrice,
    required this.onOpenPrice,
    required this.onAddPrice,
    required this.onOpenRule,
  });

  final bool isTemplate;
  final bool isLoading;
  final List<ItemPrice> prices;
  final List<PricingRule> rules;
  final bool pricesVisible;
  final bool rulesVisible;
  final bool canAddPrice;
  final ValueChanged<ItemPrice> onOpenPrice;
  final VoidCallback onAddPrice;
  final ValueChanged<PricingRule> onOpenRule;

  static String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    final s = context.scheme;
    const groupNote = 'Rules on item groups are not listed here.';

    return ListView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        if (!pricesVisible && !rulesVisible)
          const FormEmptyState(
            icon: Icons.lock_outline,
            message: "You don't have access to item prices or pricing rules.",
          ),
        if (pricesVisible)
          DocSectionCard(
            title: 'Item prices',
            margin: const EdgeInsets.only(bottom: 12),
            headerAction: prices.isEmpty
                ? null
                : Text(_count(prices.length, 'price'),
                    style: TextStyle(fontSize: 11, color: s.textSubtle)),
            children: [
              if (isTemplate)
                const FormEmptyState(
                  icon: Icons.layers_outlined,
                  title: 'Prices are set on variants',
                  message:
                      'This is a template. Open a variant to see or add its price.',
                )
              else if (prices.isEmpty)
                FormEmptyState(
                  icon: Icons.sell_outlined,
                  title: 'No price set',
                  message: "Most items have no price yet — that's normal.",
                  action: canAddPrice
                      ? FilledButton.icon(
                          onPressed: onAddPrice,
                          icon: const Icon(Icons.add),
                          label: const Text('Add price'),
                        )
                      : null,
                )
              else ...[
                for (final p in prices)
                  ItemPriceRow(price: p, onTap: () => onOpenPrice(p)),
                if (canAddPrice)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: onAddPrice,
                      icon: const Icon(Icons.add),
                      label: const Text('Add price'),
                    ),
                  ),
              ],
            ],
          ),
        if (rulesVisible)
          DocSectionCard(
            title: 'Pricing rules',
            margin: EdgeInsets.zero,
            headerAction: rules.isEmpty
                ? null
                : Text(_count(rules.length, 'rule'),
                    style: TextStyle(fontSize: 11, color: s.textSubtle)),
            children: [
              if (rules.isEmpty)
                FormEmptyState(
                  icon: Icons.percent,
                  title: isTemplate
                      ? 'No rules name this template'
                      : 'No rules name this item',
                  message: groupNote,
                )
              else ...[
                for (final r in rules)
                  PricingRuleRow(rule: r, onTap: () => onOpenRule(r)),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(groupNote,
                      style: TextStyle(fontSize: 11, color: s.textSubtle)),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the widget test**

Run: `flutter test test/widget/item_prices_tab_test.dart`
Expected: PASS. (In "no price", the empty-state message and `groupNote` are different strings, so `find.text(...)` stays unambiguous.)

- [ ] **Step 5: Wire the controller** — `item_form_controller.dart` (hand-edit):

Add imports (skip any already present — duplicate imports fail analyze):
```dart
import 'package:multimax/app/data/models/item_price_model.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
```
Add state after the re-order block:
```dart
  // ── Prices tab ────────────────────────────────────────────────────────────
  var itemPrices = <ItemPrice>[].obs;
  var itemRules = <PricingRule>[].obs;
  var isLoadingPricing = false.obs;

  /// False once the server denies the DocType (Sales/Stock Users get 403 on
  /// Item Price) — the section hides instead of erroring.
  var pricesVisible = true.obs;
  var rulesVisible = true.obs;
  bool _pricesTabLoaded = false;
```
In `onTabChanged` add before the closing brace of the switch:
```dart
      case 5:
        if (!_pricesTabLoaded) {
          _pricesTabLoaded = true;
          fetchPricing();
        }
        break;
```
Add methods:
```dart
  Future<void> fetchPricing() async {
    if (itemCode.isEmpty) return;
    // The Item form can open as a sheet without ItemFormBinding.
    if (!Get.isRegistered<ItemPriceProvider>()) {
      Get.lazyPut<ItemPriceProvider>(() => ItemPriceProvider(), fenix: true);
    }
    if (!Get.isRegistered<PricingRuleProvider>()) {
      Get.lazyPut<PricingRuleProvider>(() => PricingRuleProvider(), fenix: true);
    }
    isLoadingPricing.value = true;
    try {
      await Future.wait([_loadItemPrices(), _loadItemRules()]);
    } finally {
      isLoadingPricing.value = false;
    }
  }

  Future<void> _loadItemPrices() async {
    if (Get.find<PermissionService>().hasAccess('Item Price') == false) {
      pricesVisible.value = false;
      return;
    }
    if (item.value?.hasVariants == true) {
      itemPrices.clear();
      return;
    }
    try {
      final res = await Get.find<ItemPriceProvider>().getItemPrices(
        limit: 0,
        filters: [
          ['Item Price', 'item_code', '=', itemCode]
        ],
        orderBy: 'price_list asc',
      );
      itemPrices.assignAll([
        for (final e in (res.data['data'] as List?) ?? const [])
          ItemPrice.fromJson(Map<String, dynamic>.from(e as Map)),
      ]);
      pricesVisible.value = true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        pricesVisible.value = false;
      } else {
        GlobalSnackbar.error(message: 'Could not load item prices');
      }
    }
  }

  Future<void> _loadItemRules() async {
    if (Get.find<PermissionService>().hasAccess('Pricing Rule') == false) {
      rulesVisible.value = false;
      return;
    }
    try {
      itemRules.assignAll(await Get.find<PricingRuleProvider>()
          .rulesForItem(itemCode, item.value?.variantOf));
      rulesVisible.value = true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        rulesVisible.value = false;
      } else {
        GlobalSnackbar.error(message: 'Could not load pricing rules');
      }
    }
  }

  Future<void> openItemPrice(ItemPrice price) async {
    await Get.toNamed(AppRoutes.ITEM_PRICE_FORM,
        arguments: {'name': price.name, 'mode': 'edit'});
    fetchPricing();
  }

  Future<void> addItemPrice() async {
    await Get.toNamed(AppRoutes.ITEM_PRICE_FORM,
        arguments: {'name': '', 'mode': 'new', 'item_code': itemCode});
    fetchPricing();
  }

  Future<void> openPricingRule(PricingRule rule) async {
    await Get.toNamed(AppRoutes.PRICING_RULE_FORM,
        arguments: {'name': rule.name, 'mode': 'edit'});
    fetchPricing();
  }
```
(`dio` and `GlobalSnackbar` are already imported in this file.)

- [ ] **Step 6: Tabs** — `item_tab_controller.dart`: `TabController(length: 6, vsync: this)`.
`item_form_screen.dart`: add imports for `permission_service.dart` and `widgets/item_prices_tab.dart`; add `Tab(text: 'Prices'),` after `Tab(text: 'Re-order'),`; add the last TabBarView child after `_buildReorderTab(context, item, cs),`:
```dart
                          Obx(() => ItemPricesTab(
                                isTemplate: item.hasVariants,
                                isLoading: controller.isLoadingPricing.value,
                                prices: controller.itemPrices.toList(),
                                rules: controller.itemRules.toList(),
                                pricesVisible: controller.pricesVisible.value,
                                rulesVisible: controller.rulesVisible.value,
                                canAddPrice: Get.find<PermissionService>()
                                        .hasAccess('Item Price',
                                            permType: 'create') ==
                                    true,
                                onOpenPrice: controller.openItemPrice,
                                onAddPrice: controller.addItemPrice,
                                onOpenRule: controller.openPricingRule,
                              )),
```

- [ ] **Step 7: Run the Item form tests**

Run: `flutter test test/widget/item_prices_tab_test.dart test/unit/item_form_reorder_controller_test.dart test/widget/reorder_tab_test.dart`
Expected: PASS. Then `grep -rn "length: 5\|Re-order')" test` — update any test that counts Item form tabs.

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/item/form test/widget/item_prices_tab_test.dart
git commit -m "feat(item): Prices tab with item prices and pricing rules

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Navigation, permissions, search, deviations, full verification

**Files:**
- Modify: `lib/app/data/constants/permission_entries.dart` (`kSellingPermissions`)
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart` (Selling group children, ~line 418)
- Modify: `lib/app/data/constants/global_search_targets.dart` (`kGlobalSearchTargets`)
- Modify: `test/unit/global_search_targets_test.dart`
- Modify: `docs/design_handoff_item_price_pricing_rule/README.md` (append "Build deviations")

**Interfaces:**
- Consumes: routes from Task 5, screens from Tasks 5–8.
- Produces: drawer entries Selling › Pricing › Item Price / Pricing Rule; Pricing Rule in global search.

- [ ] **Step 1: Write the failing test** — in `test/unit/global_search_targets_test.dart`, add `'Pricing Rule',` to the `view-mode doctypes pass name + mode:view` list, and add a test in the same group:
```dart
    test('Pricing Rule opens its form in view mode; Item Price is not searchable', () {
      expect(_byDoctype('Pricing Rule').route, AppRoutes.PRICING_RULE_FORM);
      expect(
        kGlobalSearchTargets.any((t) => t.doctype == 'Item Price'),
        isFalse,
        reason: 'Item Price names are random hashes',
      );
    });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/unit/global_search_targets_test.dart`
Expected: FAIL — no Pricing Rule target.

- [ ] **Step 3: Search target** — append to `kGlobalSearchTargets` (after ToDo):
```dart
  GlobalSearchTarget(
    doctype: 'Pricing Rule',
    label: 'Pricing Rules',
    icon: Icons.discount_outlined,
    color: Colors.deepOrange,
    route: AppRoutes.PRICING_RULE_FORM,
    argsFor: _nameView,
  ),
```
The form controller treats `mode: 'view'` as read-only; users with write access can reopen from the list (which opens `edit`). This matches the other view-mode targets.

- [ ] **Step 4: Permissions** — extend `kSellingPermissions`:
```dart
const List<PermEntry> kSellingPermissions = [
  (doctype: 'POS Upload', permType: 'read'),
  (doctype: 'POS Upload', permType: 'report'), // POS & DN Item Rate report
  (doctype: 'Item Price',   permType: 'read'),   // Selling › Pricing (Sales/Purchase Master Manager)
  (doctype: 'Item Price',   permType: 'create'), // New price FAB
  (doctype: 'Item Price',   permType: 'write'),  // Edit / Delete (delete roles == write roles)
  (doctype: 'Pricing Rule', permType: 'read'),   // Selling › Pricing (Sales/Purchase/Accounts Manager)
  (doctype: 'Pricing Rule', permType: 'create'), // New rule FAB
  (doctype: 'Pricing Rule', permType: 'write'),  // Edit / Delete
];
```

- [ ] **Step 5: Drawer** — in the Selling `_ModuleGroup` children, insert BEFORE the `// ── Selling > Reports` comment:
```dart
                      // ── Selling > Pricing ────────────────────────────────────
                      _GuardedSection(
                        doctypes: ['Item Price', 'Pricing Rule'],
                        permType: 'read',
                        children: [
                          const _NavSubheading('Pricing'),
                          DocTypeGuard(
                            doctype: 'Item Price',
                            loading: skeleton,
                            child: _DrawerItem(
                              title: 'Item Price',
                              icon: Icons.sell_outlined,
                              route: AppRoutes.ITEM_PRICE,
                              currentRoute: currentRoute,
                            ),
                          ),
                          DocTypeGuard(
                            doctype: 'Pricing Rule',
                            loading: skeleton,
                            child: _DrawerItem(
                              title: 'Pricing Rule',
                              icon: Icons.discount_outlined,
                              route: AppRoutes.PRICING_RULE,
                              currentRoute: currentRoute,
                            ),
                          ),
                        ],
                      ),
```
Read `_GuardedSection.build` (~line 673) first and confirm it hides when none of `doctypes` is readable — it is the same pattern as the Reports section below.

- [ ] **Step 6: Build deviations** — append to `docs/design_handoff_item_price_pricing_rule/README.md`:
```markdown

## 6. Build deviations (mockup / build prompt vs. what shipped)

- Summary sentence follows the Claude Design notes grammar (supersedes the build prompt's), money as currency CODE (`AED 25.00`), not a symbol.
- `validatePricingRule` / `validateItemPrice` return `field → message` maps (not `List<String>`) so errors sit under fields and tabs get an error dot; messages mirror the server text, not the mockup copy ("Max must be at least min (50)").
- Models are mutable and edited through `Rx.update`; no `copyWith`.
- Item Price search: digits-only → `item_code like`, else `item_name like` (keeps `or_filters` free for the Active validity filter).
- Filter sheet: validity is single-choice (Any/Active/Upcoming/Expired); price list lives only in the header chips; "Has customer or supplier" = `reference is set`.
- Status counts: Active is derived (all − disabled − upcoming − expired).
- Rows use `GenericDocumentCard` (new `trailing` / `body` slots): item NAME is the title and CODE the mono subtitle (mockup had code above name); no status accent stripe.
- Delete is a header icon (like ToDo), not a ⋯ overflow menu.
- Pricing Rule form: Side and For are stacked (not a 120/1fr row); Brand segment stays enabled (0 brands → empty picker); the unit chip toggles: tap a set unit to clear it ("Any unit"), tap "Any unit" to pick.
- Discount amount suffix is "per unit" (ERPNext applies `discount_amount` to the item rate), not "per line".
- Priority picker has no "In use: P3 …" note.
- Item form Prices tab reuses the full list rows (`ItemPriceRow`, `PricingRuleRow`) instead of compact rows.
- Pricing Rule list refetches the page after the form closes (rules are few) instead of patching one row.
- New Item Price defaults to the list named `Standard Selling` (ERPNext setup-wizard name), else the first enabled list.
- UNVERIFIED on the live site: child-table fields (`` `tabPricing Rule Item Code`.`item_code` ``) through `/api/resource` for list targets and `rulesForItem`; on failure rows fall back to "on items".
```

- [ ] **Step 7: Run the search test**

Run: `flutter test test/unit/global_search_targets_test.dart`
Expected: PASS.

- [ ] **Step 8: Full verification (sequential, never concurrent)**

Run: `flutter analyze`
Expected: no errors; no new warnings/infos in files this plan touched (compare with `git stash`-free baseline: `git diff --name-only 273447f1` and check each listed file in the analyze output).

Then run: `flutter test`
Expected: all green. Record the pass/fail counts for the final report. If pre-existing failures appear, confirm they also fail on `273447f1` (`git worktree add` a throwaway copy) before calling them pre-existing.

- [ ] **Step 9: Commit**

```bash
git branch --show-current
git add lib/app/data/constants lib/app/modules/global_widgets/app_nav_drawer.dart test/unit/global_search_targets_test.dart docs/design_handoff_item_price_pricing_rule/README.md
git commit -m "feat(pricing): Selling > Pricing drawer entries, permissions and search

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## After the plan (controller, not a subagent task)

- On-device smoke (side-by-side install per memory `feedback-side-by-side-smoke-install`): a Sales Master Manager account AND a Sales-User-only account (Pricing entries hidden, Item Prices tab sections hidden, no red screens).
- Live round-trip on erp.multimax.cloud — **ask the user before any write**: create a Standard Selling price for a variant with `valid_upto` → edit → duplicate attempt shows the server banner → delete; create a `disable=1` test Pricing Rule → edit → delete.
- Versioning: MINOR at release time per `docs/versioning_conventions.md` — not part of this plan.
