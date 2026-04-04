// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Reactive batch-field state contract.
///
/// Any controller that wants to host [SharedBatchField] must satisfy this
/// interface.  The contract is intentionally narrower than
/// [ItemSheetControllerBase] so that future DocType controllers do not
/// need to inherit the full item-sheet base class just to reuse the batch
/// widget.
///
/// ## Why a separate interface?
///
/// Before the [BatchNoFieldWithBrowseDelegate] refactor, [SharedBatchField]
/// held a hard dependency on [ItemSheetControllerBase].  This meant:
///
/// - Any DocType whose controller did not extend the base class could not
///   use the widget.
/// - Tests were forced to instantiate a full [GetxController] subclass.
/// - Future extensions (e.g. a lightweight batch-only widget) would carry
///   unnecessary coupling.
///
/// This interface extracts only the members [SharedBatchField] actually
/// reads, so both the existing base class (via `implements`) and any
/// future lightweight controller can satisfy it with zero extra cost.
///
/// ## Reactive fields
///
/// All state fields are `Rx*` so that `Obx` widgets inside
/// [SharedBatchField] rebuild correctly when the controller mutates them.
///
/// ## Error semantics — ENFORCED CONTRACT
///
/// [batchError] is **[RxString]** (non-nullable).  An **empty string (`''`)
/// means no error is present**.  Callers MUST check
/// `batchError.value.isNotEmpty` — never `!= null`.
///
/// Rationale:
///   • [ItemSheetControllerBase] declares `batchError = RxString('')`.
///   • All DocType controllers write `batchError.value = ''` on success
///     and a non-empty string on failure — no nullable assignment anywhere.
///   • [SharedBatchField] checks `c.batchError.value.isNotEmpty` in both
///     _SimpleField and _EditModeField — no null checks in the widget layer.
///
/// This is the **sealed contract**: implementors of this interface MUST
/// declare `batchError` as [RxString] and MUST use `''` to signal the
/// no-error state.  Using [RxnString] or assigning `null` is a contract
/// violation and will cause a runtime type error when the widget calls
/// `.isNotEmpty` on the value.
///
/// ## batchInfoTooltip semantics
///
/// [batchInfoTooltip] is [RxnString] where **`null` means no tooltip**
/// should be rendered.  The widget checks `batchInfoTooltip.value != null`
/// before building the tooltip widget.
///
/// ## validateSheet semantics
///
/// [validateSheet] is called by [ValidatedBatchField]'s `onChanged`
/// callback each time the batch text field changes.  Its role is to
/// recompute the sheet-level save gate ([isSheetValid]) after each
/// keystroke.  Lightweight controllers that do not gate a Save button can
/// provide an empty-body implementation.
///
/// ## Constructor type (BatchNoFieldWithBrowseDelegate)
///
/// [SharedBatchField.c] is typed against [BatchNoFieldWithBrowseDelegate]
/// (a super-interface of this class that adds the batch browser contract).
/// Any future lightweight DocType controller that implements
/// [BatchNoFieldDelegate] directly can drive [SharedBatchField] in
/// non-picker mode (i.e. without passing [onPickerTap]):
///
/// ```dart
/// class LightweightBatchController extends GetxController
///     implements BatchNoFieldDelegate {
///   @override final isBatchValid      = false.obs;
///   @override final isValidatingBatch = false.obs;
///   @override final isBatchReadOnly   = false.obs;
///   @override final batchError        = RxString('');
///   @override final batchInfoTooltip  = RxnString(null);
///   @override final batchController   = TextEditingController();
///
///   @override double batchBalanceFor(String batchNo) => _balance;
///   @override void   resetBatch()                    { /* ... */ }
///   @override void   validateSheet()                 { /* no save gate */ }
///   @override Future<void> validateBatch(String batchNo) async { /* ... */ }
/// }
///
/// // No picker button rendered (c does not implement BatchNoBrowseDelegate):
/// SharedBatchField(c: lightweightController, accentColor: Colors.teal, ...)
/// ```
///
/// To add Browse Batches support, upgrade to [BatchNoFieldWithBrowseDelegate]
/// — this adds [canBrowseBatches], [browseBatches], and [handleBatchPicked].
///
/// ## Changelog
///
/// Commit 1 of 7 — Extract BatchNoFieldDelegate:
///   • New file.  Mirrors RackFieldDelegate in structure and Dartdoc conventions.
///   • No existing files modified.  No call sites changed.
///
/// fix(batch-delegate) — add validateSheet:
///   • [ValidatedBatchField] passes `c.validateSheet` as its `onChanged`
///     callback (shared_batch_field.dart line 311).  Sheet-level save-gate
///     recomputation after a keystroke is a field-state concern, so it
///     belongs on this interface rather than [BatchNoBrowseDelegate].
///   • [ItemSheetControllerBase] already declares `validateSheet` as
///     abstract — no changes to the base class or any concrete controller.
abstract interface class BatchNoFieldDelegate {
  // ── Reactive state ──────────────────────────────────────────────

