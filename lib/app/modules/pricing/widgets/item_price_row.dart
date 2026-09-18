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
