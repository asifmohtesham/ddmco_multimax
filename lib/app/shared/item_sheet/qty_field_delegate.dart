// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'qty_cap_delegate.dart';

/// Reactive qty-field state contract.
///
/// Any controller that wants to host [SharedQtyField] must satisfy this
/// interface.  The contract is intentionally narrower than
/// [ItemSheetControllerBase] so that future DocType controllers do not
/// need to inherit the full item-sheet base class just to reuse the qty
/// widget.
///
/// ## Why a separate interface?
///
/// Before this refactor, qty state lived directly on
/// [ItemSheetControllerBase] with no extraction.  This meant:
///
/// - Any DocType whose controller did not extend the base class could not
///   use the widget.
/// - Tests were forced to instantiate a full [GetxController] subclass.
/// - Future extensions (e.g. a lightweight standalone qty field) would
///   carry unnecessary coupling.
///
/// This interface extracts only the members [SharedQtyField] actually
/// reads, so both the existing base class (via `implements`) and any
/// future lightweight controller can satisfy it with zero extra cost.
///
/// ## Relationship to [QtyCapDelegate]
///
/// [QtyFieldDelegate] extends [QtyCapDelegate], which declares
/// [qtyInfoText] and [qtyInfoTooltip].  This means [SharedQtyField] can
/// pass `this` directly to [QtyCapBadge] without a cast:
///
/// ```dart
/// QtyCapBadge(controller: c)  // c: QtyFieldDelegate — no cast needed
/// ```
///
/// ## Reactive fields
///
/// All state fields are `Rx*` so that `Obx` widgets inside
/// [SharedQtyField] rebuild correctly when the controller mutates them.
///
/// ## isQtyValid — DEDICATED sub-field
///
/// [isQtyValid] is a **dedicated** [RxBool] field, *not* an alias of
/// `isSheetValid`.  This mirrors [BatchNoFieldDelegate.isBatchValid] and
/// [RackFieldDelegate.isRackValid], which are also dedicated sub-fields
/// on their respective interfaces.
///
/// The sheet-level save gate should compose individual sub-validations:
///
/// ```dart
/// isSheetValid.value =
///     isQtyValid.value && isBatchValid.value && isRackValid.value;
/// ```
///
/// ## Error semantics — ENFORCED CONTRACT
///
/// [qtyError] is **[RxString]** (non-nullable).  An **empty string (`''`)
/// means no error is present**.  Callers MUST check
/// `qtyError.value.isNotEmpty` — never `!= null`.
///
/// Rationale:
///   • [ItemSheetControllerBase] declares `qtyError = RxString('')`.
///   • All DocType controllers write `qtyError.value = ''` on success
///     and a non-empty string on failure — no nullable assignment anywhere.
///   • [SharedQtyField] checks `c.qtyError.value.isNotEmpty` in both
///     view-only and edit-mode paths — no null checks in the widget layer.
///
/// This is the **sealed contract**: implementors of this interface MUST
/// declare [qtyError] as [RxString] and MUST use `''` to signal the
/// no-error state.  Using [RxnString] or assigning `null` is a contract
/// violation and will cause a runtime type error when the widget calls
/// `.isNotEmpty` on the value.
///
/// ## validateSheet semantics
///
/// [validateSheet] is called by [SharedQtyField]'s `onChanged` callback
/// on every keystroke and on field blur.  Implementing controllers must
/// write both [isQtyValid] and [qtyError] inside this method:
///
/// ```dart
/// @override
/// void validateSheet() {
///   final qty = double.tryParse(qtyController.text);
///   if (qty == null || qty <= 0) {
///     isQtyValid.value = false;
///     qtyError.value   = qty == null ? '' : 'Enter a quantity greater than 0';
///   } else {
///     isQtyValid.value = true;
///     qtyError.value   = '';
///   }
///   isSheetValid.value = isQtyValid.value && isBatchValid.value;
/// }
/// ```
///
/// Lightweight controllers that do not gate a Save button may provide an
/// empty-body implementation.
///
/// ## Lightweight-controller example
///
/// ```dart
/// class LightweightQtyController extends GetxController
///     implements QtyFieldDelegate {
///   @override final isQtyValid     = false.obs;
///   @override final qtyError       = RxString('');
///   @override final qtyController  = TextEditingController();
///   @override final qtyInfoTooltip = RxnString(null);
///
///   @override String? get qtyInfoText => null; // no cap badge
///
///   @override void validateSheet() {
///     final qty = double.tryParse(qtyController.text);
///     isQtyValid.value = qty != null && qty > 0;
///     qtyError.value   = isQtyValid.value ? '' : 'Required';
///   }
///
///   @override
///   void onClose() {
///     qtyController.dispose();
///     super.onClose();
///   }
/// }
///
/// // No ± stepper rendered (c does not implement QtyPlusMinusDelegate):
/// SharedQtyField(c: lightweightController, accentColor: Colors.teal)
/// ```
///
/// To add ± stepper support, upgrade to [QtyFieldWithPlusMinusDelegate]
/// — this adds [isQtyReadOnly], [effectiveMaxQty], and [adjustQty].
///
/// ## Changelog
///
/// Commit 2 of 7 — Add QtyFieldDelegate:
///   • New file.  Mirrors [BatchNoFieldDelegate] in structure, Dartdoc
///     conventions, error-semantics contract, and changelog format.
///   • Extends [QtyCapDelegate] (Commit 1) so [SharedQtyField] can pass
///     `c` directly to [QtyCapBadge] without a cast.
///   • No existing files modified.  No call sites changed.
abstract interface class QtyFieldDelegate implements QtyCapDelegate {
  // ── Reactive sub-field validity ───────────────────────────────────

