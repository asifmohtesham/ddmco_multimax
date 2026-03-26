import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';
import 'package:multimax/app/shared/item_card/doc_item_progress_bar.dart';

// ────────────────────────────────────────────────────────────────────────────
// DocItemCard
// ────────────────────────────────────────────────────────────────────────────

/// Shared stateless item-card widget for all DocType form screens.
///
/// Layout (C12):
///
///   Row 1  ─ index badge | item code + name (_HeadlineRow) | delete button
///   Row 2  ─ [Variant Of chip]          ← full card width
///   Zone 2 ─ Batch No, rack pair        ← full card width
///   [────── divider ──────]
///   Zone 3 ─ Qty                        ← full card width
///   [progress bar]                      ← full card width
///   [linear loading indicator]          ← full card width
///
/// Index badge and delete button are constrained to Row 1 only,
/// freeing the full width for all subsequent content.
///
/// [onEdit] is retained as a silent no-op for call-site compatibility (C11).
class DocItemCard extends StatelessWidget {
  final ItemCardData  data;
  final VoidCallback? onTap;

  /// Retained for call-site compatibility. Not wired to any widget (C11).
  @Deprecated('Edit is triggered via onTap (card body). This parameter is a '
      'silent no-op and will be removed in a future cleanup commit.')
  final VoidCallback? onEdit;

  final VoidCallback? onDelete;

  /// When true a slim LinearProgressIndicator fades in at the card bottom.
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

    final bool hasVariant     = data.variantOf != null && data.variantOf!.isNotEmpty;
    final bool hasOperational =
        (data.batchNo != null && data.batchNo!.isNotEmpty) ||
        (data.rack    != null && data.rack!.isNotEmpty);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: data.isHighlighted
            ? cs.tertiaryContainer.withValues(alpha: 0.35)
            : cs.surface,
        boxShadow: [
          BoxShadow(
            color:       cs.shadow.withValues(alpha: .06),
            spreadRadius: 1,
            blurRadius:   3,
            offset:       const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Card body ──────────────────────────────────────────────────
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Row 1: headline + index badge + delete ────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (data.index != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                              '${data.index! + 1}',
                              style: TextStyle(
                                color:      cs.onPrimaryContainer,
                                fontSize:   9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: _HeadlineRow(
                          itemCode: data.itemCode,
                          itemName: data.itemName,
                        ),
                      ),
                      if (data.isEditable && onDelete != null) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width:  36,
                          height: 36,
                          child: IconButton(
                            padding:   EdgeInsets.zero,
                            icon:      Icon(Icons.delete_outline,
                                color: cs.error, size: 20),
                            tooltip:   'Remove item',
                            onPressed: onDelete,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // ── Row 2: Variant Of chip (full width) ──────────────
                  if (hasVariant) ...[
                    const SizedBox(height: 6),
                    _VariantOfRow(variantOf: data.variantOf!),
                  ],

                  // ── Zone 2: Operational (full width) ─────────────────
                  _OperationalZone(
                    batchNo:        data.batchNo,
                    rack:           data.rack,
                    toRack:         data.toRack,
                    warehouse:      data.warehouse,
                    toWarehouse:    data.toWarehouse,
                    warehouseLabel: data.warehouseLabel ?? 'Warehouse',
                  ),

                  // ── Zone 2 → Zone 3 divider ───────────────────────
                  if (hasOperational)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        height:    1,
                        thickness: 0.6,
                        color:     cs.outlineVariant,
                      ),
                    ),

                  // ── Zone 3: Financial (full width) ─────────────────
                  _FinancialZone(
                    qty:      data.qty,
                    uom:      data.uom,
                    qtyLabel: data.qtyLabel ?? 'Qty',
                  ),

                  // ── Progress bar (full width) ─────────────────────
                  if (data.targetQty != null && data.targetQty! > 0)
                    DocItemProgressBar(
                      qty:       data.qty,
                      targetQty: data.targetQty!,
                      uom:       data.uom,
                    ),
                ],
              ),
            ),
          ),

          // ── Loading indicator — full-width linear bar ──────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isLoadingEdit
                ? LinearProgressIndicator(
                    key:             const ValueKey('loading'),
                    minHeight:       2,
                    backgroundColor: cs.primaryContainer,
                    valueColor:      AlwaysStoppedAnimation<Color>(cs.primary),
                  )
                : const SizedBox.shrink(key: ValueKey('idle')),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _HeadlineRow  (split from _IdentityZone — C12)
// ────────────────────────────────────────────────────────────────────────────

/// Item code + name headline only.
/// Sits inside the constrained Row 1 alongside the index badge and
/// delete button. Variant Of has been extracted to [_VariantOfRow].
class _HeadlineRow extends StatelessWidget {
  final String  itemCode;
  final String? itemName;

