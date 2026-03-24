import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';

// Shared base + mixins
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_pos_serial.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_autofill_rack.dart';

// Domain model
import 'package:multimax/app/data/models/delivery_note_model.dart';

// Parent controller
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';

/// Item-level sheet controller for Delivery Note.
///
/// Extends [ItemSheetControllerBase] and mixes in:
///   • [PosSerialMixin]    — invoice serial-number selector (POS Upload flow)
///   • [AutoFillRackMixin] — auto-selects the best-stock rack in add-mode
///
/// Step-2 additions:
///   • [isAddingItemFlag]    wired to _parent.isAddingItem
///   • [isScanning]         wired to _parent.isScanning
///   • [sheetScanController] wired to _parent.barcodeController
///   • [qtyInfoText]        'Max Available: N' or null
///   • [deleteCurrentItem]  resolves item + calls parent.confirmAndDeleteItem
///
/// P1-A: _loadNewItem no longer hard-codes qty '6'; clears the field instead.
/// P1-A: _loadNewItem now pre-validates batch when batchNo is supplied, matching SE.
/// P1-B: submit() removed its own save call; the parent onSubmit lambda owns saving.
/// P2-D: isSheetLoading overridden to also cover isValidatingRack (mirrors P1-C for SE).
///
/// Standardisation S1:
///   • [currentScannedEan8] — removed; use base field [currentScannedEan].
///   • [validateBatchOnInit] — removed local duplicate; use base method.
///   • [isBatchReadOnly]    — wired in _loadExistingItem (lock on existing batch).
///
/// Standardisation S7:
///   • [applyRackScan]  — added; delegates to rackController + validateRack,
///                        matching PR pattern for scan-bar rack routing.
///   • [resetRack]      — overridden; calls super, explicit extension point
///                        for future DN-specific rack state.
///
/// Sheet-close responsibility:
///   • submit() does NOT call Get.back().
///   • Sheet dismissal is owned exclusively by the parent coordinator
///     (_openItemSheet onSubmit lambda), matching the SRP boundary
///     established in Phase-1 (commit f2aeb9a).
///
/// Lifecycle:
///   Get.put() just before bottomSheet opens  →  initialise()  →  sheet opens
///   sheet closes  →  Get.delete<DeliveryNoteItemFormController>()
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {
  // ── Parent reference ────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  // currentScannedEan8  → base field currentScannedEan (S1)
  // validateBatchOnInit → base method (S1)

  // ── ItemSheetControllerBase contract ─────────────────────────────────────

  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override
  bool get requiresBatch => true;

  @override
  bool get requiresRack => false;

  // ── P2-D: isSheetLoading override ─────────────────────────────────────────
  //
  // Base already covers isValidatingBatch + isValidatingRack + isAddingItemFlag.
  // Override kept as an explicit extension point for future DN-specific flags.

  @override
  bool get isSheetLoading => super.isSheetLoading;

  // ── Step-2: qtyInfoText ───────────────────────────────────────────────

  @override
  String? get qtyInfoText {
    final max = maxQty.value;
    if (max <= 0) return null;
    return 'Max Available: ${max % 1 == 0 ? max.toInt() : max}';
  }

  // ── Step-2: deleteCurrentItem ─────────────────────────────────────────

  @override
  Future<void> deleteCurrentItem() async {
    final name = editingItemName.value;
    if (name == null) return;
    final item = _parent.deliveryNote.value?.items
        .firstWhereOrNull((i) => i.name == name);
    if (item != null) _parent.confirmAndDeleteItem(item);
  }

  // ── PosSerialMixin contract ────────────────────────────────────────────

  @override
  List<String> get availableSerialNos =>
      _parent.posUpload.value?.items
          .map((i) => i.idx.toString())
          .toList() ??
      [];

  // ── Initialisation ───────────────────────────────────────────────────

  void initialise({
    required DeliveryNoteFormController parent,
    required String code,
    required String name,
    String? batchNo,
    double initialMaxQty = 0.0,
    DeliveryNoteItem? editingItem,
    String scannedEan8 = '',
  }) {
    _parent = parent;
    currentScannedEan = scannedEan8; // S1: base field

    isAddingItemFlag    = _parent.isAddingItem;
    isScanning          = _parent.isScanning;
    sheetScanController = _parent.barcodeController;

    itemCode.value = code;
    itemName.value = name;
    maxQty.value   = initialMaxQty;
    rackStockMap.clear();
    rackStockTooltip.value = null;
    rackError.value        = null;
    batchError.value       = null;
    batchInfoTooltip.value = null;

    if (editingItem != null) {
      _loadExistingItem(editingItem);
    } else {
      _loadNewItem(batchNo);
    }

    initBaseListeners();
    ever(selectedSerial, (_) => validateSheet());

    captureSnapshot();
    captureSerialSnapshot();

    isAddMode = editingItem == null;

    validateSheet();
    fetchAllRackStocks();
  }

  void _loadExistingItem(DeliveryNoteItem item) {
    editingItemName.value = item.name;

    itemOwner.value      = item.owner;
    itemCreation.value   = item.creation;
    itemModified.value   = item.modified;
    itemModifiedBy.value = item.modifiedBy;

    batchController.text = item.batchNo ?? '';
    rackController.text  = item.rack   ?? '';
    qtyController.text   = item.qty % 1 == 0
        ? item.qty.toInt().toString()
        : item.qty.toString();
    selectedSerial.value = item.customInvoiceSerialNumber;

    isBatchValid.value    = item.batchNo != null && item.batchNo!.isNotEmpty;
    isBatchReadOnly.value = isBatchValid.value; // S1
    isRackValid.value     = item.rack != null && item.rack!.isNotEmpty;

    if (item.batchNo != null && item.batchNo!.contains('-')) {
      currentScannedEan = item.batchNo!.split('-').first; // S1
    }

    log('[DN:ItemSheet] loaded existing item=${item.name} batch=${item.batchNo} rack=${item.rack}',
        name: 'DN:ItemSheet');
  }

  void _loadNewItem(String? batchNo) {
    editingItemName.value = null;

    itemOwner.value      = null;
    itemCreation.value   = null;
    itemModified.value   = null;
    itemModifiedBy.value = null;

    batchController.text = batchNo ?? '';
    rackController.clear();
    qtyController.clear();
    selectedSerial.value = null;

    isBatchValid.value    = batchNo != null && batchNo.isNotEmpty;
    isBatchReadOnly.value = false; // S1: new item — batch field unlocked
    isRackValid.value     = false;

    if (batchNo != null && batchNo.isNotEmpty) {
      validateBatchOnInit(batchNo); // S1: base method
    }

    log('[DN:ItemSheet] new item code=${itemCode.value} batch=$batchNo batchValid=${isBatchValid.value}',
        name: 'DN:ItemSheet');
  }

  // ── AutoFillRackMixin override ────────────────────────────────────────────

  @override
  Future<void> fetchAllRackStocks() async {
    await super.fetchAllRackStocks();
    autoFillBestRack();
  }

  // ── S7: applyRackScan ──────────────────────────────────────────────────────

  void applyRackScan(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  // ── S7: resetRack override ─────────────────────────────────────────────────

  @override
  void resetRack() {
    super.resetRack();
  }

  // ── validateSheet ─────────────────────────────────────────────────────────

  @override
  void validateSheet() {
    bool valid = baseValidate();

    if (!validateSerial()) valid = false;

    isFormDirty.value = isFieldsDirty || isSerialDirty;

    if (editingItemName.value != null && !isFormDirty.value) valid = false;

    isSheetValid.value = valid;
  }

  // ── P1-B: submit — delegates to parent only (sheet close owned by parent coordinator)

  @override
  Future<void> submit() async {
    final qty    = double.tryParse(qtyController.text) ?? 0;
    final rack   = rackController.text;
    final batch  = batchController.text;
    final serial = selectedSerial.value;

    if (editingItemName.value != null && editingItemName.value!.isNotEmpty) {
      _parent.updateItemLocally(editingItemName.value!, qty, rack, batch, serial);
    } else {
      _parent.addItemLocally(itemCode.value, itemName.value, qty, rack, batch, serial);
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onClose() {
    super.onClose();
  }
}
