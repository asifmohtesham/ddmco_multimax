import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_fields.dart';

/// Theme-aware accent for a server status. Doubles as pill TEXT, so it uses
/// the x700 (light) / x300 (dark) ramp — never the x500 bases.
Color posDnStatusAccent(BuildContext context, String status) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case PosDnItemRateController.statusNew:
      return dark ? AppColors.green300 : AppColors.green700;
    case PosDnItemRateController.statusNoDelivery:
      return dark ? AppColors.orange300 : AppColors.orange700;
    case PosDnItemRateController.statusMapped:
      return context.scheme.textMuted;
    default: // 'No code' and anything unexpected
      return cs.onSurfaceVariant;
  }
}

/// Status pill: server status text over a 14%-alpha tint of its accent.
class PosDnStatusPill extends StatelessWidget {
  final String status;
  const PosDnStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final accent = posDnStatusAccent(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

/// One report row: (upload line, mapped item_code) with its server status.
class PosDnItemRateTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final FieldsState? fields;
  final Map<String, String> captions;
  const PosDnItemRateTile({
    super.key,
    required this.row,
    this.fields,
    this.captions = const {},
  });

  bool _shows(String key) => fields?.shows(key) ?? true;
  String _caption(String key) => captions[key] ?? posFieldLabel(fields, key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final status = (row['status'] ?? '').toString();
    final refCode = (row['ref_code'] ?? '').toString();
    final itemCode = (row['item_code'] ?? '').toString();
    final itemGroup = _shows('item_group')
        ? (row['item_group'] ?? '').toString()
        : '';
    final dnItem = (row['dn_item'] ?? '').toString();
    final uploadItem = (row['upload_item'] ?? '').toString();
    final customer = (row['customer'] ?? '').toString();
    final custGroup = _shows('customer_group')
        ? (row['customer_group'] ?? '').toString()
        : '';
    final dnName = (row['dn_name'] ?? '').toString();
    final posUpload = (row['pos_upload'] ?? '').toString();
    final idx = (row['idx'] ?? '').toString();

    final customerLine = [
      customer,
      custGroup,
    ].where((s) => s.isNotEmpty).join(' · ');

    final itemImage = (row['item_image'] ?? '').toString();
    final canOpenItem = itemCode.isNotEmpty;
    final statKeys = [
      for (final key in ['upload_qty', 'upload_rate', 'dn_qty'])
        if (_shows(key)) key,
    ];
    final showNames =
        dnItem.isNotEmpty || uploadItem.isNotEmpty || customerLine.isNotEmpty;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      color: cs.surfaceContainerLowest,
      child: InkWell(
        onTap: canOpenItem
            ? () => Get.toNamed(
                AppRoutes.ITEM_FORM,
                arguments: {'itemCode': itemCode},
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero: thumbnail + customer code + status ─────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ItemThumbnail(
                    imageUrl: itemImage.isEmpty ? null : itemImage,
                    itemCode: itemCode,
                    itemName: dnItem.isNotEmpty ? dnItem : uploadItem,
                    size: 40,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onLongPress: refCode.isEmpty
                                      ? null
                                      : () {
                                          Clipboard.setData(
                                            ClipboardData(text: refCode),
                                          );
                                          GlobalSnackbar.success(
                                            title: 'Copied',
                                            message: 'Customer code $refCode',
                                          );
                                        },
                                  child: Semantics(
                                    label: _caption('ref_code'),
                                    child: Text(
                                      refCode.isEmpty ? '—' : refCode,
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'ShureTechMono',
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      (constraints.maxWidth - 8).clamp(
                                        0,
                                        double.infinity,
                                      ) /
                                      2,
                                ),
                                child: Semantics(
                                  label: _caption('status'),
                                  child: PosDnStatusPill(status: status),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (itemCode.isNotEmpty || itemGroup.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (itemCode.isNotEmpty)
                                Semantics(
                                  label: _caption('item_code'),
                                  child: Text(
                                    itemCode,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              if (itemCode.isNotEmpty && itemGroup.isNotEmpty)
                                Text(
                                  ' · ',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              if (itemGroup.isNotEmpty)
                                Semantics(
                                  label: _caption('item_group'),
                                  child: Text(
                                    itemGroup,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (showNames || statKeys.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
              ],

              // ── Item names: the naming gap is the point — show both ──────
              if (dnItem.isNotEmpty)
                _NameRow(label: _caption('dn_item'), value: dnItem),
              if (uploadItem.isNotEmpty)
                _NameRow(label: _caption('upload_item'), value: uploadItem),
              if (customerLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (customer.isNotEmpty)
                      Semantics(
                        label: _caption('customer'),
                        child: Text(
                          customer,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (customer.isNotEmpty && custGroup.isNotEmpty)
                      Text(
                        ' · ',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (custGroup.isNotEmpty)
                      Semantics(
                        label: _caption('customer_group'),
                        child: Text(
                          custGroup,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (statKeys.isNotEmpty) ...[
                if (showNames) const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final key in statKeys)
                      Flexible(
                        child: StatCell(
                          label: _caption(key),
                          value: formatQty(toNum(row[key])),
                        ),
                      ),
                  ],
                ),
              ],

              // ── Voucher links ────────────────────────────────────────────
              if (dnName.isNotEmpty || posUpload.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (dnName.isNotEmpty)
                      _VoucherChip(
                        icon: Icons.local_shipping_outlined,
                        label: dnName,
                        semantics: _caption('dn_name'),
                        onTap: () => Get.toNamed(
                          AppRoutes.DELIVERY_NOTE_FORM,
                          arguments: {'name': dnName, 'mode': 'edit'},
                        ),
                      ),
                    if (posUpload.isNotEmpty)
                      _VoucherChip(
                        icon: Icons.cloud_upload_outlined,
                        label: idx.isEmpty
                            ? posUpload
                            : '$posUpload · ${_caption('idx')} $idx',
                        semantics: _caption('pos_upload'),
                        onTap: () => Get.toNamed(
                          AppRoutes.POS_UPLOAD_FORM,
                          arguments: {'name': posUpload, 'mode': 'edit'},
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NameRow extends StatelessWidget {
  final String label;
  final String value;
  const _NameRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoucherChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback onTap;
  const _VoucherChip({
    required this.icon,
    required this.label,
    required this.semantics,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: semantics,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: cs.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