  const _HeadlineRow({
    required this.itemCode,
    this.itemName,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
            text: itemCode,
            style: TextStyle(
              fontWeight:   FontWeight.bold,
              fontSize:     14,
              fontFamily:   'ShureTechMono',
              fontFeatures: const [FontFeature.slashedZero()],
              color:        cs.onSurface,
            ),
          ),
          if (itemName != null && itemName!.isNotEmpty)
            TextSpan(
              text: ': $itemName',
              style: TextStyle(
                fontWeight:   FontWeight.bold,
                fontSize:     14,
                fontFamily:   'ShureTechMono',
                color:        cs.onSurface,
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _VariantOfRow  (split from _IdentityZone — C12)
// ────────────────────────────────────────────────────────────────────────────

/// Variant Of chip rendered at full card width below Row 1.
/// Only built when variantOf is non-null and non-empty.
class _VariantOfRow extends StatelessWidget {
  final String variantOf;

  const _VariantOfRow({required this.variantOf});

  @override
  Widget build(BuildContext context) {
    return DocItemMetaChip(
      icon:  Icons.account_tree_outlined,
      label: 'Variant Of: $variantOf',
      role:  MetaChipRole.variantOf,
      size:  MetaChipSize.standard,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _OperationalZone
// ────────────────────────────────────────────────────────────────────────────

/// Zone 2: Batch No (full-width), rack _ArrowPairRow, warehouse _ArrowPairRow.
/// Returns [SizedBox.shrink] when no operational field is set.
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
    final bool hasBatch      = batchNo   != null && batchNo!.isNotEmpty;
    final bool hasSourceRack = rack      != null && rack!.isNotEmpty;
    final bool hasWarehouse  = warehouse != null && warehouse!.isNotEmpty;

    if (!hasBatch && !hasSourceRack && !hasWarehouse) {
      return const SizedBox.shrink();
    }

    final List<Widget> rows = [];

    if (hasBatch) {
      rows.add(_LabelValueCell(
        icon:  Icons.label_outline,
        label: 'Batch No',
        value: batchNo!,
        role:  MetaChipRole.batch,
      ));
    }

    if (hasSourceRack) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
      rows.add(_ArrowPairRow(
        source: _LabelValueCell(
          icon:  Icons.shelves,
          label: 'Source Rack',
          value: rack!,
          role:  MetaChipRole.rack,
        ),
        target: (toRack != null && toRack!.isNotEmpty)
            ? _LabelValueCell(
                icon:  Icons.shelves,
                label: 'Target Rack',
                value: toRack!,
                role:  MetaChipRole.toRack,
              )
            : null,
      ));
    }

    if (hasWarehouse) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
      rows.add(_ArrowPairRow(
        source: _LabelValueCell(
          icon:  Icons.store_outlined,
          label: warehouseLabel,
          value: warehouse!,
          role:  MetaChipRole.warehouse,
        ),
        target: (toWarehouse != null && toWarehouse!.isNotEmpty)
            ? _LabelValueCell(
                icon:  Icons.store_outlined,
                label: 'Target Warehouse',
                value: toWarehouse!,
                role:  MetaChipRole.toWarehouse,
              )
            : null,
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _FinancialZone
// ────────────────────────────────────────────────────────────────────────────

/// Zone 3: Qty only — single [_LabelValueCell] at natural width.
class _FinancialZone extends StatelessWidget {
  final double  qty;
  final String? uom;
  final String  qtyLabel;

  static final _fmt = NumberFormat('#,##0.##');

  const _FinancialZone({
    required this.qty,
    this.uom,
    required this.qtyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final String qtyValue =
        '${_fmt.format(qty)}${uom != null ? '  $uom' : ''}';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _LabelValueCell(
        icon:  Icons.numbers,
        label: qtyLabel,
        value: qtyValue,
        role:  MetaChipRole.qty,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// MetaChipSize
// ────────────────────────────────────────────────────────────────────────────

enum MetaChipSize { standard, compact }

// ────────────────────────────────────────────────────────────────────────────
// MetaChipRole
// ────────────────────────────────────────────────────────────────────────────

enum MetaChipRole {
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

// ────────────────────────────────────────────────────────────────────────────
// DocItemMetaChip
// ────────────────────────────────────────────────────────────────────────────

/// Compact icon + label chip used across all zones.
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
        color:        col.bg,
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: col.border, width: 0.5),
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

// ────────────────────────────────────────────────────────────────────────────
// _LabelValueCell
// ────────────────────────────────────────────────────────────────────────────

/// A labelled-value cell: muted label on top, prominent value below.
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
    final col = DocItemMetaChip._colours(role, cs);

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
                  fontSize:      10,
                  color:         cs.onSurfaceVariant,
                  fontFamily:    'ShureTechMono',
                  fontFeatures:  const [FontFeature.slashedZero()],
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
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

// ────────────────────────────────────────────────────────────────────────────
// _ArrowPairRow
// ────────────────────────────────────────────────────────────────────────────

/// Guaranteed single-line source → target row.
/// Both cells are Expanded so long values share width equally.
/// When target is null, source occupies full width with no arrow.
class _ArrowPairRow extends StatelessWidget {
  final Widget  source;
  final Widget? target;

  const _ArrowPairRow({
    required this.source,
    this.target,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: source),
        if (target != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward_rounded,
              size:  14,
              color: cs.outline,
            ),
          ),
          Expanded(child: target!),
        ],
      ],
    );
  }
}

/// Internal colour bundle.
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
