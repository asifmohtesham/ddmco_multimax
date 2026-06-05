import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/batch_no_field_with_browse_delegate.dart';

/// A conditional "Browse Batches" text button rendered **below** the batch
/// input field.
///
/// Visible only when:
/// - [showBrowseBatches] is `true` (opt-in per call site)
/// - the batch is not yet validated ([isValid] == false)
/// - the field is not read-only ([isReadOnly] == false)
/// - no validation is currently in flight ([isValidating] == false)
///
/// Tapping opens [showBatchPickerSheet] and, on selection, writes the chosen
/// batch number into [batchController] then calls [onBatchSelected] so the
/// caller can trigger validation.
///
/// ## Controller decoupling
///
/// This widget does **not** accept an [ItemSheetControllerBase] or any other
/// full controller.  All reactive reads are passed as plain values; the
/// caller (e.g. [SharedBatchField]) wraps this in an `Obx` and passes
/// current `.value` snapshots.
///
/// ## Usage
///
/// ```dart
/// Obx(() => BrowseBatchButton(
///   showBrowseBatches: w.showBrowseBatches,
///   isValid:           c.isBatchValid.value,
///   isReadOnly:        w.readOnly || c.isBatchReadOnly.value,
///   isValidating:      c.isValidatingBatch.value,
///   itemCode:          c.itemCode.value,
///   warehouse:         w.browseWarehouse ?? c.resolvedWarehouse,
///   accentColor:       w.accentColor,
///   batchController:   c.batchController,
///   onBatchSelected:   c.validateBatch,
/// ))
/// ```
class BrowseBatchButton extends StatelessWidget {
  /// When `false` the widget renders [SizedBox.shrink] immediately, with
  /// no reactive subscriptions.  Defaults to `false` at call sites.
  final bool showBrowseBatches;

  /// Current validation state of the batch field.
  final bool isValid;

  /// Whether the batch field is read-only (field-level or DocType-level).
  final bool isReadOnly;

  /// Whether a validation round-trip is currently in flight.
  final bool isValidating;

  /// ERPNext Item Code — passed to [showBatchPickerSheet].
  final String itemCode;

  /// Warehouse filter — passed to [showBatchPickerSheet].  May be null
  /// when no warehouse constraint is needed.
  final String? warehouse;

  /// Accent colour for the button icon and label.
  final Color accentColor;

  /// The [TextEditingController] written when a batch is selected from the
  /// picker sheet.
  final TextEditingController batchController;

  /// Called with the selected batch number after [batchController] is
  /// updated.  The caller drives the validation round-trip.
  final Future<void> Function(String) onBatchSelected;

  const BrowseBatchButton({
    super.key,
    required this.showBrowseBatches,
    required this.isValid,
    required this.isReadOnly,
    required this.isValidating,
    required this.itemCode,
    required this.accentColor,
    required this.batchController,
    required this.onBatchSelected,
    this.warehouse,
  });

  @override
  Widget build(BuildContext context) {
    if (!showBrowseBatches) return const SizedBox.shrink();
    if (isValid || isReadOnly || isValidating) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () async {
          final selected = await showBatchPickerSheet(
            context,
            itemCode:    itemCode,
            warehouse:   warehouse,
            accentColor: accentColor,
          );
          if (selected != null && selected.isNotEmpty) {
            batchController.text = selected;
            await onBatchSelected(selected);
          }
        },
        icon: Icon(Icons.shelves, size: 16, color: accentColor),
        label: Text(
          'Browse Batches',
          style: TextStyle(
            color:      accentColor,
            fontSize:   12,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          padding:       const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize:   Size.zero,
        ),
      ),
    );
  }
}
