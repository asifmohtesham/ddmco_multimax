import 'package:flutter/material.dart';

// ────────────────────────────────────────────────────────────────────────────
// DocTypePickerColumn
// ────────────────────────────────────────────────────────────────────────────

/// Defines a single column displayed in the [DocTypePickerBottomSheet] row.
///
/// Columns are rendered side-by-side on wide screens (tablet / landscape)
/// and stacked as metadata cards on narrow phone-width screens.
///
/// Only columns with [visibleOnMobile] set to `true` are shown in the
/// stacked mobile layout. At least one column should be [isPrimary] and
/// one [isSecondary] so the compact mobile tile renders correctly.
class DocTypePickerColumn {
  /// Frappe/ERPNext fieldname returned by the API, e.g. `'item_code'`.
  final String fieldname;

  /// Human-readable header label shown above the column on wide layouts.
  final String label;

  /// Relative width weight used with [Flexible] / [Expanded].
  /// Defaults to `1`. A column with `flex: 2` is twice as wide as `flex: 1`.
  final int flex;

  /// Minimum pixel width before the column is hidden on wide layouts.
  /// Null means no minimum constraint.
  final double? minWidth;

  /// Marks this column as the primary identifier of the record.
  /// Rendered bold and dominant in both wide and mobile layouts.
  /// Only one column per config should be primary.
  final bool isPrimary;

  /// Marks this column as the secondary descriptor (e.g. item name).
  /// Rendered muted below the primary value in the mobile stacked layout.
  /// Only one column per config should be secondary.
  final bool isSecondary;

  /// Whether this column is included in the compact mobile stacked tile.
  /// Defaults to `true`. Set to `false` for supplementary columns that
  /// are only meaningful on wider screens (e.g. stock_uom).
  final bool visibleOnMobile;

  /// Optional text alignment for this column on wide layouts.
  /// Defaults to [TextAlign.start].
  final TextAlign align;

  /// Optional custom value formatter. When provided, the return value of
  /// this function is rendered instead of `row[fieldname].toString()`.
  ///
  /// Use this for unit suffixes, date formatting, or conditional display.
  ///
  /// Example:
  /// ```dart
  /// valueBuilder: (row) => '${row['qty']} ${row['uom']}',
  /// ```
  final String Function(Map<String, dynamic> row)? valueBuilder;

  const DocTypePickerColumn({
    required this.fieldname,
    required this.label,
    this.flex = 1,
    this.minWidth,
    this.isPrimary = false,
    this.isSecondary = false,
    this.visibleOnMobile = true,
    this.align = TextAlign.start,
    this.valueBuilder,
  });

  /// Returns the display value for [row], using [valueBuilder] if set,
  /// or falling back to `row[fieldname]?.toString() ?? ''`.
  String resolve(Map<String, dynamic> row) {
    if (valueBuilder != null) return valueBuilder!(row);
    final v = row[fieldname];
    if (v == null) return '';
    return v.toString();
  }
}
