// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'serial_number_field_delegate.dart';

/// Shared implementation layer for any DocType item-sheet controller that
/// carries a POS-Upload invoice serial number field.
///
/// Adopt this mixin instead of the now-deprecated [PosSerialMixin] to gain:
///
/// - Full [SerialNumberFieldDelegate] compliance (widget-ready out of the box)
/// - Live remaining qty computation that reacts to every keystroke
/// - Edit-mode double-count prevention via [savedQtyForRow]
/// - Rich dropdown row metadata via [serialDropdownItems] override
/// - Dirty-check helpers ported from [PosSerialMixin] with identical semantics
/// - A static [fmtQty] helper shared with the widget's cap badge
///
/// ## Minimal adoption
///
/// ```dart
/// class MyItemController extends GetxController
///     with SerialFieldMixin {
///
///   @override
///   List<String> get availableSerialNos => _parent.posSerials;
///
///   @override
///   double posItemQtyForSerial(String serial) =>
///       _parent.posQtyFor(serial);
///
///   @override
///   double sumQtyUsedForSerial(String serial) =>
///       _parent.items
///           .where((r) => r.serial == serial)
///           .fold(0.0, (s, r) => s + r.qty);
///
///   // Optional: supply rich row metadata for the dropdown.
///   @override
///   SerialDropdownItem? posDropdownItemFor(String serial) {
///     final item = _parent.posItemFor(serial);
///     if (item == null) return null;
///     return SerialDropdownItem(
///       serial: serial,
///       itemName: item.itemName,
///       qty: item.qty?.toDouble(),
///       remaining: liveRemaining.value,
///     );
///   }
///
///   // --- call this from validateSheet() ---
///   @override
///   void validateSheet() {
///     final typed = double.tryParse(qtyController.text) ?? 0.0;
///     computeLiveRemaining(
///       currentTypedQty: typed,
///       editingRowId: editingItemName.value,
///     );
///     // ... rest of validation ...
///   }
/// }
/// ```
///
/// ## Live remaining formula
///
/// [computeLiveRemaining] implements:
///
/// Formula:
/// ```
/// used          = sumQtyUsedForSerial(serial, excludeRowId: editingRowId)
/// liveRemaining = cap − used − currentTypedQty
/// ```
///
/// In **add mode** (`editingRowId == null`) all rows are summed (none excluded)
/// and the formula simplifies to `cap − sumAll − currentTypedQty`.
///
/// A negative result indicates over-allocation; the widget renders the badge
/// in the error colour in that case.
///
/// ## Packing Slip read-only mode
///
/// When [availableSerialNos] contains exactly one element (pre-seeded from the
/// linked DN item's `customInvoiceSerialNumber`), the dropdown effectively
/// becomes read-only.  [selectedSerial] is seeded in `initialise()` and
/// [captureSerialSnapshot] is called immediately after, so [isSerialDirty]
/// stays false unless the value is externally mutated.
///
/// ## Relationship to PosSerialMixin
///
/// [SerialFieldMixin] is the direct replacement for `PosSerialMixin`.
/// Key differences:
///
/// | Aspect                | PosSerialMixin                  | SerialFieldMixin                         |
/// |-----------------------|---------------------------------|------------------------------------------|
/// | Base-class constraint | `on ItemSheetControllerBase`    | None — any `GetxController`              |
/// | Interface             | none                            | `implements SerialNumberFieldDelegate`   |
/// | Live remaining        | exposed via `posSerialCapText`  | computed via `computeLiveRemaining()`    |
/// | Edit-mode handling    | absent                          | `savedQtyForRow` hook                    |
/// | qty source            | `posItemQty` getter             | `posItemQtyForSerial(String serial)`     |
/// | Rich dropdown rows    | absent                          | `posDropdownItemFor` hook                |
///
/// `PosSerialMixin` will be deleted in commit 7 of this series.
mixin SerialFieldMixin implements SerialNumberFieldDelegate {
  // ── SerialNumberFieldDelegate concrete fields ────────────────────────────

  @override
  final selectedSerial = RxnString();

  @override
  final liveRemaining = 0.0.obs;

  /// Incremented every time the serial dropdown items list should be
  /// re-evaluated (e.g. after a sibling row is committed or qty changes).
  /// Read by [SharedInvoiceSerialNumberField] inside its Obx to force a
  /// dropdown rebuild when the underlying data changes.
  final serialItemsStamp = 0.obs;

  void notifySerialItemsChanged() => serialItemsStamp.value++;

  /// Whether the user has overridden the Full-serial lock for this sheet session.
  ///
  /// When `true`:
  ///   - Full serials are selectable in the dropdown (widget un-disables them).
  ///   - The POS qty cap is bypassed in `effectiveMaxQty` so the user can enter
  ///     any qty (batch and rack balance caps remain enforced).
  ///
  /// Reset to `false` at every sheet open via `_seedNewItemModeFlags` /
  /// `_seedEditModeFlags` (DN) and `initForNewItem` / `_loadExistingItem` (SE).
  final allowFullSerials = false.obs;

  /// Whether [SharedInvoiceSerialNumberField] should offer the "Allow Full"
  /// override toggle when a Full serial exists.
  ///
  /// DN/SE keep the default (true). Packing Slip overrides to false: its qty
  /// cap treats 0 remaining as "uncapped", so selecting a Full serial could
  /// over-pack the DN row. Full rows stay hard-disabled there.
  bool get supportsAllowFullToggle => true;

  // ── Abstract hooks (concrete controller must provide) ────────────────────

  /// Ordered list of valid serial numbers for the dropdown.
  ///
  /// Return a single-element list for Packing Slip (pre-seeded, read-only).
  /// Return an empty list to hide the widget entirely.
  @override
  List<String> get availableSerialNos;

  /// POS Upload qty cap for [serial] at the current item idx.
  ///
  /// Concrete controller resolves `serial → idx → PosUploadItem.qty`.
  /// Return `double.infinity` for no cap; return `0` for no POS Upload loaded.
  @override
  double posItemQtyForSerial(String serial);

  /// Sum of all committed row qtys in the parent document for [serial],
  /// optionally excluding one row by its alphanumeric document name.
  ///
  /// Walk the parent document's in-memory items list synchronously —
  /// no API call.
  ///
  /// [excludeRowId] — pass the editing row's `item.name` (e.g.
  /// `"MAT-STE-2026-00123-1"`) to exclude it from the sum so that
  /// Used = sum of OTHER rows only.  Pass `null` (default) to include all rows.
  ///
  /// Default returns 0.0; override in every concrete adopter.
  double sumQtyUsedForSerial(String serial, {String? excludeRowId}) => 0.0;

  /// The already-saved qty of the row identified by [rowId].
  ///
  /// Used by [computeLiveRemaining] to undo the double-count that occurs in
  /// edit mode (the row being edited is already included in
  /// [sumQtyUsedForSerial] but we want to replace its saved qty with the
  /// live-typed qty).
  ///
  /// Return 0.0 in add mode (default) or when the row is not found.
  double savedQtyForRow(String rowId) => 0.0;

  /// Optional rich metadata for a single dropdown row.
  ///
  /// Override to supply POS Upload item name and qty cap for [serial].
  /// Return `null` to fall back to the index-badge-only rendering.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// SerialDropdownItem? posDropdownItemFor(String serial) {
  ///   final pos = _parent.posItemFor(serial);
  ///   if (pos == null) return null;
  ///   return SerialDropdownItem(
  ///     serial: serial,
  ///     itemName: pos.itemName,
  ///     qty: pos.qty?.toDouble(),
  ///     remaining: liveRemaining.value,
  ///   );
  /// }
  /// ```
  SerialDropdownItem? posDropdownItemFor(String serial) => null;

  /// Rich metadata list for the dropdown — overrides the default
  /// pass-through in [SerialNumberFieldDelegate].
  ///
  /// Calls [posDropdownItemFor] for each serial; falls back to a bare
  /// [SerialDropdownItem] (index badge only) when the hook returns null.
  /// remaining = cap − already-scanned qty, so isFull triggers correctly at 0.
  @override
  List<SerialDropdownItem> get serialDropdownItems =>
      availableSerialNos.map((s) {
        return posDropdownItemFor(s) ??
            SerialDropdownItem(
              serial: s,
              remaining: posItemQtyForSerial(s),
            );
      }).toList();

  // ── Live remaining computation ────────────────────────────────────────────

  /// Recomputes [liveRemaining] and writes the result reactively.
  ///
  /// Call this from `validateSheet()` on every text-field change:
  ///
  /// ```dart
  /// @override
  /// void validateSheet() {
  ///   computeLiveRemaining(
  ///     currentTypedQty: double.tryParse(qtyController.text) ?? 0.0,
  ///     editingRowId: editingItemName.value,  // null = add mode
  ///   );
  ///   // ...
  /// }
  /// ```
  ///
  /// Formula:
  /// ```
  /// liveRemaining = cap
  ///               − sumQtyUsedForSerial(serial)
  ///               + savedQtyForRow(editingRowId ?? '')
  ///               − currentTypedQty
  /// ```
  ///
  /// Sets [liveRemaining] to `0.0` when:
  ///   - no serial is selected
  ///   - `posItemQtyForSerial` returns 0 or infinity (badge hidden anyway)
  void computeLiveRemaining({
    required double currentTypedQty,
    String? editingRowId,
  }) {
    final serial = selectedSerial.value;
    if (serial == null || serial.isEmpty) {
      liveRemaining.value = 0.0;
      return;
    }

    final cap = posItemQtyForSerial(serial);
    if (cap <= 0 || cap == double.infinity) {
      liveRemaining.value = 0.0;
      return;
    }

    // Used = sum of all rows for this serial EXCLUDING the editing row by name.
    // In add mode (editingRowId == null) all rows are included.
    final used = sumQtyUsedForSerial(serial, excludeRowId: editingRowId);

    // Pending = cap − Used − currentTypedQty
    liveRemaining.value = cap - used - currentTypedQty;

    debugPrint(
      '[computeLiveRemaining] serial=$serial '
          'cap=$cap '
          'excludeRowId=$editingRowId '
          'used=$used '
          'currentTypedQty=$currentTypedQty '
          'pending=${liveRemaining.value}',
    );
  }

  // ── Dirty-check & validation (ported from PosSerialMixin unchanged) ───────

  /// Snapshot value captured at sheet open time for dirty detection.
  String? _snapshotSerial;

  /// Captures the current [selectedSerial] value as the baseline for
  /// [isSerialDirty].  Call this at the end of `initialise()`.
  void captureSerialSnapshot() => _snapshotSerial = selectedSerial.value;

  /// True when [selectedSerial] differs from the value at last snapshot.
  bool get isSerialDirty => selectedSerial.value != _snapshotSerial;

  /// Returns true when the serial field is satisfied.
  ///
  /// Passes automatically when [availableSerialNos] is empty (serial field
  /// not required for this DocType / POS Upload not loaded).
  bool validateSerial() {
    if (availableSerialNos.isEmpty) return true;
    return selectedSerial.value != null &&
        selectedSerial.value!.isNotEmpty;
  }

  // ── Format helper (static — shared with widget cap badge) ─────────────────

  /// Formats a qty value for display in the cap badge.
  ///
  /// - Whole numbers drop the decimal: `3.0` → `"3"`
  /// - Fractional values use 2 decimal places: `3.5` → `"3.50"`
  /// - Infinity returns `"∞"`
  /// - Negative infinity returns `"-∞"` (over-allocation edge case)
  ///
  /// Ported from `PosSerialMixin._fmtQty`; promoted to `static` so the
  /// widget's `_SerialCapBadge` can call it without a controller reference.
  static String fmtQty(double v) {
    if (v == double.infinity) return '\u221e';
    if (v == double.negativeInfinity) return '-\u221e';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }
}