  /// Whether the qty field currently holds a valid, in-bounds value.
  ///
  /// This is a **dedicated** [RxBool] — not an alias of `isSheetValid`.
  /// The sheet save gate MUST compose individual sub-validations:
  ///
  /// ```dart
  /// isSheetValid.value =
  ///     isQtyValid.value && isBatchValid.value && isRackValid.value;
  /// ```
  ///
  /// Mirrors [BatchNoFieldDelegate.isBatchValid] and
  /// [RackFieldDelegate.isRackValid].
  RxBool get isQtyValid;

  /// Inline error text displayed beneath the qty [TextFormField].
  ///
  /// `''` → no error (field renders normally).\
  /// Non-empty → displayed as `errorText` on the [InputDecoration].
  ///
  /// **Sealed contract — never null.** See class-level doc for the full
  /// rationale.  Mirrors [RackFieldDelegate.rackError] and
  /// [BatchNoFieldDelegate.batchError].
  RxString get qtyError;

  // ── QtyCapDelegate (re-declared for documentation clarity) ────────
  //
  // The two members below are inherited from [QtyCapDelegate].  They are
  // listed here only as Dartdoc anchors so that IDEs surfacing this
  // interface show the full member set.  Implementors do NOT need to
  // declare them a second time.
  //
  //   String?   get qtyInfoText;
  //       Label text rendered on the [QtyCapBadge] chip
  //       (e.g. 'Max: 12').  `null` → chip is not rendered.
  //
  //   RxnString get qtyInfoTooltip;
  //       Breakdown content shown when the chip is tapped
  //       (e.g. 'Batch: 10  ·  Rack: 2').  `null` → chip is not tappable.

  // ── Text controller ───────────────────────────────────────────────

  /// Backing [TextEditingController] for the qty [TextFormField].
  ///
  /// Lifecycle (creation and disposal) is the responsibility of the
  /// implementing controller, not [SharedQtyField].
  TextEditingController get qtyController;

  // ── Actions ───────────────────────────────────────────────────────

  /// Recomputes sheet-level validity after any qty change.
  ///
  /// Called by [SharedQtyField] on every `onChanged` keystroke and on
  /// field blur.  Implementing controllers MUST write both [isQtyValid]
  /// and [qtyError] inside this method.
  ///
  /// Lightweight controllers that do not gate a Save button may provide
  /// an empty-body implementation:
  /// ```dart
  /// @override void validateSheet() {}
  /// ```
  ///
  /// Mirrors [BatchNoFieldDelegate.validateSheet].
  void validateSheet();
}
