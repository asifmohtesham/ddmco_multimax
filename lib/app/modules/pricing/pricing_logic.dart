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
