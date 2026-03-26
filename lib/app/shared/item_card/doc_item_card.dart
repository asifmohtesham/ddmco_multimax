import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';
import 'package:multimax/app/shared/item_card/doc_item_progress_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────────
// DocItemCard
// ─────────────────────────────────────────────────────────────────────────────────

/// Shared stateless item-card widget for all DocType form screens.
///
/// Layout: three semantic zones stacked vertically inside the card body:
///
///   Zone 1 — Identity    : item code + name, optional Variant Of chip
///   Zone 2 — Operational : Batch No, rack arrow pair, warehouse arrow pair
///   Zone 3 — Financial   : Qty, Rate, Amount (compact chips)
///
/// Usage:
/// ```dart
/// DocItemCard(
///   data: ItemCardData.fromDeliveryNoteItem(
///     item,
///     index: groupIndex,
///     isEditable: controller.deliveryNote.value?.docstatus == 0,
///     isHighlighted: isRecentlyAdded,
///   ),
///   onEdit:   () => controller.editItem(item),
///   onDelete: () => controller.confirmAndDeleteItem(item),
/// )
/// ```
class DocItemCard extends StatelessWidget {
  final ItemCardData data;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isLoadingEdit;

  const DocItemCard({
    super.key,
    required this.data,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.isLoadingEdit = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: data.isHighlighted
            ? cs.tertiaryContainer.withValues(alpha: 0.35)
            : cs.surface,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: .06),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Index badge ───────────────────────────────────────────────
              if (data.index != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      '${data.index! + 1}',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // ── Content: three zones ───────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityZone(
                      itemCode:  data.itemCode,
                      itemName:  data.itemName,
                      variantOf: data.variantOf,
                    ),
                    _OperationalZone(
                      batchNo:        data.batchNo,
                      rack:           data.rack,
                      toRack:         data.toRack,
                      warehouse:      data.warehouse,
                      toWarehouse:    data.toWarehouse,
                      warehouseLabel: data.warehouseLabel ?? 'Warehouse',
                    ),
                    _FinancialZone(
                      qty:       data.qty,
                      uom:       data.uom,
                      qtyLabel:  data.qtyLabel  ?? 'Qty',
                      rate:      data.rate,
                      rateLabel: data.rateLabel ?? 'Rate',
                      amount:    data.amount,
                    ),
                    if (data.targetQty != null && data.targetQty! > 0)
                      DocItemProgressBar(
                        qty:       data.qty,
                        targetQty: data.targetQty!,
                        uom:       data.uom,
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ── Right: actions ──────────────────────────────────────────
              if (data.isEditable)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: isLoadingEdit
                          ? const Padding(
                              padding: EdgeInsets.all(7.0),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : onEdit != null
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(Icons.edit,
                                      color: cs.primary, size: 20),
                                  onPressed: onEdit,
                                )
                              : const SizedBox.shrink(),
                    ),
                    if (onDelete != null)
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.delete_outline,
                              color: cs.error, size: 20),
                          tooltip: 'Remove item',
                          onPressed: onDelete,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────────
// _IdentityZone
// ─────────────────────────────────────────────────────────────────────────────────

/// Zone 1: item code + name headline, optional Variant Of chip.
class _IdentityZone extends StatelessWidget {
  final String  itemCode;
  final String? itemName;
  final String? variantOf;

