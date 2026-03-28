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
///   • [AutoFillRackMixin] — auto-selects the best-fit rack once the operator
///                           enters a positive qty in add-mode
///
/// DN-A  (delivery_note_form_controller.dart)
///   • remainingQtyForSerial() helper added to parent.
///
/// DN-B:
///   • [rackBalance] — RxDouble mirroring SE; written by _updateRackBalance()
///     on every validateSheet() call. Reads rackStockMap[rackController.text]
///     — no extra network call.
///
/// DN-C:
///   • [effectiveMaxQty] — ceiling chain:
///       1. POS serial remaining
///       2. Batch balance (maxQty)
///       3. Rack balance (rackBalance)
///     Returns 999999.0 sentinel when no ceiling active.
///
/// DN-D (this commit):
///   • [liveRemaining]    — RxDouble on base; written in validateSheet();
///                          drives SharedSerialField chip rebuild.
///   • [posSerialCapText] — chip label 'Invoice #N — Remaining: X / Y pcs'.
///   • [qtyInfoText]      — 'Max: N' / 'Max: -' via effectiveMaxQty.
///   • [qtyInfoTooltip]   — 'Serial: X  ·  Batch: Y  ·  Rack: Z' breakdown.
///
/// Sheet-close responsibility:
///   • submit() does NOT call Get.back().
///   • Sheet dismissal is owned exclusively by the parent coordinator
///     (_openItemSheet onSubmit lambda).
///
/// Lifecycle:
///   Get.put() just before bottomSheet opens  →  initialise()  →  sheet opens
///   sheet closes  →  Get.delete<DeliveryNoteItemFormController>()
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {
  // ── Parent reference ──────────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  // ── DN-B: rack balance (mirrors SE rackBalance) ───────────────────────────
  var rackBalance = 0.0.obs;

  // ── ItemSheetControllerBase contract ─────────────────────────────────────

  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override
  bool get requiresBatch => true;

  @override
  bool get requiresRack => false;

  @override
  bool get isSheetLoading => super.isSheetLoading;

  // ── DN-C: effectiveMaxQty ceiling chain ───────────────────────────────────

  double get effectiveMaxQty {
    double limit = 999999.0;

    // 1. POS serial remaining
    final serial = selectedSerial.value;
    if (serial != null &&
        serial != '0' &&
        serial.isNotEmpty &&
        _parent.posUpload.value != null) {
      final cap  = _parent.posQtyCapForSerial(serial);
      final used = _parent.scannedQtyForSerial(
          serial, excludeItemName: editingItemName.value);
      final rem  = (cap - used).clamp(0.0, double.infinity);
      if (rem < limit) limit = rem;
    }

    // 2. Batch balance
    if (maxQty.value > 0 && maxQty.value < limit) limit = maxQty.value;

    // 3. Rack balance
    if (isRackValid.value && rackBalance.value > 0 && rackBalance.value < limit)
      limit = rackBalance.value;

    return limit;
  }

  // ── DN-D: posSerialCapText — chip label (mirrors SE Commit A) ─────────────
  //
  // Consumed by SharedSerialField via duck-typed
  // (controller as dynamic).posSerialCapText — same mechanism as SE.
  // Returns null when no serial is active → chip hidden.

  String? get posSerialCapText {
    final serial = selectedSerial.value;
    if (serial == null || serial == '0' || serial.isEmpty) return null;
    if (_parent.posUpload.value == null) return null;

    final serialNo  = int.tryParse(serial) ?? 0;
    final cap       = _parent.posQtyCapForSerial(serial);
    final used      = _parent.scannedQtyForSerial(
        serial, excludeItemName: editingItemName.value);
    final remaining = (cap - used).clamp(0.0, cap);

    String fmt(double v) =>
        v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

    return 'Invoice #$serialNo \u2014 Remaining: ${fmt(remaining)} / ${fmt(cap)} pcs';
  }

  // ── DN-D: qtyInfoText — 'Max: N' / 'Max: -' (mirrors SE Commit C-2) ──────
  //
  // Always returns a non-null string so the Qty badge is always present.
  // 'Max: -' signals no ceiling yet computed.

  @override
  String? get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff >= 999999.0) return 'Max: -';
    final n = eff % 1 == 0 ? eff.toInt().toString() : eff.toStringAsFixed(2);
    return 'Max: $n';
  }

  // ── DN-D: qtyInfoTooltip — breakdown on badge tap (mirrors SE Commit C-2) ──
  //
  // Builds a ·-separated list of every active ceiling with its value.
  // Returns null when no ceiling is active → widget hides tap target.

  @override
  String? get qtyInfoTooltip {
    final parts = <String>[];

    // Serial remaining (POS)
    final serial = selectedSerial.value;
    if (serial != null &&
        serial != '0' &&
        serial.isNotEmpty &&
        _parent.posUpload.value != null) {
      final cap  = _parent.posQtyCapForSerial(serial);
      final used = _parent.scannedQtyForSerial(
          serial, excludeItemName: editingItemName.value);
      final rem  = (cap - used).clamp(0.0, cap);
      final remStr = rem % 1 == 0
          ? rem.toInt().toString()
          : rem.toStringAsFixed(2);
      parts.add('Serial: $remStr');
    }

    // Batch balance
    if (maxQty.value > 0) {
      final b = maxQty.value;
      parts.add('Batch: ${b % 1 == 0 ? b.toInt() : b.toStringAsFixed(2)}');
    }

    // Rack balance
    if (isRackValid.value && rackBalance.value > 0) {
      final r = rackBalance.value;
      parts.add('Rack: ${r % 1 == 0 ? r.toInt() : r.toStringAsFixed(2)}');
    }

    if (parts.isEmpty) return null;
    return parts.join('  \u00b7  ');
  }

  // ── Step-2: deleteCurrentItem ───────────────────────────────────────────────

  @override
  Future<void> deleteCurrentItem() async {
    final name = editingItemName.value;
    if (name == null) return;
    final item = _parent.deliveryNote.value?.items
        .firstWhereOrNull((i) => i.name == name);
    if (item != null) _parent.confirmAndDeleteItem(item);
  }

  // ── PosSerialMixin contract ──────────────────────────────────────────────────

  @override
  List<String> get availableSerialNos =>
      _parent.posUpload.value?.items
          .map((i) => i.idx.toString())
          .toList() ??
      [];

  // ── Initialisation ─────────────────────────────────────────────────────────────

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
    currentScannedEan = scannedEan8;

    isAddingItemFlag    = _parent.isAddingItem;
    isScanning          = _parent.isScanning;
    sheetScanController = _parent.barcodeController;

    itemCode.value    = code;
    itemName.value    = name;
    maxQty.value      = initialMaxQty;
    rackBalance.value = 0.0;   // DN-B
    liveRemaining.value = 0.0; // DN-D
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

    isAddMode = editingItem == null;

    initBaseListeners();
    initAutoFillListener();
    ever(selectedSerial, (_) => validateSheet());

    captureSnapshot();
    captureSerialSnapshot();

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
    rackController.text  = item.rack    ?? '';
    qtyController.text   = item.qty % 1 == 0
        ? item.qty.toInt().toString()
        : item.qty.toString();
    selectedSerial.value = item.customInvoiceSerialNumber;

    isBatchValid.value    = item.batchNo != null && item.batchNo!.isNotEmpty;
    isBatchReadOnly.value = isBatchValid.value;
    isRackValid.value     = item.rack != null && item.rack!.isNotEmpty;

    if (item.batchNo != null && item.batchNo!.contains('-')) {
      currentScannedEan = item.batchNo!.split('-').first;
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
    isBatchReadOnly.value = false;
    isRackValid.value     = false;

    if (batchNo != null && batchNo.isNotEmpty) {
      validateBatchOnInit(batchNo);
    }

    log('[DN:ItemSheet] new item code=${itemCode.value} batch=$batchNo batchValid=${isBatchValid.value}',
        name: 'DN:ItemSheet');
  }

  // ── S7: applyRackScan ────────────────────────────────────────────────────────

  void applyRackScan(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  // ── S7: resetRack override ────────────────────────────────────────────────────

  @override
  void resetRack() {
    super.resetRack();
  }

  // ── DN-B: _updateRackBalance ───────────────────────────────────────────────────

  void _updateRackBalance() {
    final rack = rackController.text.trim();
    if (rack.isEmpty || !isRackValid.value) {
      rackBalance.value = 0.0;
      return;
    }
    rackBalance.value = rackStockMap[rack] ?? 0.0;
  }

  // ── validateSheet ─────────────────────────────────────────────────────────────

  @override
  void validateSheet() {
    _updateRackBalance(); // DN-B

    bool valid = true;

    final qty    = double.tryParse(qtyController.text) ?? 0;
    final effMax = effectiveMaxQty; // DN-C
    if (qty <= 0) valid = false;
    if (effMax < 999999.0 && qty > effMax) valid = false;

    if (batchController.text.isEmpty || !isBatchValid.value) valid = false;

    if (!validateSerial()) valid = false;

    // DN-D: sync liveRemaining → chip Obx rebuilds on qty change
    final serial = selectedSerial.value;
    if (serial != null &&
        serial != '0' &&
        serial.isNotEmpty &&
        _parent.posUpload.value != null) {
      final cap  = _parent.posQtyCapForSerial(serial);
      final used = _parent.scannedQtyForSerial(
          serial, excludeItemName: editingItemName.value);
      liveRemaining.value = (cap - used).clamp(0.0, cap);
    } else {
      liveRemaining.value = 0.0;
    }

    isFormDirty.value = isFieldsDirty || isSerialDirty;

    if (editingItemName.value != null && !isFormDirty.value) valid = false;

    isSheetValid.value = valid;
  }

  // ── submit ───────────────────────────────────────────────────────────────────

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

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void onClose() {
    disposeAutoFillListener();
    super.onClose();
  }
}
