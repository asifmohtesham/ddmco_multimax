// ignore_for_file: lines_longer_than_80_chars

import 'qty_field_delegate.dart';
import 'qty_plus_minus_delegate.dart';

/// Combined qty-field + ± stepper contract.
///
/// This is the **primary interface** that [SharedQtyField] accepts as its
/// `c` parameter.  Any controller that implements both [QtyFieldDelegate]
/// and [QtyPlusMinusDelegate] automatically satisfies this interface.
///
/// ## Interface composition
///
/// | Interface               | Members                                           |
/// |-------------------------|---------------------------------------------------|
/// | [QtyFieldDelegate]      | isQtyValid, qtyError, qtyInfoText, qtyInfoTooltip,|
/// |                         | qtyController, validateSheet()                    |
/// | [QtyPlusMinusDelegate]  | isQtyReadOnly, effectiveMaxQty, adjustQty()       |
///
/// ## QtyFieldDelegate-only path
///
/// A lightweight controller that does NOT need ± buttons can implement
/// [QtyFieldDelegate] directly and pass it as [SharedQtyField.c].  The
/// widget conditionally renders stepper buttons only when `c` is also a
/// [QtyPlusMinusDelegate] at runtime:
///
/// ```dart
/// // No stepper — text-only qty entry
/// SharedQtyField(c: lightweightController, accentColor: Colors.teal)
///
/// // Full ± stepper + Max-Qty chip
/// SharedQtyField(c: seController, accentColor: Colors.teal)
/// ```
///
/// ## Contrast with RackFieldWithBrowseDelegate
///
/// [RackFieldWithBrowseDelegate] declares an extra `handleRackPicked` hook
/// because rack selection triggers an async round-trip.  Qty changes are
/// synchronous mutations; `adjustQty` already calls `validateSheet` before
/// returning, so no post-mutation hook is needed here.
abstract interface class QtyFieldWithPlusMinusDelegate
    implements QtyFieldDelegate, QtyPlusMinusDelegate {
  // No additional members.
  //
  // Composition is the sole purpose of this interface.  Adding members here
  // would widen the contract without justification — any DocType-specific
  // behaviour belongs on the concrete controller, not on the shared
  // interface.
}
