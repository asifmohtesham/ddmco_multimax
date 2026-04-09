import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/barcode_aware_mixin.dart';
import 'package:multimax/app/shared/item_sheet/scan_scope.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

/// Item-level sheet controller for Packing Slip.
///
/// Extends [ItemSheetControllerBase] for the full animated item-sheet
/// infrastructure (save-button state, auto-submit worker, dirty tracking, etc.).
///
/// Commit 6 (serial refactor):
///   • Adopts [SerialFieldMixin] — full [SerialNumberFieldDelegate] compliance.
///   • [availableSerialNos] returns a single-element list seeded from
///     [PackingSlipFormController.currentSerial] when a POS Upload is loaded,
///     otherwise [] (widget hidden).
///   • [posItemQtyForSerial] delegates to [PackingSlipFormController.posQtyCapForSerial].
///   • [sumQtyUsedForSerial] sums qty for the serial across the current slip's
///     in-memory items list.
///   • [selectedSerial] is seeded in [initialise] so the dropdown is
///     pre-selected (read-only) on sheet open.
///   • [computeLiveRemaining] wired into [validateSheet] — cap badge reacts
///     to every qty keystroke.
///
/// Commit 6 (BarcodeAwareMixin wiring):
///   - `with BarcodeAwareMixin` added to the mixin chain.
///   - onInit() calls initBarcodeListeners() after super.onInit().
///   - activeScanScopes overridden to [itemBarcode] — PS has no batch or
///     rack fields on the item sheet.
///   - onItemBarcodeScanned stores barcode in currentScannedEan and
///     delegates to _parent.onItemBarcodeScanned(barcode).
class PackingSlipItemFormController extends ItemSheetControllerBase
    with SerialFieldMixin, BarcodeAwareMixin {
  // ── Parent reference ───────────────────────────────────────────────────────
  late PackingSlipFormController _parent;

  // ── In-sheet scan context ──────────────────────────────────────────────────
  String currentScannedEan = '';

  // ── ItemSheetControllerBase abstract overrides ─────────────────────────────

  @override
  String? get resolvedWarehouse => null;

  @override
  bool get requiresBatch => false;

  @override
  bool get requiresRack => false;

  @override
  Color get accentColor => Colors.teal;

  @override
  bool get isAddMode => editingItemName.value == null;

  @override
  String get qtyInfoText {
    final max = _parent.bsMaxQty.value;
    if (max > 0) return 'Remaining: ${max.toStringAsFixed(2)}';
    return '';
  }

  @override
  RxnString get qtyInfoTooltip => RxnString(null);

  @override
  MobileScannerController? get sheetScanController => null;

  // ── BarcodeAwareMixin: lifecycle ───────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    initBarcodeListeners();
  }

  // ── BarcodeAwareMixin: scope override ──────────────────────────────────────
  /// PS item sheet has no batch or rack fields; only item-barcode scan applies.
  @override
  List<ScanScope> get activeScanScopes =>
      const [ScanScope.itemBarcode];

  // ── BarcodeAwareMixin: item barcode scan ───────────────────────────────────
  @override
  void onItemBarcodeScanned(String barcode) {
    if (isClosed) return;
    currentScannedEan = barcode;
    _parent.onItemBarcodeScanned(barcode);
  }

  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final ceiling = _parent.bsMaxQty.value > 0
        ? _parent.bsMaxQty.value
        : double.infinity;
    final next = (current + delta).clamp(0.0, ceiling);
    qtyController.text =
        next.truncateToDouble() == next
            ? next.toInt().toString()
            : next.toStringAsFixed(2);
    validateSheet();
  }

  @override
  Future<void> deleteCurrentItem() => _parent.deleteCurrentItem();

  // ── SerialFieldMixin: availableSerialNos ────────────────────────────────────
  @override
  List<String> get availableSerialNos {
    if (_parent.posUpload.value == null) return [];
    final serial = _parent.currentSerial;
    if (serial == null || serial.isEmpty || serial == '0') return [];
    return [serial];
  }

  // ── SerialFieldMixin: POS qty cap for a given serial ───────────────────────
  @override
  double posItemQtyForSerial(String serial) =>
      _parent.posQtyCapForSerial(serial);

  // ── SerialFieldMixin: sum of all committed rows for this serial ────────────
  @override
  double sumQtyUsedForSerial(String serial) {
    return (_parent.packingSlip.value?.items ?? [])
        .where((i) => (i.customInvoiceSerialNumber ?? '0') == serial)
        .fold(0.0, (sum, i) => sum + i.qty);
  }

  // ── Sheet validation ────────────────────────────────────────────────────────

  @override
  void validateSheet() {
    final qty = double.tryParse(qtyController.text);

    if (qty == null || qty <= 0) {
      isSheetValid.value = false;
      return;
    }
    if (_parent.bsMaxQty.value > 0 && qty > _parent.bsMaxQty.value) {
      isSheetValid.value = false;
      return;
    }
    if (editingItemName.value != null && !isDirty) {
      isSheetValid.value = false;
      return;
    }

    computeLiveRemaining(
      currentTypedQty: qty,
      editingRowId:    editingItemName.value,
    );

    isSheetValid.value = true;
  }

  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty <= 0) return;
    await _parent.addItemToSlipWithQty(qty);
  }

  // ── Initialisation ──────────────────────────────────────────────────────────

  void initialise({
    required PackingSlipFormController parent,
    required String itemCode,
    required String itemName,
    PackingSlipItem? editingItem,
  }) {
    _parent = parent;

    isAddingItemFlag = parent.isAddingItem.value;

    this.itemCode.value = itemCode;
    this.itemName.value = itemName;

    final serial = parent.currentSerial;
    if (serial != null && serial.isNotEmpty && serial != '0') {
      selectedSerial.value = serial;
    } else {
      selectedSerial.value = null;
    }
    captureSerialSnapshot();

    if (editingItem != null) {
      editingItemName.value = editingItem.name;
      itemOwner.value       = editingItem.owner;
      itemCreation.value    = editingItem.creation;
      itemModified.value    = editingItem.modified;
      itemModifiedBy.value  = editingItem.modifiedBy;

      final qty = editingItem.qty;
      qtyController.text =
          qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    } else {
      editingItemName.value = null;
      itemOwner.value       = null;
      itemCreation.value    = null;
      itemModified.value    = null;
      itemModifiedBy.value  = null;

      final remaining = parent.bsMaxQty.value;
      qtyController.text = remaining > 0
          ? (remaining % 1 == 0
              ? remaining.toInt().toString()
              : remaining.toString())
          : '0';
    }

    initBaseListeners();
    captureSnapshot();
    validateSheet();
  }
}
