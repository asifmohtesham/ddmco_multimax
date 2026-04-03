import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';

/// Item-level sheet controller for Purchase Receipt.
///
/// PR differences from DN:
///  - No PosSerialMixin (no invoice serial number)
///  - No AutoFillRackMixin (incoming goods — operator specifies target rack)
///  - Rack is REQUIRED (isSheetValid stays false until rack validated)
///  - Batch validation accepts both existing AND new batches ("New Batch" flow)
///  - PO-linking state lives here (poItem, poName, poQty, poRate)
///  - EAN-equals-batch guard (custom PR rule)
///
class PurchaseReceiptItemFormController extends ItemSheetControllerBase {
  final PurchaseReceiptFormController _parent;
  PurchaseReceiptItemFormController(this._parent);

  // ── Parent-backed warehouse ─────────────────────────────────────────────
  // Warehouse derived from rack (overrides setWarehouse when present)
  final RxnString itemWarehouse = RxnString();

  @override
  String? get resolvedWarehouse =>
      itemWarehouse.value ?? _parent.setWarehouse.value;

  @override
  bool get requiresBatch => false; // PR allows new batches (not in system yet)

  @override
  bool get requiresRack => true;   // Target rack is mandatory for PR

  @override
  Color get accentColor => Colors.purple;

  // ── ItemSheetControllerBase abstract stubs ────────────────────────────