  /// Whether the current batch value has been confirmed valid by the server.
  RxBool get isBatchValid;

  /// Whether a batch validation round-trip is currently in flight.
  RxBool get isValidatingBatch;

  /// Whether the batch field is locked to read-only mode.
  ///
  /// When `true`, the field renders as [_SimpleField] regardless of the
  /// [editMode] flag passed to [SharedBatchField].  Typical scenarios:
  /// - The item is serial-numbered (batch entry is not applicable).
  /// - The DocType has been submitted and fields are frozen.
  RxBool get isBatchReadOnly;

  /// Validation error text for the batch field.
  ///
  /// **Empty string (`''`) means no error.** Check `batchError.value.isNotEmpty`.
  /// Never null.  Declaring this as [RxnString] or assigning `null` is a
  /// contract violation — see class-level doc for the full rationale.
  RxString get batchError;

  /// Tooltip text shown in the batch field suffix
  /// (e.g. `'Available: 24 units'`).
  /// `null` means no tooltip should be rendered.
  RxnString get batchInfoTooltip;

  // ── Text controller ────────────────────────────────────────────

  /// Text controller backing the batch number input field.
  /// Lifecycle (create / dispose) is owned by the implementing controller.
  TextEditingController get batchController;

  // ── Balance ──────────────────────────────────────────────────

  /// Returns the available balance qty for the given [batchNo].
  ///
  /// Abstracting the lookup here means:
  /// - Controllers that pre-load a map return `batchBalanceMap[batchNo] ?? 0.0`.
  /// - Controllers that maintain a live [RxDouble] balance return
  ///   `batchBalance.value`.
  /// - The [SharedBatchField] widget reads balance via a single call
  ///   regardless of which strategy the controller uses.
  double batchBalanceFor(String batchNo);

  // ── Actions ────────────────────────────────────────────────

  /// Clears the batch text field, resets all batch validity state, and zeros
  /// the batch balance.  Called when the user taps the clear / edit button.
  void resetBatch();

  /// Recomputes the sheet-level save gate after a batch field change.
  ///
  /// Called by [ValidatedBatchField]'s `onChanged` callback on every
  /// keystroke.  Implementations write [isSheetValid] (or equivalent)
  /// based on the current state of all form fields.
  ///
  /// Lightweight controllers that do not need a save gate may provide an
  /// empty-body implementation:
  /// ```dart
  /// @override void validateSheet() {}
  /// ```
  void validateSheet();

  /// Validates [batchNo] against the server (Batch-Wise Balance History) and
  /// populates [isBatchValid], [batchError], and the balance accordingly.
  ///
  /// Implementations must:
  /// 1. Set [isValidatingBatch] = true at the start.
  /// 2. Set [isValidatingBatch] = false in a `finally` block.
  /// 3. Set [batchError] = '' on success, a non-empty string on failure.
  /// 4. Set [isBatchValid] = true only on success.
  Future<void> validateBatch(String batchNo);
}
