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
