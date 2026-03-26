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
/// Accepts an [ItemCardData] value object and three optional callbacks.
/// The widget has zero knowledge of any controller or DocType model;
/// all state decisions are pre-computed by the caller and supplied
/// through [data].
///
/// Layout: three semantic zones stacked vertically inside the card body:
///
///   Zone 1 — Identity    : item code + name, optional Variant Of chip
///   Zone 2 — Operational : Batch No, rack arrow pair, warehouse arrow pair
///   Zone 3 — Financial   : Qty, Rate, Amount (compact chips)
///
/// Each zone is implemented as a private [StatelessWidget] that receives
/// only the fields it needs, keeping [build] as a thin scaffold.
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

  /// Called when the card body is tapped (e.g. PR edit-on-tap).
  final VoidCallback? onTap;

  /// Called when the edit icon button is pressed.
  /// Shown only when [ItemCardData.isEditable] is true.
  final VoidCallback? onEdit;

  /// Called when the delete icon button is pressed.
  /// Shown only when [ItemCardData.isEditable] is true.
  final VoidCallback? onDelete;

  /// When true, a [CircularProgressIndicator] replaces the edit button.
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
    final cs        = Theme.of(context).colorScheme;
    final hasVariant = variantOf != null && variantOf!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Item code + name (ShureTechMono, slashedZero, bold)
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

        // Variant Of chip — ERPNext custom field 'custom_variant_of'
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
///
/// Renders nothing (zero height) when no operational field is set,
/// so DN/PO/PS cards with no batch/rack/warehouse incur no extra spacing.
class _OperationalZone extends StatelessWidget {
  final String? batchNo;
  final String? rack;
  final String? toRack;
  final String? warehouse;
  final String? toWarehouse;

  /// Per-DocType warehouse label resolved by caller from [ItemCardData.warehouseLabel].
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

          // Batch No
          if (hasBatch)
            DocItemMetaChip(
              icon:  Icons.label_outline,
              label: 'Batch No: $batchNo',
              role:  MetaChipRole.batch,
              size:  MetaChipSize.standard,
            ),

          // Rack arrow pair: Source Rack [→] Target Rack
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

          // Warehouse arrow pair: warehouseLabel [→] Target Warehouse
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
///
/// Qty is always shown. Rate and Amount are shown only when non-null.
/// Label strings are passed in pre-resolved by [DocItemCard.build]
/// from [ItemCardData.qtyLabel] / [rateLabel] (fallbacks already applied).
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

          // Qty — always shown
          DocItemMetaChip(
            icon:  Icons.numbers,
            label: '$qtyLabel: ${_fmt.format(qty)}'
                   '${uom != null ? '  $uom' : ''}',
            role:  MetaChipRole.qty,
            size:  MetaChipSize.compact,
          ),

          // Rate
          if (rate != null)
            DocItemMetaChip(
              icon:  Icons.attach_money,
              label: '$rateLabel: ${_fmt.format(rate)}',
              role:  MetaChipRole.rate,
              size:  MetaChipSize.compact,
            ),

          // Amount
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
// MetaChipSize  —  two-tier size scale for chips
// ─────────────────────────────────────────────────────────────────────────────────

/// Controls the visual weight of a [DocItemMetaChip].
///
/// - [standard] — default; used for identity and operational chips.
/// - [compact]  — reduced padding/font; used for financial chips.
enum MetaChipSize {
  /// Horizontal padding 6, vertical 3, font 12.
  standard,
  /// Horizontal padding 5, vertical 2, font 11.
  compact,
}

// ─────────────────────────────────────────────────────────────────────────────────
// MetaChipRole  —  semantic colour slots
// ─────────────────────────────────────────────────────────────────────────────────

/// Semantic role assigned to each [DocItemMetaChip].
/// Maps to a distinct [colorScheme] colour pair so chips are
/// visually distinguishable without relying on raw colours.
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
///
/// Colour is driven entirely by [role] → [colorScheme] token mapping.
/// Size is controlled by [size]: use [MetaChipSize.compact] for financial
/// chips and [MetaChipSize.standard] (default) for all others.
///
/// Promoted as a named export so it can be reused in edit sheets
/// and other contexts that need the same visual language.
class DocItemMetaChip extends StatelessWidget {
  final IconData      icon;
  final String        label;
  final MetaChipRole  role;
  final MetaChipSize  size;

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
              fontSize: fontSize,
              color:    col.text,
              fontFamily: 'ShureTechMono',
              fontFeatures: const [FontFeature.slashedZero()],
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
