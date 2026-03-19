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
/// Lifecycle:
///   Get.put() just before bottomSheet opens  →  initialise()  →  sheet opens
///   sheet closes  →  Get.delete<DeliveryNoteItemFormController>()
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {
  // ── Parent reference ──────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  // ── DN-specific extra state ──────────────────────────────────────────

  /// The EAN-8 string captured from the last outside-sheet scan.
  String currentScannedEan8 = '';

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
  // Since P2-A added isValidatingRack to the base isSheetLoading getter this
  // override is technically redundant for DN.  It is kept as an explicit
  // declaration so that any future additional async path added to the DN child
  // only needs to extend this override rather than discovering the base.
  //
  // Note: the base now already covers isValidatingBatch + isValidatingRack +
  // isAddingItemFlag, so for DN the override simply calls super.

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

  // ── Initialisation ─────────────────────────────────────────────────────

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
    currentScannedEan8 = scannedEan8;

    // ── Step-2: wire base loading / scan flags to parent ───────────────────
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

    isBatchValid.value = item.batchNo != null && item.batchNo!.isNotEmpty;
    isRackValid.value  = item.rack    != null && item.rack!.isNotEmpty;

    if (item.batchNo != null && item.batchNo!.contains('-')) {
      currentScannedEan8 = item.batchNo!.split('-').first;
    }

    log('[DN:ItemSheet] loaded existing item=${item.name} batch=${item.batchNo} rack=${item.rack}',
        name: 'DN:ItemSheet');
  }

  // ── P1-A: _loadNewItem ───────────────────────────────────────────────────

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

    isBatchValid.value = batchNo != null && batchNo.isNotEmpty;
    isRackValid.value  = false;

    if (batchNo != null && batchNo.isNotEmpty) {
      validateBatchOnInit(batchNo);
    }

    log('[DN:ItemSheet] new item code=${itemCode.value} batch=$batchNo batchValid=${isBatchValid.value}',
        name: 'DN:ItemSheet');
  }

  /// Schedules a batch-validation call after the first frame.
  void validateBatchOnInit(String batch) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => validateBatch(batch));
  }

  // ── AutoFillRackMixin override ─────────────────────────────────────────────

  @override
  Future<void> fetchAllRackStocks() async {
    await super.fetchAllRackStocks();
    autoFillBestRack();
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

  // ── P1-B: submit ──────────────────────────────────────────────────────────

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