  @override
  void validateSheet() {
    // Recompute button visibility / state from shared fields.
    // PR-specific validity: qty > 0 and rack valid; batch can be existing OR new.
    final qty = double.tryParse(qtyController.text) ?? 0;
    final okQty = qty > 0;
    final okRack = isRackValid.value;
    saveButtonVisible.value = okQty && okRack;
  }

  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) {
      throw Exception('Enter a valid quantity');
    }
    if (!isRackValid.value) {
      throw Exception('Target rack is required');
    }

    final item = PurchaseReceiptItem(
      itemCode: itemCode.value,
      itemName: itemName.value,
      uom: itemUom.value,
      qty: qty,
      batchNo: batchController.text.trim().isEmpty ? null : batchController.text.trim(),
      rack: rackController.text.trim(),
      poName: poName.value,
      poItem: poItem.value,
      poQty: poQty.value,
      poRate: poRate.value,
    );

    if (editingIndex.value >= 0) {
      _parent.items[editingIndex.value] = item;
      _parent.items.refresh();
    } else {
      _parent.items.add(item);
    }
  }

  // ── Public reactive fields expected by shared widgets ──────────────────
  final RxString itemName = ''.obs;
  final RxString itemUom  = ''.obs;
  final RxInt    editingIndex = (-1).obs;

  // PO link metadata
  final RxnString poName = RxnString();
  final RxnString poItem = RxnString();
  final RxnDouble poQty  = RxnDouble();
  final RxnDouble poRate = RxnDouble();

  // Display helpers used by GlobalItemFormSheet
  String get currentVariantOf => '';
  String get qtyInfoText => '';
  String? get qtyInfoTooltip => null;

  // ── Init helpers ───────────────────────────────────────────────────────
  void initForCreate({
    required String code,
    required String name,
    required String uom,
    String? batchNo,
  }) {
    editingIndex.value = -1;
    itemCode.value = code;
    itemName.value = name;
    itemUom.value  = uom;

    batchController.text = batchNo ?? '';
    rackController.clear();
    qtyController.clear();
    itemWarehouse.value = null;

    poName.value = null;
    poItem.value = null;
    poQty.value  = null;
    poRate.value = null;

    resetBatch();
    resetRack();
    removeSheetListeners();
    addSheetListeners();
    validateSheet();
    snapshotState();
  }

  void initForEdit({
    required int index,
    required PurchaseReceiptItem item,
  }) {
    editingIndex.value = index;
    itemCode.value = item.itemCode;
    itemName.value = item.itemName;
    itemUom.value  = item.uom;

    batchController.text = item.batchNo ?? '';
    rackController.text  = item.rack ?? '';
    qtyController.text   = item.qty.toString();
    itemWarehouse.value  = item.warehouse;

    poName.value = item.poName;
    poItem.value = item.poItem;
    poQty.value  = item.poQty;
    poRate.value = item.poRate;

    resetBatch();
    removeSheetListeners();
    addSheetListeners();

    if ((item.batchNo ?? '').isNotEmpty) {
      validateBatchOnInit(item.batchNo!);
    }
    if ((item.rack ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateRack(item.rack!);
      });
    }

    validateSheet();
    snapshotState();
  }

  // ── PR-specific batch validation override ──────────────────────────────
  // Existing system batches remain valid via base lookup.
  // If not found, PR allows a new batch EXCEPT when batch == scanned EAN.
  @override
  Future<void> validateBatch(String batch) async {
    final trimmed = batch.trim();
    if (trimmed.isEmpty) {
      resetBatch();
      validateSheet();
      return;
    }

    isValidatingBatch.value = true;
    batchError.value = '';
    batchInfoTooltip.value = null;
    isBatchValid.value = false;

    try {
      // Try base/system validation first.
      final existing = await ApiProvider().getList(
        doctype: 'Batch',
        filters: {
          'name': trimmed,
          'item': itemCode.value,
        },
        fields: ['name', 'expiry_date', 'manufacturing_date'],
      );

      if (existing.isNotEmpty) {
        // Existing batch → use the shared happy path semantics.
        final row       = existing.first;
        final expiryRaw = row['expiry_date'] as String?;
        final mfgRaw    = row['manufacturing_date'] as String?;

        final parts = <String>[];
        if (mfgRaw != null && mfgRaw.isNotEmpty) parts.add('Mfg: $mfgRaw');
        if (expiryRaw != null && expiryRaw.isNotEmpty) parts.add('Exp: $expiryRaw');
        batchInfoTooltip.value = parts.isEmpty ? null : parts.join('  ·  ');

        isBatchValid.value = true;
        isBatchReadOnly.value = true;
        await fetchBatchBalance();
        validateSheet();
        return;
      }

      // New-batch branch allowed in PR.
      final scanned = _parent.lastScannedBarcode.value.trim();
      if (scanned.isNotEmpty && scanned == trimmed) {
        batchError.value = 'Batch cannot be identical to scanned EAN/barcode.';
        validateSheet();
        return;
      }

      isBatchValid.value = true;
      isBatchReadOnly.value = true;
      batchError.value = 'New Batch';
      batchInfoTooltip.value = 'This batch does not exist yet and will be created on submit.';
      batchBalance.value = 0.0;
      validateSheet();
    } catch (e) {
      log('[PR-Item] validateBatch error: $e', name: 'PR-Item');
      batchError.value = 'Validation error: $e';
      validateSheet();
    } finally {
      isValidatingBatch.value = false;
    }
  }

  // ── Rack validation override ────────────────────────────────────────────
  @override
  Future<void> validateRack(String rack) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty) {
      resetRack();
      validateSheet();
      return;
    }

    isValidatingRack.value = true;
    rackError.value = '';
    isRackValid.value = false;

    try {
      // PR target rack must exist in selected warehouse, but stock qty is not required.
      final rows = await ApiProvider().getStockBalanceWithDimension(
        itemCode: itemCode.value,
        warehouse: resolvedWarehouse,
        batchNo: null,
      );

      final exists = rows.any((r) =>
          (r['custom_rack'] ?? '').toString().trim().toLowerCase() ==
          trimmed.toLowerCase());

      if (!exists) {
        rackError.value = 'Rack not found in selected warehouse.';
        validateSheet();
        return;
      }

      rackBalance.value = 0.0; // informational only in PR
      isRackValid.value = true;
      validateSheet();
    } catch (e) {
      log('[PR-Item] validateRack error: $e', name: 'PR-Item');
      rackError.value = 'Rack validation error: $e';
      validateSheet();
    } finally {
      isValidatingRack.value = false;
    }
  }

  // ── Helpers used by form controller / widgets ──────────────────────────
  void applyRackScan(String rackId) {
    final id = rackId.trim();
    if (id.isEmpty) return;
    rackController.text = id;
    validateRack(id);
  }

  void clearAll() {
    batchController.clear();
    rackController.clear();
    qtyController.clear();
    itemWarehouse.value = null;
    poName.value = null;
    poItem.value = null;
    poQty.value  = null;
    poRate.value = null;
    resetBatch();
    resetRack();
    validateSheet();
  }

  void showError(String msg) => GlobalSnackbar.error(msg);
}
