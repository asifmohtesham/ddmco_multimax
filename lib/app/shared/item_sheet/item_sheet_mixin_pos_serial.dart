import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// Mixin for item-sheet controllers that belong to DocTypes linked to a
/// POS Upload (i.e. require an Invoice Serial Number selection).
///
/// Apply to: DeliveryNoteItemFormController, StockEntryItemFormController
///           (when entry source is Material Request from POS Upload).
///
/// Do NOT apply to: PurchaseReceiptItemFormController,
///                  PurchaseOrderItemFormController.
///
/// Usage:
/// ```dart
/// class DeliveryNoteItemFormController extends ItemSheetControllerBase
///     with PosSerialMixin {
///
///   @override
///   List<String> get availableSerialNos => _parent.bsAvailableInvoiceSerialNos;
/// }
/// ```
mixin PosSerialMixin on ItemSheetControllerBase {
  /// Currently selected POS Upload line / invoice serial number.
  /// Null means nothing is selected yet.
  var selectedSerial = RxnString();

  /// The list of valid serial numbers for the current POS Upload.
  /// Provided by the concrete class via the parent controller reference.
  /// Return an empty list when there is no linked POS Upload.
  List<String> get availableSerialNos;

  /// Returns true when the serial selection is acceptable:
  ///   - No serials available → always valid (non-POS doc).
  ///   - Serials available    → one must be selected.
  bool validateSerial() {
    if (availableSerialNos.isEmpty) return true;
    final v = selectedSerial.value;
    return v != null && v.isNotEmpty;
  }

  /// Clears the serial selection and re-validates the sheet.
  void clearSerial() {
    selectedSerial.value = null;
    validateSheet();
  }
}
