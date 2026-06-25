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
  });

  final String label;

  /// When non-null, rendered as `label (count)`.
  final int? count;

  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(count != null ? '$label ($count)' : label),
      selected: selected,
      onSelected: onSelected,
      visualDensity: VisualDensity.compact,
    );
  }
}
