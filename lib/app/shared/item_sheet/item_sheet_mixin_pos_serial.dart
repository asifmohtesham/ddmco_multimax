import 'item_sheet_controller_base.dart';

/// Mixin for DocType item-sheet controllers that carry a POS-Upload invoice
/// serial number (e.g. Delivery Note, Stock Entry / Material Issue).
///
/// Usage:
/// ```dart
/// class DeliveryNoteItemFormController extends ItemSheetControllerBase
///     with PosSerialMixin {
///   @override
///   List<String> get availableSerialNos => _parent.posUpload.value?.items
///       .map((i) => i.idx.toString()).toList() ?? [];
/// }
/// ```
mixin PosSerialMixin on ItemSheetControllerBase {
  /// Currently selected invoice serial number.
  final selectedSerial = RxnString();

  /// List of valid serial numbers for the current POS Upload.
  /// Concrete class provides this from the parent document controller.
  List<String> get availableSerialNos;

  /// Returns true when the serial is valid (either not required, or selected).
  bool validateSerial() {
    if (availableSerialNos.isEmpty) return true;
    return selectedSerial.value != null && selectedSerial.value!.isNotEmpty;
  }

  /// Snapshot value for dirty-checking the serial field.
  String? _snapshotSerial;

  void captureSerialSnapshot() {
    _snapshotSerial = selectedSerial.value;
  }

  bool get isSerialDirty => selectedSerial.value != _snapshotSerial;
}
