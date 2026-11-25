import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_fields.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// A condensed item line inside a Customer Code group.
class BomStockLineRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final FieldsState? fields;
  const BomStockLineRow({super.key, required this.row, this.fields});

  bool _shows(String key) => fields?.shows(key) ?? true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final short = BomStockCustomerCodeController.isShortfall(row);
    final shortage = toNum(row['shortage_qty']);
    final accent = shortage == null
        ? cs.outlineVariant
        : coverageAccent(context, short);

    final itemName = (row['item_name'] ?? '').toString();
    final itemCode = (row['item_code'] ?? '').toString();
    final itemGroup = (row['item_group'] ?? '').toString();
    final inStock = toNum(row['in_stock_qty']);
    final avail = toNum(row['running_total']);
    final need = toNum(row['required_qty']);
    final showItemGroup = _shows('item_group') && itemGroup.isNotEmpty;
    final itemTitle = itemName.isEmpty ? itemCode : itemName;
    final itemTitleKey = itemName.isEmpty ? 'item_code' : 'item_name';
    final subline = [
      itemCode,
      if (showItemGroup) itemGroup,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            itemTitle,
            semanticsLabel: itemTitle.isEmpty
                ? null
                : '${bomStockLabel(itemTitleKey, fields)} $itemTitle',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subline.isNotEmpty)
            Text(
              subline,
              semanticsLabel: [
                if (itemCode.isNotEmpty)
                  '${bomStockLabel('item_code', fields)} $itemCode',
                if (showItemGroup)
                  '${bomStockLabel('item_group', fields)} $itemGroup',
              ].join(', '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (key, value, alert) in [
                ('in_stock_qty', inStock, false),
                ('running_total', avail, short),
                ('required_qty', need, false),
                ('shortage_qty', shortage, short),
              ])
                if (key == 'shortage_qty' || _shows(key))
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: StatCell(
                        label: bomStockLabel(key, fields),
                        value: formatQty(value),
                        alert: alert,
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
