// ignore_for_file: lines_longer_than_80_chars

import 'package:get/get.dart';

/// Narrow stepper contract for the qty field ± buttons.
///
/// A controller that implements [QtyFieldDelegate] alone provides a plain
/// text-only qty field with no stepper.  Upgrading to
/// [QtyFieldWithPlusMinusDelegate] (which combines this interface with
/// [QtyFieldDelegate]) enables the ± buttons and blur-clamping.
///
/// ## Read-only guard
///
/// [isQtyReadOnly] should be backed by a dedicated [RxBool] field in the
/// controller — *not* a raw `.obs` literal in the getter. A getter literal
/// allocates a new [Rx] object on every rebuild, breaking Obx subscriptions.
///
/// The canonical implementation wires the field to `docstatus` via an
/// `ever()` worker in `onInit`:
///
/// ```dart
/// // In ItemSheetControllerBase.onInit
/// ever(docStatus, (_) => _isQtyReadOnly.value = docStatus.value == 1);
/// ```
///
/// ## Max-qty ceiling
///
/// [effectiveMaxQty] is the single resolved ceiling used by both the ±
/// buttons (via [adjustQty]) and the blur-clamp in [SharedQtyField].
/// Return [double.infinity] to disable the ceiling for uncapped DocTypes.
///
/// | DocType        | Formula                                              |
/// |----------------|------------------------------------------------------|
/// | Stock Entry    | `min(batchBalance.value, rackBalance.value)`         |
/// | Delivery Note  | `min(batchBalance.value, rackBalance.value, liveRemaining.value)` |
/// | Purchase Rcpt  | `maxQty` (PO ordered qty)                            |
/// | MR / Job Card  | `double.infinity` (base default — no override needed)|
///
/// ## adjustQty contract
///
/// Implementors MUST:
/// 1. Read the current value from [QtyFieldDelegate.qtyController].
/// 2. Compute `next = (current + delta).clamp(0.0, effectiveMaxQty)`.
/// 3. Format and write back to [QtyFieldDelegate.qtyController].
/// 4. Call [QtyFieldDelegate.validateSheet] to refresh the save gate.
///
/// [delta] is always +1 or -1 from [SharedQtyField]'s buttons, but the
/// interface does not restrict it — callers may pass larger steps if
/// required by a future DocType.
abstract interface class QtyPlusMinusDelegate {
  // ── Reactive guard ───────────────────────────────────────────────

  /// Whether the qty field and ± buttons are read-only.
  ///
  /// `true` when the DocType row has `docstatus == 1` (submitted) or when
  /// a DocType-specific prerequisite is unmet.
  ///
  /// Backed by a named `RxBool` field in the implementing controller;
  /// never a getter literal (`RxBool get isQtyReadOnly => false.obs;`
  /// is WRONG — creates a new Rx on every access).
  ///
  /// Mirrors [BatchNoFieldDelegate.isBatchReadOnly].
  RxBool get isQtyReadOnly;

  // ── Max-qty ceiling ──────────────────────────────────────────────

  /// The effective qty ceiling enforced by [adjustQty] and the blur-clamp
  /// in [SharedQtyField].
  ///
  /// Derived from DocType-specific business rules.  Return
  /// [double.infinity] to disable the ceiling (open-ended qty entry).
  ///
  /// This is a synchronous getter — implementations read from reactive
  /// fields (`batchBalance.value`, `rackBalance.value`, etc.) but the
  /// return type is a plain [double] because [SharedQtyField] reads it
  /// inside an [Obx] that already rebuilds on those upstream Rx changes.
  double get effectiveMaxQty;

  // ── Actions ───────────────────────────────────────────────────────

  /// Increment or decrement the qty field by [delta].
  ///
  /// [delta] is `+1` (increment) or `-1` (decrement) from [SharedQtyField].
  ///
  /// Implementing controllers MUST clamp the result to
  /// `[0.0, effectiveMaxQty]` and call [QtyFieldDelegate.validateSheet]
  /// before returning.
  void adjustQty(int delta);
}
