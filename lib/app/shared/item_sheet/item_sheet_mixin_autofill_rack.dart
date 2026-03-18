import 'dart:developer';
import 'item_sheet_controller_base.dart';

/// Mixin that auto-fills the rack field with the best-stock rack when the
/// sheet opens in add-mode and the rack field is still empty.
///
/// Usage:
/// ```dart
/// class DeliveryNoteItemFormController extends ItemSheetControllerBase
///     with AutoFillRackMixin {
///   ...
///   @override
///   Future<void> fetchAllRackStocks() async {
///     await super.fetchAllRackStocks();
///     autoFillBestRack(); // called AFTER map is populated
///   }
/// }
/// ```
mixin AutoFillRackMixin on ItemSheetControllerBase {
  /// Set to true when opening the sheet for a NEW item (not editing).
  bool isAddMode = false;

  /// Picks the rack with the highest available qty and pre-fills the rack
  /// field. Only acts when [isAddMode] is true and rack field is empty.
  void autoFillBestRack() {
    if (!isAddMode) return;
    if (rackController.text.isNotEmpty) return; // operator already typed
    if (rackStockMap.isEmpty) return;

    final best = rackStockMap.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    log('[AutoFillRack] auto-filling rack="$best"', name: 'ItemSheet');
    rackController.text = best;
    validateRack(best);
  }
}
