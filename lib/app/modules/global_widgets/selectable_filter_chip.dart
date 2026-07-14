import 'package:flutter/material.dart';

/// A selectable (toggle) filter chip for *in-screen* segmentation — e.g. the
/// All / Pending / Completed item filters on form Items tabs, or a single-select
/// warehouse picker.
///
/// Distinct from [FilterChipWidget], which is the read-only *applied-filter*
/// chip (maroon pill with a trailing ×) rendered in the list-header chip row.
///
/// Consolidates the private `_buildFilterChip` helpers (bare [ChoiceChip]s) in
/// Delivery Note, Packing Slip and Purchase Receipt, plus the hand-styled
/// warehouse [FilterChip]s in the Item form. Styling is delegated to the global
/// `chipTheme` so every selectable filter chip looks identical.
class SelectableFilterChip extends StatelessWidget {
  const SelectableFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
    this.dotColor,
  });

  final String label;

  /// When non-null, rendered as `label (count)`.
  final int? count;

  /// When non-null, a small leading dot in this colour — e.g. the
  /// [StatusPill] dot colour for a status facet chip. Lives inside the
  /// label (not [ChoiceChip.avatar]) so it stays visible when the
  /// selected-state checkmark is shown.
  final Color? dotColor;

  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Text(count != null ? '$label ($count)' : label);
    return ChoiceChip(
      label: dotColor == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                text,
              ],
            ),
      selected: selected,
      onSelected: onSelected,
      visualDensity: VisualDensity.compact,
    );
  }
}
