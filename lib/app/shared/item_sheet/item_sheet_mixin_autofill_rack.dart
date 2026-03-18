import 'dart:developer';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// Mixin that automatically fills the rack field with the rack that holds
/// the most available stock, but only in add-mode.
///
/// Apply to: DeliveryNoteItemFormController, PurchaseReceiptItemFormController,
///           and any future DocType that opens a blank rack field on add.
///
/// Usage:
/// ```dart
/// class DeliveryNoteItemFormController extends ItemSheetControllerBase
///     with AutoFillRackMixin {
///
///   void initialise({...}) {
///     isAddMode = existingItem == null;
///     // ... load fields ...
///   }
/// }
/// ```
mixin AutoFillRackMixin on ItemSheetControllerBase {
  /// Set to true when the sheet is opened in add-mode (no existing item).
  /// Auto-fill only runs in add-mode to avoid overwriting operator edits.
  bool isAddMode = false;

  /// Called by [ItemSheetControllerBase.fetchRackStocks] once the rack
  /// stock map has been populated.
  @override
  void onRackStocksLoaded() {
    _autoFillBestRack();
  }

  void _autoFillBestRack() {
    if (!isAddMode) return;
    if (rackController.text.isNotEmpty) return;
    if (rackStockMap.isEmpty) return;

    final best = rackStockMap.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    log('[AutoFillRack] auto-filling rack="$best"');
    rackController.text = best;
    validateRack(best);
  }
}
