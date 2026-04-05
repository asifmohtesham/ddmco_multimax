// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'qty_cap_delegate.dart';

/// Narrow reactive-state contract for the qty text field.
///
/// [SharedQtyField] depends solely on this interface. Any controller
/// — whether or not it extends [ItemSheetControllerBase] — can host a
/// qty field by implementing these members.
///
/// ## Relationship to [QtyCapDelegate]
///
/// [QtyFieldDelegate] declares both [qtyInfoText] and [qtyInfoTooltip],
/// so it is a structural subtype of [QtyCapDelegate]. [SharedQtyField]
/// can pass `this` directly to [QtyCapBadge] without a cast.
///
/// ## Error-feedback contract
///
/// [qtyError] mirrors the `rackError` / `batchError` convention on the
/// sibling delegates: an empty string means "no error"; a non-empty string
/// is rendered as inline error text beneath the qty field. Each concrete
/// [validateSheet] implementation is responsible for writing
/// `qtyError.value` alongside `isQtyValid.value`.
abstract interface class QtyFieldDelegate implements QtyCapDelegate {
  // ── Reactive sub-field validity ───────────────────────────────────

  /// Whether the qty field is currently valid.
  ///
  /// This is a **dedicated** Rx field, *not* an alias of `isSheetValid`.
  /// The sheet-level save gate should compose multiple sub-validations:
  ///
  /// ```dart
  /// isSheetValid.value =
  ///     isQtyValid.value && isBatchValid.value && isRackValid.value;
  /// ```
  RxBool get isQtyValid;

  /// Inline error text displayed beneath the qty [TextFormField].
  ///
  /// `''` → no error (field renders normally).
  /// Non-empty → displayed as `errorText` on the [InputDecoration].
  ///
  /// Same contract as [RackFieldDelegate.rackError] and
  /// [BatchNoFieldDelegate.batchError].
  RxString get qtyError;

  // ── QtyCapDelegate (re-declared for documentation clarity) ────────
  //
  // These two members are inherited from QtyCapDelegate.  They are
  // listed here only as documentation anchors; implementations do NOT
  // need to declare them twice.
  //
  //   String?   get qtyInfoText;       ← label shown on QtyCapBadge chip
  //   RxnString get qtyInfoTooltip;    ← breakdown dialog content

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
  /// field blur. Implementing controllers must write both [isQtyValid]
  /// and [qtyError] inside this method.
  ///
  /// Mirrors [BatchNoFieldDelegate.validateSheet].
  void validateSheet();
}
