import 'dart:developer';
import 'package:flutter/material.dart';
import 'item_sheet_controller_base.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Mixin that auto-fills the rack field with the best-fit rack when the
/// user sets a positive quantity in add-mode.
///
/// ## Trigger semantics
/// Autofill fires once, on the first transition of the qty field from
/// blank / zero → a positive value, provided:
///   • [isAddMode] is true
///   • [autoFillRackController] is still empty (operator hasn't typed a rack)
///   • [rackStockMap] has been populated (via [fetchAllRackStocks])
///   • [resolvedWarehouse] is non-null / non-empty
///
/// ## Warehouse constraint
/// Rack names follow the company asset-code convention:
///
///   KA  - WH   - DXB1 - 101A
///   [0]   [1]    [2]    [3]
///   │      │      │      └─ Shelf ID: 3-digit rack number + shelf letter
///   │      │      └──────── Country / location counter (DXB1, DXB2, …)
///   │      └─────────────── Location type  (WH = Warehouse, POS = …)
///   └────────────────────── Company prefix (KA)
///
/// The corresponding ERPNext Warehouse name is derived as:
///   parts[1]-parts[2] + ' - ' + parts[0]
///   e.g.  KA-WH-DXB1-101A  →  "WH-DXB1 - KA"
///
/// This derivation is purely local — no extra API call is required.
///
/// ## Selection order
/// 1. Racks whose derived warehouse == [resolvedWarehouse] AND
///    qty >= requested qty  →  pick the one with the highest qty.
/// 2. No rack satisfies (1) for qty  →  pick the highest-qty
///    matching-warehouse rack, autofill it, show an insufficient-stock
///    warning.  [baseValidate] will block submission.
/// 3. No rack matches the warehouse at all  →  skip autofill, show a
///    warning snackbar so the operator is informed.
/// 4. [resolvedWarehouse] is null / empty  →  skip silently.
///
/// ## DocType hook overrides
/// By default the mixin writes to [rackController] and calls [validateRack]
/// — correct for Delivery Note, Purchase Receipt, Purchase Order.
///
/// DocTypes with a separate rack TEC (e.g. Stock Entry's sourceRackController)
/// must override the two protected hooks:
///
///   [autoFillRackController] — return the TEC to fill (default: rackController)
///   [onAutoFillRackSelected] — perform post-fill validation
///                              (default: validateRack(rack))
///
/// ## Usage
/// ```dart
/// // Simple DocType (DN, PR, PO) — no overrides needed:
/// class MyItemFormController extends ItemSheetControllerBase
///     with AutoFillRackMixin {
///
///   void initialise(...) {
///     ...
///     isAddMode = editingItem == null;
///     initBaseListeners();
///     initAutoFillListener();
///     ...
///   }
///
///   @override
///   void onClose() {
///     disposeAutoFillListener();
///     super.onClose();
///   }
/// }
///
/// // DocType with separate source-rack TEC (SE):
/// class StockEntryItemFormController extends ItemSheetControllerBase
///     with AutoFillRackMixin {
///
///   final TextEditingController sourceRackController = TextEditingController();
///
///   @override
///   TextEditingController get autoFillRackController => sourceRackController;
///
///   @override
///   void onAutoFillRackSelected(String rack) => validateDualRack(rack, true);
/// }
/// ```
mixin AutoFillRackMixin on ItemSheetControllerBase {
  // ── Internal listener reference ──────────────────────────────────────────
  VoidCallback? _autoFillQtyListener;

  // ── Protected hooks (override in DocTypes with separate rack TECs) ───────

  /// The TEC that autofill writes the selected rack name into.
  ///
  /// Default: [rackController] — correct for DN, PR, PO.
  /// SE override: [sourceRackController].
  TextEditingController get autoFillRackController => rackController;

  /// Called immediately after the rack name is written to
  /// [autoFillRackController].  Perform whatever validation the DocType
  /// requires for the newly set rack.
  ///
  /// Default: calls [validateRack(rack)] — correct for DN, PR, PO.
  /// SE override: calls [validateDualRack(rack, true)].
  void onAutoFillRackSelected(String rack) => validateRack(rack);

  // ── Rack-name → warehouse derivation ────────────────────────────────────

  /// Derives the ERPNext Warehouse name from a rack asset-code name.
  ///
  /// Pattern: `KA-WH-DXB1-101A`  →  `"WH-DXB1 - KA"`
  ///
  /// Returns null if the rack name does not conform to the expected
  /// 4-part pattern (safe: caller treats null as no-match).
  static String? _warehouseFromRackName(String rackName) {
    final parts = rackName.split('-');
    // Minimum required parts: company(0), location(1), countryCode(2), shelf(3)
    if (parts.length < 4) return null;
    return '${parts[1]}-${parts[2]} - ${parts[0]}';
  }

  // ── Listener lifecycle ───────────────────────────────────────────────────

  /// Attaches the qty-field listener that drives autofill.
  /// Call this from [initialise] after [isAddMode] is set and after
  /// [initBaseListeners].
  void initAutoFillListener() {
    _autoFillQtyListener = _onQtyChangedForAutoFill;
    qtyController.addListener(_autoFillQtyListener!);
  }

  /// Removes the qty listener. Call from [onClose] before [super.onClose].
  void disposeAutoFillListener() {
    if (_autoFillQtyListener != null) {
      qtyController.removeListener(_autoFillQtyListener!);
      _autoFillQtyListener = null;
    }
  }

  // ── Qty change handler ───────────────────────────────────────────────────

  void _onQtyChangedForAutoFill() {
    if (!isAddMode) return;
    if (autoFillRackController.text.isNotEmpty) return; // operator already typed
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty <= 0) return;
    if (rackStockMap.isEmpty) return;

    // Detach immediately so this fires only once per add-mode session.
    disposeAutoFillListener();

    autoFillRackForQty(qty);
  }

  // ── Core autofill logic ──────────────────────────────────────────────────

  /// Selects and pre-fills the best rack for [qty], constrained to
  /// [resolvedWarehouse].  See class-level doc for selection order.
  void autoFillRackForQty(double qty) {
    if (!isAddMode) return;
    if (autoFillRackController.text.isNotEmpty) return;
    if (rackStockMap.isEmpty) return;

    final targetWh = resolvedWarehouse;

    // Decision 4: silently skip when no source warehouse is set.
    if (targetWh == null || targetWh.isEmpty) {
      log('[AutoFillRack] resolvedWarehouse is null — skipping autofill',
          name: 'ItemSheet');
      return;
    }

    // Partition rackStockMap into matching-warehouse entries.
    final matchingEntries = rackStockMap.entries.where((e) {
      final derivedWh = _warehouseFromRackName(e.key);
      return derivedWh != null &&
          derivedWh.toLowerCase() == targetWh.toLowerCase();
    }).toList();

    // Decision 3: no rack at all belongs to the source warehouse.
    if (matchingEntries.isEmpty) {
      log('[AutoFillRack] no rack matches warehouse="$targetWh" — skipping',
          name: 'ItemSheet');
      GlobalSnackbar.warning(
        message: 'No rack found in the source warehouse ($targetWh). '
            'Please select a rack manually.',
      );
      return;
    }

    // Sort matching entries by qty descending.
    matchingEntries.sort((a, b) => b.value.compareTo(a.value));

    // Decision 1: prefer a rack with qty >= requested.
    final sufficient = matchingEntries.where((e) => e.value >= qty).toList();

    final String best;
    if (sufficient.isNotEmpty) {
      best = sufficient.first.key;
      log('[AutoFillRack] auto-filling rack="$best" '
          '(qty=${matchingEntries.firstWhere((e) => e.key == best).value} >= $qty)',
          name: 'ItemSheet');
    } else {
      // Decision 2: fall back to best available, warn about insufficient stock.
      best = matchingEntries.first.key;
      final available = matchingEntries.first.value;
      log('[AutoFillRack] insufficient stock — auto-filling rack="$best" '
          '(available=$available < requested=$qty)',
          name: 'ItemSheet');
      GlobalSnackbar.warning(
        message: 'Insufficient stock in rack "$best" (available: $available). '
            'Please verify before saving.',
      );
    }

    autoFillRackController.text = best;
    onAutoFillRackSelected(best);
  }
}
