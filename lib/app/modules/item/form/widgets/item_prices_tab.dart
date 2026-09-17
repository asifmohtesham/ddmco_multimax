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