  const _IdentityZone({
    required this.itemCode,
    this.itemName,
    this.variantOf,
  });

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final hasVariant = variantOf != null && variantOf!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(
                text: itemCode,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'ShureTechMono',
                  fontFeatures: const [FontFeature.slashedZero()],
                  color: cs.onSurface,
                ),
              ),
              if (itemName != null && itemName!.isNotEmpty)
                TextSpan(
                  text: ': $itemName',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'ShureTechMono',
                    color: cs.onSurface,
                  ),
                ),
            ],
          ),
        ),
        if (hasVariant) ...[
          const SizedBox(height: 4),
          DocItemMetaChip(
            icon:  Icons.account_tree_outlined,
            label: 'Variant Of: $variantOf',
            role:  MetaChipRole.variantOf,
            size:  MetaChipSize.standard,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────────
// _OperationalZone
// ─────────────────────────────────────────────────────────────────────────────────

/// Zone 2: Batch No, rack arrow pair, warehouse arrow pair.
/// Returns [SizedBox.shrink] when no operational field is present.
class _OperationalZone extends StatelessWidget {
  final String? batchNo;
  final String? rack;
  final String? toRack;
  final String? warehouse;
  final String? toWarehouse;
  final String  warehouseLabel;

  const _OperationalZone({
    this.batchNo,
    this.rack,
    this.toRack,
    this.warehouse,
    this.toWarehouse,
    required this.warehouseLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bool hasBatch       = batchNo    != null && batchNo!.isNotEmpty;
    final bool hasSourceRack  = rack        != null && rack!.isNotEmpty;
    final bool hasTargetRack  = toRack      != null && toRack!.isNotEmpty;
    final bool hasWarehouse   = warehouse   != null && warehouse!.isNotEmpty;
    final bool hasToWarehouse = toWarehouse != null && toWarehouse!.isNotEmpty;

    if (!hasBatch && !hasSourceRack && !hasWarehouse) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (hasBatch)
            DocItemMetaChip(
              icon:  Icons.label_outline,
              label: 'Batch No: $batchNo',
              role:  MetaChipRole.batch,
              size:  MetaChipSize.standard,
            ),
          if (hasSourceRack) ...[
            DocItemMetaChip(
              icon:  Icons.shelves,
              label: 'Source Rack: $rack',
              role:  MetaChipRole.rack,
              size:  MetaChipSize.standard,
            ),
            if (hasTargetRack) ...[
              Icon(Icons.arrow_forward, size: 12, color: cs.outline),
              DocItemMetaChip(
                icon:  Icons.shelves,
                label: 'Target Rack: $toRack',
                role:  MetaChipRole.toRack,
                size:  MetaChipSize.standard,
              ),
            ],
          ],
          if (hasWarehouse) ...[
            DocItemMetaChip(
              icon:  Icons.store_outlined,
              label: '$warehouseLabel: $warehouse',
              role:  MetaChipRole.warehouse,
              size:  MetaChipSize.standard,
            ),
            if (hasToWarehouse) ...[
              Icon(Icons.arrow_forward, size: 12, color: cs.outline),
              DocItemMetaChip(
                icon:  Icons.store_outlined,
                label: 'Target Warehouse: $toWarehouse',
                role:  MetaChipRole.toWarehouse,
                size:  MetaChipSize.standard,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────────
// _FinancialZone
// ─────────────────────────────────────────────────────────────────────────────────

/// Zone 3: Qty, Rate, Amount — all rendered as compact chips.
class _FinancialZone extends StatelessWidget {
  final double  qty;
  final String? uom;
  final String  qtyLabel;
  final double? rate;
  final String  rateLabel;
  final double? amount;

  static final _fmt = NumberFormat('#,##0.##');

  const _FinancialZone({
    required this.qty,
    this.uom,
    required this.qtyLabel,
    this.rate,
    required this.rateLabel,
    this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DocItemMetaChip(
            icon:  Icons.numbers,
            label: '$qtyLabel: ${_fmt.format(qty)}'
                   '${uom != null ? '  $uom' : ''}',
            role:  MetaChipRole.qty,
            size:  MetaChipSize.compact,
          ),
          if (rate != null)
            DocItemMetaChip(
              icon:  Icons.attach_money,
              label: '$rateLabel: ${_fmt.format(rate)}',
              role:  MetaChipRole.rate,
              size:  MetaChipSize.compact,
            ),
          if (amount != null)
            DocItemMetaChip(
              icon:  Icons.receipt_outlined,
              label: 'Amount: ${_fmt.format(amount)}',
              role:  MetaChipRole.amount,
              size:  MetaChipSize.compact,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────────
// MetaChipSize
// ─────────────────────────────────────────────────────────────────────────────────

enum MetaChipSize {
  /// Horizontal padding 6, vertical 3, font 12.
  standard,
  /// Horizontal padding 5, vertical 2, font 11.
  compact,
}

// ─────────────────────────────────────────────────────────────────────────────────
// MetaChipRole
// ─────────────────────────────────────────────────────────────────────────────────

enum MetaChipRole {
  /// Template/parent item identity — amber-tinted (secondary family).
  variantOf,
  qty,
  rate,
  amount,
  batch,
  rack,
  toRack,
  warehouse,
  toWarehouse,
}

// ─────────────────────────────────────────────────────────────────────────────────
// DocItemMetaChip
// ─────────────────────────────────────────────────────────────────────────────────

/// Compact icon + label chip for metadata in a [DocItemCard].
/// Colour driven by [role] → [colorScheme] token mapping.
class DocItemMetaChip extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final MetaChipRole role;
  final MetaChipSize size;

  const DocItemMetaChip({
    super.key,
    required this.icon,
    required this.label,
    required this.role,
    this.size = MetaChipSize.standard,
  });

  static _ChipColours _colours(MetaChipRole role, ColorScheme cs) {
    switch (role) {
      case MetaChipRole.variantOf:
        return _ChipColours(
            bg:     cs.secondaryContainer.withValues(alpha: 0.55),
            border: cs.secondary.withValues(alpha: 0.35),
            icon:   cs.secondary,
            text:   cs.onSecondaryContainer);
      case MetaChipRole.qty:
        return _ChipColours(
            bg:     cs.primaryContainer.withValues(alpha: 0.5),
            border: cs.primary.withValues(alpha: 0.25),
            icon:   cs.primary,
            text:   cs.onPrimaryContainer);
      case MetaChipRole.rate:
        return _ChipColours(
            bg:     cs.secondaryContainer.withValues(alpha: 0.5),
            border: cs.secondary.withValues(alpha: 0.25),
            icon:   cs.secondary,
            text:   cs.onSecondaryContainer);
      case MetaChipRole.amount:
        return _ChipColours(
            bg:     cs.tertiaryContainer.withValues(alpha: 0.5),
            border: cs.tertiary.withValues(alpha: 0.25),
            icon:   cs.tertiary,
            text:   cs.onTertiaryContainer);
      case MetaChipRole.batch:
        return _ChipColours(
            bg:     cs.surfaceContainerHighest,
            border: cs.outline.withValues(alpha: 0.4),
            icon:   cs.onSurfaceVariant,
            text:   cs.onSurface);
      case MetaChipRole.rack:
      case MetaChipRole.toRack:
        return _ChipColours(
            bg:     cs.tertiaryContainer.withValues(alpha: 0.3),
            border: cs.tertiary.withValues(alpha: 0.2),
            icon:   cs.tertiary,
            text:   cs.onTertiaryContainer);
      case MetaChipRole.warehouse:
      case MetaChipRole.toWarehouse:
        return _ChipColours(
            bg:     cs.secondaryContainer.withValues(alpha: 0.3),
            border: cs.secondary.withValues(alpha: 0.2),
            icon:   cs.secondary,
            text:   cs.onSecondaryContainer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final col = _colours(role, cs);

    final EdgeInsets pad  = size == MetaChipSize.compact
        ? const EdgeInsets.symmetric(horizontal: 5, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final double fontSize = size == MetaChipSize.compact ? 11.0 : 12.0;
    final double iconSize = size == MetaChipSize.compact ? 11.0 : 12.0;

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color:  col.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: col.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: col.icon),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize:     fontSize,
              color:        col.text,
              fontFamily:   'ShureTechMono',
              fontFeatures: const [FontFeature.slashedZero()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────────
// _LabelValueCell
// ─────────────────────────────────────────────────────────────────────────────────

/// A small labelled-value cell: muted label on top, prominent value below.
///
/// Visual anatomy:
/// ```
/// ┌────────────────────────┐
/// │ ⚪ label         10px, onSurfaceVariant  │
/// │ VALUE-STRING     13px, w600, role colour │
/// └────────────────────────┘
/// ```
///
/// - Background and border tint come from the same [MetaChipRole] →
///   [_ChipColours] mapping used by [DocItemMetaChip], ensuring colour
///   consistency across both chip styles.
/// - [isMonospace] (default `true`) applies ShureTechMono + slashedZero
///   to the value text. Set to `false` for natural-language values.
/// - [icon] is optional; when supplied it appears inline before the label
///   text at 10 px in [_ChipColours.icon] colour.
class _LabelValueCell extends StatelessWidget {
  final String       label;
  final String       value;
  final MetaChipRole role;
  final IconData?    icon;
  final bool         isMonospace;

  const _LabelValueCell({
    required this.label,
    required this.value,
    required this.role,
    this.icon,
    this.isMonospace = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final col = DocItemMetaChip._colours(role, cs); // reuse same colour helper

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color:        col.bg,
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: col.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Label row ────────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 10, color: col.icon),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color:    cs.onSurfaceVariant,
                  fontFamily:   'ShureTechMono',
                  fontFeatures: const [FontFeature.slashedZero()],
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // ── Value row ────────────────────────────────────────
          Text(
            value,
            style: TextStyle(
              fontSize:     13,
              fontWeight:   FontWeight.w600,
              color:        col.text,
              fontFamily:   isMonospace ? 'ShureTechMono' : null,
              fontFeatures: isMonospace
                  ? const [FontFeature.slashedZero()]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal colour bundle — keeps the switch statement readable.
class _ChipColours {
  final Color bg;
  final Color border;
  final Color icon;
  final Color text;
  const _ChipColours({
    required this.bg,
    required this.border,
    required this.icon,
    required this.text,
  });
}
