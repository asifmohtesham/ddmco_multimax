import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// One result card, mirroring the POS Upload form's item tile.
class BomStockTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const BomStockTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shortfall = BomStockCustomerCodeController.isShortfall(row);

    final slNo      = (row['sl_no'] ?? '').toString();
    final itemName  = (row['item_name'] ?? '').toString();
    final itemCode  = (row['item_code'] ?? '').toString();
    final itemGroup = (row['item_group'] ?? '').toString();
    final custCode  = (row['customer_code'] ?? '').toString();
    final bom       = (row['bom'] ?? '').toString();
    final inStock   = toNum(row['in_stock_qty']);
    final reqNum    = toNum(row['required_qty']);
    final hasReq    = reqNum != null;
    final shortage  = toNum(row['shortage_qty']) ?? 0;
    final enough    = row['enough_parts_to_build'];

    final subline = [itemCode, itemGroup].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: shortfall ? cs.error : cs.outlineVariant),
      ),
      color: cs.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    slNo,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              itemName.isEmpty ? itemCode : itemName,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (hasReq) ...[
                            const SizedBox(width: 8),
                            StatusPill(shortage: shortage),
                          ],
                        ],
                      ),
                      if (subline.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subline,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // ── Stats ────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatCell(label: 'In Stock', value: formatQty(inStock)),
                if (hasReq) StatCell(label: 'Need', value: formatQty(reqNum)),
                if (hasReq)
                  StatCell(label: 'Short', value: formatQty(shortage), alert: shortage > 0),
                if (enough != null)
                  StatCell(label: 'Build', value: enough.toString()),
              ],
            ),
            // ── Chips ────────────────────────────────────────────────────
            if (custCode.isNotEmpty || bom.isNotEmpty) ...[
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (custCode.isNotEmpty)
                        _chip(cs, Icons.qr_code_2, custCode, maxW),
                      if (bom.isNotEmpty)
                        _chip(cs, Icons.account_tree_outlined, bom, maxW),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(ColorScheme cs, IconData icon, String label, double maxWidth) =>
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
}

