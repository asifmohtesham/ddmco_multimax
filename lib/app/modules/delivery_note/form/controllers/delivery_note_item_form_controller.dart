import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

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
/// Auto-submit wiring is handled by [ItemSheetControllerBase.setupAutoSubmit];
/// no worker duplication here.
///
/// Lifecycle:
///   Get.put() just before bottomSheet opens  →  initialise()  →  sheet opens
///   sheet closes  →  Get.delete<DeliveryNoteItemFormController>()
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {
  // ── Parent reference ───────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  // ── DN-specific extra state ────────────────────────────────────────────

  /// The EAN-8 string captured from the last outside-sheet scan.
  String currentScannedEan8 = '';

  // ── ItemSheetControllerBase contract ───────────────────────────────────

  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override
  bool get requiresBatch => true;

  @override
  bool get requiresRack => false;

  // ── PosSerialMixin contract ─────────────────────────────────────────────

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

  void _loadNewItem(String? batchNo) {
    editingItemName.value = null;

    itemOwner.value      = null;
    itemCreation.value   = null;
    itemModified.value   = null;
    itemModifiedBy.value = null;

    batchController.text = batchNo ?? '';
    rackController.clear();
    qtyController.text   = '6';
    selectedSerial.value = null;

    isBatchValid.value = batchNo != null && batchNo.isNotEmpty;
    isRackValid.value  = false;

    log('[DN:ItemSheet] new item code=${itemCode.value} batch=$batchNo batchValid=${isBatchValid.value}',
        name: 'DN:ItemSheet');
  }

  // ── AutoFillRackMixin override ────────────────────────────────────────────

  @override
  Future<void> fetchAllRackStocks() async {
    await super.fetchAllRackStocks();
    autoFillBestRack();
  }

  // ── validateSheet ─────────────────────────────────────────────────────────

  @override
  void validateSheet() {
    bool valid = baseValidate(); // requiresBatch=true enforced here

    if (!validateSerial()) valid = false;

    isFormDirty.value = isFieldsDirty || isSerialDirty;

    if (editingItemName.value != null && !isFormDirty.value) valid = false;

    isSheetValid.value = valid;
  }

  // ── submit ───────────────────────────────────────────────────────────────

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

    _parent.isDirty.value = true;
    await _parent.saveDeliveryNote();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onClose() {
    super.onClose(); // disposes TECs, FocusNode, scrollController, worker
  }
}
