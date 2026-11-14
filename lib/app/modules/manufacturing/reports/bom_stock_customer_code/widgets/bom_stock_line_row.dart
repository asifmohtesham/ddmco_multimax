import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// A condensed item line inside a Customer Code group.
class BomStockLineRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const BomStockLineRow({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final short = BomStockCustomerCodeController.isShortfall(row);
    final accent = coverageAccent(context, short);

    final itemName = (row['item_name'] ?? '').toString();
    final itemCode = (row['item_code'] ?? '').toString();
    final itemGroup = (row['item_group'] ?? '').toString();
    final inStock = toNum(row['in_stock_qty']);
    final avail = toNum(row['running_total']);
    final need = toNum(row['required_qty']);
    final shortage = toNum(row['shortage_qty']) ?? 0;
    final subline = [itemCode, itemGroup].where((s) => s.isNotEmpty).join(' · ');

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
          Text(itemName.isEmpty ? itemCode : itemName,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (subline.isNotEmpty)
            Text(subline,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatCell(label: 'In Stock', value: formatQty(inStock)),
              StatCell(label: 'Avail', value: formatQty(avail), alert: short),
              StatCell(label: 'Need', value: formatQty(need)),
              StatCell(label: 'Short', value: formatQty(shortage), alert: shortage > 0),
            ],
          ),
        ],
      ),
    );
  }
}
