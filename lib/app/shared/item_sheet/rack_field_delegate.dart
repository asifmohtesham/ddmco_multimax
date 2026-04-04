// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Reactive rack-field state contract.
///
/// Any controller that wants to host [SharedRackField] must satisfy this
/// interface.  The contract is intentionally narrower than
/// [ItemSheetControllerBase] so that future DocType controllers do not
/// need to inherit the full item-sheet base class just to reuse the rack
/// widget.
///
/// ## Why a separate interface?
///
/// Before the [RackFieldWithBrowseDelegate] refactor, [SharedRackField]
/// held a hard dependency on [ItemSheetControllerBase].  This meant:
///
/// - Any DocType whose controller did not extend the base class could not
///   use the widget.
/// - Tests were forced to instantiate a full [GetxController] subclass.
/// - Future extensions (e.g. a lightweight rack-only widget) would carry
///   unnecessary coupling.
///
/// This interface extracts only the members [SharedRackField] actually
/// reads, so both the existing base class (via `implements`) and any
/// future lightweight controller can satisfy it with zero extra cost.
///
/// ## Reactive fields
///
/// All state fields are `Rx*` so that `Obx` widgets inside
/// [SharedRackField] rebuild correctly when the controller mutates them.
///
/// ## Error semantics — ENFORCED CONTRACT (Commit 2 of 4)
///
/// [rackError] is **[RxString]** (non-nullable).  An **empty string (`''`)
/// means no error is present**.  Callers MUST check
/// `rackError.value.isNotEmpty` — never `!= null`.
///
/// Rationale (Commit 2 audit):
///   • [ItemSheetControllerBase] declares `rackError = RxString('')`.
///   • [StockEntryItemFormController], [DeliveryNoteItemFormController],
///     and [PurchaseReceiptItemFormController] all write
///     `rackError.value = ''` on success and a non-empty string on
///     failure — no nullable assignment anywhere.
///   • [SharedRackField] (_SimpleRack and _EditModeRack) checks
///     `c.rackError.value.isNotEmpty` in both modes — no null checks
///     remain in the widget layer.
///
/// This is now the **sealed contract**: implementors of this interface
/// MUST declare `rackError` as `RxString` and MUST use `''` to signal
/// the no-error state.  Using `RxnString` or assigning `null` is a
/// contract violation and will cause a runtime type error when the widget
/// calls `.isNotEmpty` on the value.
///
/// ## rackStockTooltip semantics
///
/// [rackStockTooltip] is [RxnString] where **`null` means no tooltip**
/// should be rendered.  The widget checks `rackStockTooltip.value != null`
/// before building the tooltip widget.
///
/// ## Constructor type switch (Commit 3 of 4)
///
/// [SharedRackField.c] is typed against [RackFieldWithBrowseDelegate]
/// (a super-interface of this class that adds the rack browser contract).
/// The switch from `ItemSheetControllerBase c` to
/// `RackFieldWithBrowseDelegate c` was confirmed complete in the Commit 3
/// audit:
///
///   • `shared_rack_field.dart` declares `final RackFieldWithBrowseDelegate c`
///     — no reference to [ItemSheetControllerBase] anywhere in the widget.
///   • [ItemSheetControllerBase] declares
///     `implements RackFieldWithBrowseDelegate` with four default overrides:
///     [rackBalanceFor], [canBrowseRacks], [browseRacks], [handleRackPicked].
///   • All existing call sites (SE, DN, PR) pass controllers that extend
///     [ItemSheetControllerBase] → transitively satisfy the interface.
///     Zero call-site changes required.
///
/// Any future DocType controller that implements [RackFieldWithBrowseDelegate]
/// directly (without inheriting [ItemSheetControllerBase]) is now a
/// first-class citizen of [SharedRackField] — zero extra ceremony.
///
/// ## Changelog
///
/// Commit 2 of 4 — Standardize rackError to non-nullable RxString:
///   • Full codebase audit confirmed zero nullable rackError usages.
///   • Contract sealed: RxString + '' = no-error is now the enforced rule.
///   • No runtime changes — this commit is documentation + contract lock.
///
/// Commit 3 of 4 — Switch SharedRackField constructor type:
///   • Audit confirmed SharedRackField.c already typed as
///     RackFieldWithBrowseDelegate — not ItemSheetControllerBase.
///   • ItemSheetControllerBase already implements RackFieldWithBrowseDelegate
///     with all four required overrides (rackBalanceFor, canBrowseRacks,
///     browseRacks, handleRackPicked) — confirmed in base class changelog.
///   • All SE / DN / PR call sites satisfy the interface transitively.
///   • No runtime changes — implementation was already in its target state.
abstract interface class RackFieldDelegate {
  // ── Reactive state ────────────────────────────────────────────────────────

  /// Whether the current rack value has been confirmed valid by the server.
  RxBool get isRackValid;

  /// Whether a rack validation round-trip is currently in flight.
  RxBool get isValidatingRack;

  /// Validation error text for the rack field.
  ///
  /// **Empty string (`''`) means no error.** Check `rackError.value.isNotEmpty`.
  /// Never null.  Declaring this as [RxnString] or assigning `null` is a
  /// contract violation — see class-level doc for the full rationale.
  RxString get rackError;

  /// Tooltip text shown in the rack field suffix (e.g. `'12 units in stock'`).
  /// `null` means no tooltip should be rendered.
  RxnString get rackStockTooltip;

  // ── Text / focus controllers ──────────────────────────────────────────────

  /// Text controller backing the rack input field.
  /// Lifecycle (create / dispose) is owned by the implementing controller.
  TextEditingController get rackController;

  /// Focus node for the rack text field.
  /// Lifecycle is owned by the implementing controller.
  FocusNode get rackFocusNode;

  // ── Balance ───────────────────────────────────────────────────────────────

  /// Returns the available balance for the given [rack] identifier.
  ///
  /// This method replaces the previous pattern of exposing `rackStockMap`
  /// directly on the controller.  Abstracting the lookup here means:
  /// - Controllers that pre-load a `Map<String, double>` return
  ///   `rackStockMap[rack] ?? 0.0`.
  /// - Controllers that maintain a live [RxDouble] balance return
  ///   `rackBalance.value`.
  /// - The [SharedRackField] widget reads balance via a single call
  ///   regardless of which strategy the controller uses.
  ///
  /// The [balanceOverride] constructor parameter on [SharedRackField]
  /// remains available for call sites that need to supply a closure
  /// instead of going through the delegate (e.g. legacy DN sites).
  double rackBalanceFor(String rack);

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Clears the rack text field, resets all rack validity state, and zeros
  /// the rack balance.  Called when the user taps the clear / edit button.
  void resetRack();

  /// Validates [rack] against the server and populates [isRackValid],
  /// [rackError], and [rackBalance] accordingly.
  ///
  /// Implementations must:
  /// 1. Set [isValidatingRack] = true at the start.
  /// 2. Set [isValidatingRack] = false in a `finally` block.
  /// 3. Set [rackError] = '' on success, a non-empty string on failure.
  /// 4. Set [isRackValid] = true only on success.
  Future<void> validateRack(String rack);
}
