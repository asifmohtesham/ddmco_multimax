import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';

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
  /// Pass null to make the card non-tappable.
  final VoidCallback? onTap;

  /// Called when the edit icon button is pressed.
  /// Shown only when [ItemCardData.isEditable] is true.
  final VoidCallback? onEdit;

  /// Called when the delete icon button is pressed.
  /// Shown only when [ItemCardData.isEditable] is true.
  final VoidCallback? onDelete;

  /// When true, a [CircularProgressIndicator] replaces the edit button,
  /// signalling that a server round-trip for this row is in progress.
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Index badge ───────────────────────────────────────────────
              if (data.index != null) ...[
                CircleAvatar(
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
                const SizedBox(width: 10),
              ],

              // ── Left: identity + metadata ───────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item code (always ShureTechMono + slashedZero)
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(
                            text: data.itemCode,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              fontFamily: 'ShureTechMono',
                              fontFeatures: const [FontFeature.slashedZero()],
                              color: cs.onSurface,
                            ),
                          ),
                          if (data.itemName != null &&
                              data.itemName!.isNotEmpty)
                            TextSpan(
                              text: ': ${data.itemName}',
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

                    // variant_of chip
                    if (data.variantOf != null &&
                        data.variantOf!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.3),
                              width: 0.5),
                        ),
                        child: Text(
                          'Variant of: ${data.variantOf!}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSecondaryContainer,
                            fontFamily: 'ShureTechMono',
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 6),

                    // ── Meta chip row ───────────────────────────────────────
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Qty — always shown
                        DocItemMetaChip(
                          icon: Icons.numbers,
                          label:
                              'Qty: ${NumberFormat('#,##0.##').format(data.qty)}'
                              '${data.uom != null ? '  ${data.uom}' : ''}',
                          role: MetaChipRole.qty,
                        ),

                        // Rate
                        if (data.rate != null)
                          DocItemMetaChip(
                            icon: Icons.attach_money,
                            label:
                                'Rate: ${NumberFormat('#,##0.##').format(data.rate)}',
                            role: MetaChipRole.rate,
                          ),

                        // Amount
                        if (data.amount != null)
                          DocItemMetaChip(
                            icon: Icons.receipt_outlined,
                            label:
                                'Amt: ${NumberFormat('#,##0.##').format(data.amount)}',
                            role: MetaChipRole.amount,
                          ),

                        // Batch
                        if (data.batchNo != null &&
                            data.batchNo!.isNotEmpty)
                          DocItemMetaChip(
                            icon: Icons.label_outline,
                            label: 'Batch: ${data.batchNo!}',
                            role: MetaChipRole.batch,
                          ),

                        // Source rack
                        if (data.rack != null && data.rack!.isNotEmpty)
                          DocItemMetaChip(
                            icon: Icons.shelves,
                            label: 'Rack: ${data.rack!}',
                            role: MetaChipRole.rack,
                          ),

                        // Destination rack (SE transfer only)
                        if (data.toRack != null &&
                            data.toRack!.isNotEmpty)
                          DocItemMetaChip(
                            icon: Icons.shelves,
                            label: 'To Rack: ${data.toRack!}',
                            role: MetaChipRole.toRack,
                          ),

                        // Warehouse
                        if (data.warehouse != null &&
                            data.warehouse!.isNotEmpty)
                          DocItemMetaChip(
                            icon: Icons.store_outlined,
                            label: 'WH: ${data.warehouse!}',
                            role: MetaChipRole.warehouse,
                          ),

                        // Destination warehouse (SE only)
                        if (data.toWarehouse != null &&
                            data.toWarehouse!.isNotEmpty)
                          DocItemMetaChip(
                            icon: Icons.store_outlined,
                            label: 'To WH: ${data.toWarehouse!}',
                            role: MetaChipRole.toWarehouse,
                          ),
                      ],
                    ),

                    // ── Progress bar ───────────────────────────────────────
                    // Rendered only when targetQty is provided.
                    // Phase 3 will replace this inline block with
                    // DocItemProgressBar(qty: data.qty, targetQty: data.targetQty!).
                    if (data.targetQty != null && data.targetQty! > 0)
                      _ProgressSection(
                        qty: data.qty,
                        targetQty: data.targetQty!,
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
                    // Edit / loading spinner
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: isLoadingEdit
                          ? const Padding(
                              padding: EdgeInsets.all(7.0),
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
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
                    // Delete
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
// MetaChipRole  —  semantic colour slots
// ─────────────────────────────────────────────────────────────────────────────────

/// Semantic role assigned to each [DocItemMetaChip].
/// Maps to a distinct [colorScheme] colour pair so chips are
/// visually distinguishable without relying on raw colours.
enum MetaChipRole {
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
/// Colour is driven entirely by [role] → [colorScheme] token mapping,
/// so no caller ever passes a raw [Color].
///
/// Promoted as a named export so it can also be used in edit sheets
/// and other contexts that need the same visual language.
class DocItemMetaChip extends StatelessWidget {
  final IconData icon;

  /// Self-explanatory prefixed label, e.g. 'Batch: B-001', 'Rack: R-02'.
  final String label;

  final MetaChipRole role;

  const DocItemMetaChip({
    super.key,
    required this.icon,
    required this.label,
    required this.role,
  });

  /// Maps a [MetaChipRole] to a [_ChipColours] pair from [colorScheme].
  static _ChipColours _colours(
      MetaChipRole role, ColorScheme cs) {
    switch (role) {
      case MetaChipRole.qty:
        return _ChipColours(
            bg: cs.primaryContainer.withValues(alpha: 0.5),
            border: cs.primary.withValues(alpha: 0.25),
            icon: cs.primary,
            text: cs.onPrimaryContainer);
      case MetaChipRole.rate:
        return _ChipColours(
            bg: cs.secondaryContainer.withValues(alpha: 0.5),
            border: cs.secondary.withValues(alpha: 0.25),
            icon: cs.secondary,
            text: cs.onSecondaryContainer);
      case MetaChipRole.amount:
        return _ChipColours(
            bg: cs.tertiaryContainer.withValues(alpha: 0.5),
            border: cs.tertiary.withValues(alpha: 0.25),
            icon: cs.tertiary,
            text: cs.onTertiaryContainer);
      case MetaChipRole.batch:
        return _ChipColours(
            bg: cs.surfaceContainerHighest,
            border: cs.outline.withValues(alpha: 0.4),
            icon: cs.onSurfaceVariant,
            text: cs.onSurface);
      case MetaChipRole.rack:
      case MetaChipRole.toRack:
        return _ChipColours(
            bg: cs.tertiaryContainer.withValues(alpha: 0.3),
            border: cs.tertiary.withValues(alpha: 0.2),
            icon: cs.tertiary,
            text: cs.onTertiaryContainer);
      case MetaChipRole.warehouse:
      case MetaChipRole.toWarehouse:
        return _ChipColours(
            bg: cs.secondaryContainer.withValues(alpha: 0.3),
            border: cs.secondary.withValues(alpha: 0.2),
            icon: cs.secondary,
            text: cs.onSecondaryContainer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = _colours(role, cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: col.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: col.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: col.icon),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: col.text,
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
  const _ChipColours(
      {required this.bg,
      required this.border,
      required this.icon,
      required this.text});
}

// ─────────────────────────────────────────────────────────────────────────────────
// _ProgressSection  —  inline placeholder until Phase 3
// ─────────────────────────────────────────────────────────────────────────────────

/// Inline progress block used by [DocItemCard] until [DocItemProgressBar]
/// (Phase 3) is ready to slot in.
///
/// Phase 3 replaces this class entirely — the call-site in [DocItemCard]
/// is already commented with the replacement instruction.
class _ProgressSection extends StatelessWidget {
  final double qty;
  final double targetQty;

  const _ProgressSection({
    required this.qty,
    required this.targetQty,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (qty / targetQty).clamp(0.0, 1.0);
    final isComplete = percent >= 1.0;
    final isOver = qty > targetQty;

    final Color progressColor = isOver
        ? cs.error
        : isComplete
            ? cs.tertiary
            : cs.primary;

    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isComplete
                    ? 'Fully received'
                    : 'Rcvd: ${NumberFormat('#,##0.##').format(qty)}'
                        ' / ${NumberFormat('#,##0.##').format(targetQty)}',
                style: TextStyle(
                    fontSize: 11,
                    color: progressColor,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                '${(percent * 100).toInt()}%',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: progressColor),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }
}
