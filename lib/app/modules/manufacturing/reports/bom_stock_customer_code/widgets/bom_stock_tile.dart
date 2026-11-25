import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_fields.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// One result card, mirroring the POS Upload form's item tile.
class BomStockTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final FieldsState? fields;
  const BomStockTile({super.key, required this.row, this.fields});

  bool _shows(String key) => fields?.shows(key) ?? true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shortfall = BomStockCustomerCodeController.isShortfall(row);

    final slNo = (row['sl_no'] ?? '').toString();
    final itemName = (row['item_name'] ?? '').toString();
    final itemCode = (row['item_code'] ?? '').toString();
    final itemGroup = (row['item_group'] ?? '').toString();
    final custCode = (row['customer_code'] ?? '').toString();
    final bom = (row['bom'] ?? '').toString();
    final inStock = toNum(row['in_stock_qty']);
    final reqNum = toNum(row['required_qty']);
    final hasReq = reqNum != null;
    final shortage = toNum(row['shortage_qty']);
    final enough = row['enough_parts_to_build'];

    final showItemGroup = _shows('item_group') && itemGroup.isNotEmpty;
    final itemTitle = itemName.isEmpty ? itemCode : itemName;
    final itemTitleKey = itemName.isEmpty ? 'item_code' : 'item_name';
    final subline = [
      itemCode,
      if (showItemGroup) itemGroup,
    ].where((s) => s.isNotEmpty).join(' · ');
    final stats = <StatCell>[
      if (_shows('in_stock_qty'))
        StatCell(
          label: bomStockLabel('in_stock_qty', fields),
          value: formatQty(inStock),
        ),
      if (hasReq && _shows('required_qty'))
        StatCell(
          label: bomStockLabel('required_qty', fields),
          value: formatQty(reqNum),
        ),
      if (hasReq && (_shows('shortage_qty') || shortage == null))
        StatCell(
          label: bomStockLabel('shortage_qty', fields),
          value: formatQty(shortage),
          alert: shortfall,
        ),
      if (enough != null && _shows('enough_parts_to_build'))
        StatCell(
          label: bomStockLabel('enough_parts_to_build', fields),
          value: enough.toString(),
        ),
    ];

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
                if (_shows('sl_no')) ...[
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      slNo,
                      semanticsLabel: '${bomStockLabel('sl_no', fields)} $slNo',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              itemTitle,
                              semanticsLabel: itemTitle.isEmpty
                                  ? null
                                  : '${bomStockLabel(itemTitleKey, fields)} $itemTitle',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (hasReq && shortage != null) ...[
                            const SizedBox(width: 8),
                            StatusPill(shortage: shortage),
                          ],
                        ],
                      ),
                      if (subline.isNotEmpty) ...[
                        const SizedBox(height: 2),
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
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final stat in stats)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: stat,
                      ),
                    ),
                ],
              ),
            ],
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
