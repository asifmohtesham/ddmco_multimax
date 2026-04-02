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
///       2. Batch balance (batchBalance)
///       3. Rack balance  (rackBalance)
///     Returns 999999.0 sentinel when no ceiling active.
///
/// DN-D:
///   • [liveRemaining]    — RxDouble on base; written in validateSheet();
///                          drives SharedSerialField chip rebuild.
///   • [posSerialCapText] — chip label 'Invoice #N — Remaining: X / Y pcs'.
///   • [qtyInfoText]      — 'Max: N' / 'Max: -' via effectiveMaxQty.
///   • [qtyInfoTooltip]   — 'Serial: X  ·  Batch: Y  ·  Rack: Z' breakdown.
///
/// Commit 7 (this commit):
///   • Removed `maxQty.value = initialMaxQty` from [initialise] — maxQty is
///     a computed getter in the base class (Commit 4) and cannot be assigned.
///   • [effectiveMaxQty] step 2 now reads [batchBalance].value instead of
///     the defunct maxQty.value RxDouble.
///   • [qtyInfoTooltip] batch line reads [batchBalance].value.
///   • [validateBatch] override calls base [fetchBatchBalance] +
///     [fetchRackBalance] after a successful batch confirmation, mirroring
///     the SE controller’s _updateBatchBalance flow.
///   • [validateSheet] gains the Commit-6 zero-stock guard:
///     `effMax == 0.0 && isBatchValid` → immediately invalid.
///   • Explicit [batchBalance] + [rackBalance] resets added to [initialise].
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
  // ── Parent reference ────────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  // ── ItemSheetControllerBase contract ────────────────────────────────────
  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override
  bool get requiresBatch => true;

  @override
  bool get requiresRack => false;

  @override
  bool get isSheetLoading => super.isSheetLoading;

  // ── DN-C: effectiveMaxQty ceiling chain ─────────────────────────────────
  //
  // Commit 7: step 2 reads batchBalance.value (base field populated by
  // fetchBatchBalance) instead of the defunct maxQty.value RxDouble.
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

    // 2. Batch balance (Commit 7: was maxQty.value)
    if (batchBalance.value > 0 && batchBalance.value < limit)
      limit = batchBalance.value;

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

  // ── DN-D: qtyInfoText — 'Max: N' / 'Max: -' (mirrors SE Commit C-2) ───────
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
  //
  // Commit 7: batch line reads batchBalance.value instead of maxQty.value.
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

    // Batch balance (Commit 7: was maxQty.value)
    if (batchBalance.value > 0) {
      final b = batchBalance.value;
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

  // ── deleteCurrentItem ─────────────────────────────────────────────────────────
  @override
  Future<void> deleteCurrentItem() async {
    final name = editingItemName.value;
    if (name == null) return;
    final item = _parent.deliveryNote.value?.items
        .firstWhereOrNull((i) => i.name == name);
    if (item != null) _parent.confirmAndDeleteItem(item);
  }

  // ── PosSerialMixin contract ────────────────────────────────────────────────
  @override
  List<String> get availableSerialNos =>
      _parent.posUpload.value?.items
          .map((i) => i.idx.toString())
          .toList() ??
      [];

  // ── Initialisation ───────────────────────────────────────────────────────
  //
  // Commit 7: removed `maxQty.value = initialMaxQty` — maxQty is a computed
  // getter in the base class and cannot be assigned. initialMaxQty parameter
  // also removed from the signature as it is no longer needed.
  // Explicit batchBalance + rackBalance resets added for clarity.
  void initialise({
    required DeliveryNoteFormController parent,
    required String code,
    required String name,
    String? batchNo,
    DeliveryNoteItem? editingItem,
    String scannedEan8 = '',
  }) {
    _parent = parent;
    currentScannedEan = scannedEan8;

    isAddingItemFlag    = _parent.isAddingItem;
    isScanning          = _parent.isScanning;
    sheetScanController = _parent.barcodeController;

    itemCode.value      = code;
    itemName.value      = name;
    // Commit 7: maxQty is a computed getter — no assignment needed.
    batchBalance.value  = 0.0;
    rackBalance.value   = 0.0;
    liveRemaining.value = 0.0;
    rackStockMap.clear();
    rackStockTooltip.value = null;
    rackError.value        = null;
    batchError.value       = null;
    batchInfoTooltip.value = null;
    isBatchValid.value     = false;
    isRackValid.value      = false;
    isBatchReadOnly.value  = false;

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

    if (editingItem != null) {
      // Pre-fetch balances for editing so the badge shows correct values.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await fetchBatchBalance(
          itemCode:  itemCode.value,
          batchNo:   batchController.text,
          warehouse: resolvedWarehouse,
        );
        if (isRackValid.value) {
          await fetchRackBalance(
            itemCode:  itemCode.value,
            batchNo:   batchController.text,
            rack:      rackController.text,
            warehouse: resolvedWarehouse,
          );
        }
      });
    }

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

  // ── applyRackScan ──────────────────────────────────────────────────────────
  void applyRackScan(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  // ── resetRack override ──────────────────────────────────────────────────────
  @override
  void resetRack() {
    super.resetRack();
  }

  // ── validateBatch (DN-specific override) ─────────────────────────────────
  //
  // Commit 7: after a successful batch confirmation, calls base
  // fetchBatchBalance() to populate batchBalance so effectiveMaxQty and
  // the qty badge reflect real stock immediately — mirroring SE’s
  // _updateBatchBalance flow.
  @override
  Future<void> validateBatch(String batch) async {
    batchError.value = null;
    if (batch.isEmpty) return;

    if (batch.contains('-')) {
      final parts = batch.split('-');
      if (parts.length >= 2 && parts[0] == parts[1]) {
        isBatchValid.value    = false;
        isBatchReadOnly.value = false;
        batchError.value      = 'Invalid Batch: Batch ID cannot match EAN';
        validateSheet();
        return;
      }
    }

    isValidatingBatch.value = true;
    try {
      final response = await apiProvider.getDocumentList(
        'Batch',
        filters: {'item': itemCode.value, 'name': batch},
        fields: ['name', 'custom_packaging_qty'],
      );
      if (response.statusCode == 200 &&
          response.data['data'] != null &&
          (response.data['data'] as List).isNotEmpty) {
        final batchData = response.data['data'][0];
        isBatchValid.value    = true;
        isBatchReadOnly.value = true;

        final double pkgQty =
            (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
        if (pkgQty > 0) {
          qtyController.text = pkgQty % 1 == 0
              ? pkgQty.toInt().toString()
              : pkgQty.toString();
        }

        // Commit 7: fetch real batch balance so effectiveMaxQty is accurate.
        await fetchBatchBalance(
          itemCode:  itemCode.value,
          batchNo:   batch,
          warehouse: resolvedWarehouse,
        );

        // Refresh rack balance if a rack is already confirmed.
        if (isRackValid.value && rackController.text.isNotEmpty) {
          await fetchRackBalance(
            itemCode:  itemCode.value,
            batchNo:   batch,
            rack:      rackController.text,
            warehouse: resolvedWarehouse,
          );
        }

        unawaited(fetchAllRackStocks());

        final enteredQty = double.tryParse(qtyController.text) ?? 0.0;
        if (batchBalance.value > 0 && enteredQty > batchBalance.value) {
          batchError.value =
              'Qty ($enteredQty) exceeds Batch balance '
              '(${batchBalance.value.toStringAsFixed(0)}) in warehouse';
        }
      } else {
        isBatchValid.value    = false;
        isBatchReadOnly.value = false;
        batchBalance.value    = 0.0;
        batchError.value      = 'Batch not found for this item';
      }
    } catch (e) {
      isBatchValid.value    = false;
      isBatchReadOnly.value = false;
      batchBalance.value    = 0.0;
      log('[DN:ItemSheet] validateBatch error: $e', name: 'DN:ItemSheet');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  // ── DN-B: _updateRackBalance ────────────────────────────────────────────────
  //
  // Derives rackBalance from the already-fetched rackStockMap (no extra
  // network call). Called at the top of every validateSheet().
  void _updateRackBalance() {
    final rack = rackController.text.trim();
    if (rack.isEmpty || !isRackValid.value) {
      rackBalance.value = 0.0;
      return;
    }
    rackBalance.value = rackStockMap[rack] ?? 0.0;
  }

  // ── validateSheet ──────────────────────────────────────────────────────────
  //
  // Commit 7: added Commit-6 zero-stock guard — when batch is confirmed
  // valid but effectiveMaxQty resolves to 0.0, no qty is acceptable.
  @override
  void validateSheet() {
    _updateRackBalance(); // DN-B

    bool valid = true;

    final qty    = double.tryParse(qtyController.text) ?? 0;
    final effMax = effectiveMaxQty;
    if (qty <= 0) valid = false;
    if (effMax == 0.0 && isBatchValid.value) {
      valid = false;
    } else if (effMax < 999999.0 && qty > effMax) {
      valid = false;
    }

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

  // ── submit ─────────────────────────────────────────────────────────────
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

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void onClose() {
    disposeAutoFillListener();
    super.onClose();
  }
}
