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
