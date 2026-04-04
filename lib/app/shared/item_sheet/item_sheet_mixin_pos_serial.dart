import 'package:get/get.dart';
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
///
///   @override
///   double get posItemQty =>
///       _parent.posQtyCapForSerial(selectedSerial.value ?? '');
/// }
/// ```
mixin PosSerialMixin on ItemSheetControllerBase {
  /// Currently selected invoice serial number.
  final selectedSerial = RxnString();

  /// List of valid serial numbers for the current POS Upload.
  /// Concrete class provides this from the parent document controller.
  List<String> get availableSerialNos;

  /// Total POS-Upload qty cap for the currently selected serial.
  ///
  /// Concrete class overrides this to delegate to the parent document
  /// controller (e.g. `_parent.posQtyCapForSerial(selectedSerial.value ?? '')`).
  /// Returns 0 when no serial is selected or there is no POS Upload loaded.
  double get posItemQty => 0.0;

  /// Human-readable ratio shown below the Invoice Serial No dropdown:
  ///   "$liveRemaining / $posItemQty"
  ///
  /// Returns null (chip hidden) when:
  ///   - no serial is selected, OR
  ///   - posItemQty is 0 (no POS Upload / no cap configured).
  ///
  /// This replaces the duck-typed `(controller as dynamic).posSerialCapText`
  /// pattern that was used in SharedSerialField, giving compile-time
  /// type-safety to all PosSerialMixin implementors.
  String? get posSerialCapText {
    final serial = selectedSerial.value;
    if (serial == null || serial.isEmpty) return null;
    final cap = posItemQty;
    if (cap <= 0) return null;
    final remaining = liveRemaining.value;
    final fmt = _fmtQty;
    return '${fmt(remaining)} / ${fmt(cap)}';
  }

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

  // ── Internal helper ──────────────────────────────────────────────────────

  /// Formats a qty value: drops trailing ".0" for whole numbers.
  String Function(double) get _fmtQty => (double v) {
        if (v == v.truncateToDouble()) return v.toInt().toString();
        return v.toStringAsFixed(2);
      };
}
