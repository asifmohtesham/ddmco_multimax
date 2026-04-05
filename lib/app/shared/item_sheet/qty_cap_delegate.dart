// ignore_for_file: lines_longer_than_80_chars

import 'package:get/get.dart';

/// Narrow contract consumed by [QtyCapBadge].
///
/// Any controller that supplies a qty-cap label and an optional tooltip
/// string can render the badge — no inheritance of [ItemSheetControllerBase]
/// required.
///
/// ## Existing implementors
///
/// [ItemSheetControllerBase] already declares both [qtyInfoText] (abstract
/// getter) and [qtyInfoTooltip] (concrete RxnString field).  Adding
/// `implements QtyCapDelegate` to the base class in Commit 4 satisfies this
/// interface with zero additional code.
///
/// ## Design note
///
/// [qtyInfoText] is a plain [String?] getter (not Rx) because the label is
/// computed synchronously from existing Rx fields inside [validateSheet].
/// The Obx in [QtyCapBadge.build] rebuilds when [qtyInfoTooltip] changes;
/// it also rebuilds whenever the enclosing Obx in [SharedQtyField] rebuilds
/// on any Rx change, which is sufficient to refresh the label.
abstract interface class QtyCapDelegate {
  /// Human-readable cap label shown on the badge chip.
  ///
  /// Returns `null` to suppress the badge entirely.
  /// Examples: `'Max: 12'`, `'Max: 6.5 Kg'`, `null`.
  String? get qtyInfoText;

  /// Full tooltip string surfaced in the breakdown dialog when the badge
  /// is tapped.  `null` = badge is not tappable (no info icon shown).
  ///
  /// Backed by [RxnString] so [QtyCapBadge] can subscribe to changes via
  /// [Obx].
  RxnString get qtyInfoTooltip;
}
