import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// One card per row of the BOM Stock with Customer Code report.
class BomStockTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const BomStockTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final shortfall = BomStockCustomerCodeController.isShortfall(row);

    final image    = (row['image'] ?? '').toString();
    final itemName = (row['item_name'] ?? '').toString();
    final itemCode = (row['item_code'] ?? '').toString();
    final custCode = (row['customer_code'] ?? '').toString();
    final customer = (row['customer'] ?? '').toString();
    final bom      = (row['bom'] ?? '').toString();
    final inStock  = toNum(row['in_stock_qty']);
    final reqNum   = toNum(row['required_qty']);
    final hasReq   = reqNum != null;
    final running  = toNum(row['running_total']);
    final enough   = row['enough_parts_to_build'];

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: shortfall ? cs.error : cs.outlineVariant.withValues(alpha: 0.4),
            width: shortfall ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _thumb(cs, image),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName.isEmpty ? itemCode : itemName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (itemCode.isNotEmpty)
                        Text(
                          itemCode,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (custCode.isNotEmpty)
                            _chip(cs, Icons.qr_code_2, custCode),
                          if (customer.isNotEmpty)
                            _chip(cs, Icons.person_outline, customer),
                          if (bom.isNotEmpty)
                            _chip(cs, Icons.account_tree_outlined, bom),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric(theme, cs, 'In Stock', formatQty(inStock), false),
                if (hasReq)
                  _metric(theme, cs, 'Required', formatQty(reqNum), shortfall),
                _metric(theme, cs, 'Running', formatQty(running), shortfall),
                if (enough != null)
                  _metric(theme, cs, 'Can Build', enough.toString(), false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(ColorScheme cs, String image) => Container(
        width: 56,
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: image.isEmpty
            ? Icon(Icons.image_not_supported_outlined,
                size: 22, color: cs.outline)
            : Image.network(
                image,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                    Icons.broken_image_outlined, size: 22, color: cs.outline),
              ),
      );

  Widget _chip(ColorScheme cs, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      );

  Widget _metric(
      ThemeData theme, ColorScheme cs, String label, String value, bool alert) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alert ? cs.error : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
