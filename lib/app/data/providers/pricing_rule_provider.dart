import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/item_price_model.dart' show pricingLink;
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
      } catch (e) {
        // Rows still render; see doc comment.
        debugPrint('PricingRuleProvider.attachTargets(${entry.key}) failed: $e');
      }
    }
  }

  /// Fills the client-only `label` (item name) and `variantOf` on Item Code
  /// targets read back from the server — the child table carries only the
  /// code, so a reloaded rule would otherwise show bare codes and skip the
  /// variant-vs-template check. Best-effort: on failure rows keep the code.
  Future<void> attachItemLabels(List<PricingRuleTarget> targets) async {
    final codes = [
      for (final t in targets)
        if (t.label == null && t.value.isNotEmpty) t.value
    ];
    if (codes.isEmpty) return;
    try {
      final res = await _api.getDocumentList(
        'Item',
        limit: 0,
        fields: const ['name', 'item_name', 'variant_of'],
        filterTuples: [
          ['Item', 'name', 'in', codes],
        ],
      );
      final rows = {
        for (final row in (res.data['data'] as List?) ?? const [])
          if (row is Map) (row['name'] ?? '').toString(): row,
      };
      for (final t in targets) {
        final row = rows[t.value];
        if (row == null) continue;
        t.label = pricingLink(row['item_name']);
        t.variantOf = pricingLink(row['variant_of']);
      }
    } catch (e) {
      debugPrint('PricingRuleProvider.attachItemLabels failed: $e');
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
