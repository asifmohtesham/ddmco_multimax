// ignore_for_file: lines_longer_than_80_chars

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
/// ```
/// liveRemaining = cap
///               − sumQtyUsedForSerial(serial)   // all committed rows
///               + savedQtyForRow(editingRowId)   // undo double-count in edit mode
///               − currentTypedQty               // react to every keystroke
/// ```
///
/// In **add mode** (`editingRowId == null`) `savedQtyForRow` returns 0.0 and
/// the formula simplifies to `cap − committed − currentTypedQty`.
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
///
/// `PosSerialMixin` will be deleted in commit 7 of this series.
mixin SerialFieldMixin implements SerialNumberFieldDelegate {
  // ── SerialNumberFieldDelegate concrete fields ────────────────────────────

  @override
  final selectedSerial = RxnString();

  @override
  final liveRemaining = 0.0.obs;

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

  /// Sum of all committed row qtys in the parent document for [serial].
  ///
  /// Walk the parent document's in-memory items list synchronously —
  /// no API call.  Include the row currently being edited (its saved qty
  /// will be subtracted by [computeLiveRemaining] via [savedQtyForRow]).
  ///
  /// Default returns 0.0; override in every concrete adopter.
  double sumQtyUsedForSerial(String serial) => 0.0;

  /// The already-saved qty of the row identified by [rowId].
  ///
  /// Used by [computeLiveRemaining] to undo the double-count that occurs in
  /// edit mode (the row being edited is already included in
  /// [sumQtyUsedForSerial] but we want to replace its saved qty with the
  /// live-typed qty).
  ///
  /// Return 0.0 in add mode (default) or when the row is not found.
  double savedQtyForRow(String rowId) => 0.0;

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

    final committed = sumQtyUsedForSerial(serial);
    final savedOfCurrentRow =
        editingRowId != null ? savedQtyForRow(editingRowId) : 0.0;

    liveRemaining.value =
        cap - committed + savedOfCurrentRow - currentTypedQty;
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
