import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';

/// Item-level sheet controller for Purchase Receipt.
///
/// PR differences from SE / DN:
///  - No PosSerialMixin (no invoice serial number)
///  - No AutoFillRackMixin (incoming goods — operator specifies target rack)
///  - Rack is REQUIRED (isSheetValid stays false until rack validated)
///  - Batch validation accepts both existing AND new batches ("New Batch" flow)
///  - PO-linking state lives here (poItemId, poDocName, poQty, poRate)
///  - EAN-equals-batch guard (custom PR rule)
///
/// Commit 6:
///  • No-arg constructor; parent wired via initialise().
///  • Abstract members implemented: isAddMode, sheetScanController,
///    qtyInfoTooltip (RxnString), adjustQty(), deleteCurrentItem().
///  • PO field names: poItemId / poDocName to match
///    PurchaseReceiptFormController.linkToPurchaseOrder().
///  • currentScannedEan field added (parent reads child.currentScannedEan).
///  • lastScannedBarcode → _parent.currentScannedEan.
///  • setupAutoSubmit call uses base signature {required onValid:}.
///  • GlobalSnackbar.error positional → named message:.
///  • validateSheet writes both isSheetValid and saveButtonVisible.
class PurchaseReceiptItemFormController extends ItemSheetControllerBase {

  // ── Parent back-reference ───────────────────────────────────────────────
  // No-arg constructor so Get.put(PurchaseReceiptItemFormController()) compiles.
  // Parent is wired lazily via initialise().
  late PurchaseReceiptFormController _parent;

  PurchaseReceiptFormController get parent => _parent;

  // ── In-sheet scan context ──────────────────────────────────────────────
  /// EAN-8 / barcode that triggered this sheet open.
  /// Forwarded from [PurchaseReceiptFormController.currentScannedEan].
  String currentScannedEan = '';

  // ── Parent-backed warehouse ───────────────────────────────────────────
  final RxnString itemWarehouse = RxnString();

  @override
  String? get resolvedWarehouse =>
      itemWarehouse.value ?? _parent.setWarehouse.value;

  // ── Abstract overrides ───────────────────────────────────────────────
  @override bool get requiresBatch => false; // PR allows new batches
  @override bool get requiresRack  => true;  // Target rack mandatory
  @override Color get accentColor  => Colors.purple;

  /// True when the sheet was opened for a new item (not editing).
  @override
  bool get isAddMode => editingItemName.value == null;

  /// PR does not embed an in-sheet camera scanner; returns null.
  @override
  MobileScannerController? get sheetScanController => null;

  /// Qty-info label: shows max from PO ordered qty when available.
  @override
  String get qtyInfoText {
    final po = poQty.value;
    if (po != null && po > 0) {
      return 'PO Qty: ${po.toStringAsFixed(po.truncateToDouble() == po ? 0 : 2)}';
    }
    return '';
  }

  /// Backing RxnString for the qty-info tooltip (ceiling breakdown).
  @override
  final RxnString qtyInfoTooltip = RxnString(null);

  // ── PO link metadata ─────────────────────────────────────────────────────
  // Commit 6: renamed from poItem/poName → poItemId/poDocName to match
  // PurchaseReceiptFormController.linkToPurchaseOrder() write path.
  final RxString  poItemId  = ''.obs;
  final RxString  poDocName = ''.obs;
  final RxnDouble poQty     = RxnDouble();
  final RxnDouble poRate    = RxnDouble();

  // ── Additional reactive fields ───────────────────────────────────────────
  final RxString itemUom = ''.obs;

  // ── initialise() entry point ───────────────────────────────────────────
  /// Called by [PurchaseReceiptFormController._openItemSheet] immediately after
  /// [Get.put]; wires the parent reference and delegates to initForCreate /
  /// initForEdit.
  void initialise({
    required PurchaseReceiptFormController parent,
    required String code,
    required String name,
    String?  batchNo,
    String?  scannedEan,
    String?  variantOfValue,
    String?  uomValue,
    PurchaseReceiptItem? editingItem,
  }) {
    _parent = parent;
    currentScannedEan = scannedEan ?? '';

    if (editingItem != null) {
      // Find index of this item in the parent list.
      final items  = parent.purchaseReceipt.value?.items ?? [];
      final idx    = items.indexWhere((i) => i.name == editingItem.name);
      initForEdit(index: idx >= 0 ? idx : 0, item: editingItem);
    } else {
      initForCreate(
        code:   code,
        name:   name,
        uom:    uomValue ?? 'Nos',
        batchNo: batchNo,
      );
    }

    // Wire PO link if available.
    _parent.linkToPurchaseOrder(code, this);
  }

  // ── validateSheet ───────────────────────────────────────────────────────────
  @override
  void validateSheet() {
    final qty  = double.tryParse(qtyController.text) ?? 0;
    final ok   = qty > 0 && isRackValid.value;
    isSheetValid.value    = ok;
    saveButtonVisible.value = ok;

    // Update qty-info tooltip with PO qty ceiling.
    final po = poQty.value;
    qtyInfoTooltip.value = (po != null && po > 0)
        ? 'Ordered: ${po.toStringAsFixed(0)}'  
        : null;
  }

  // ── adjustQty (abstract impl) ───────────────────────────────────────────────
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, double.infinity);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem (abstract impl) ─────────────────────────────────────────
  @override
  void deleteCurrentItem() {
    final rowId = editingItemName.value;
    if (rowId == null) return;
    final items = _parent.purchaseReceipt.value?.items ?? [];
    final item  = items.cast<PurchaseReceiptItem?>().firstWhere(
      (i) => i?.name == rowId, orElse: () => null,
    );
    if (item == null) return;
    _parent.confirmAndDeleteItem(item);
  }

  // ── submit ────────────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) throw Exception('Enter a valid quantity');
    if (!isRackValid.value) throw Exception('Target rack is required');

    final batch     = batchController.text.trim();
    final rack      = rackController.text.trim();
    final warehouse = itemWarehouse.value ?? _parent.setWarehouse.value ?? '';

    final rowId = editingItemName.value;
    if (rowId != null) {
      _parent.updateItemLocally(
        rowId,
        qty,
        batch,
        rack,
        warehouse,
      );
    } else {
      _parent.addItemLocally(
        itemCode.value,
        itemName.value,
        qty,
        batch,
        rack,
        warehouse,
        uom:       itemUom.value,
        poItemId:  poItemId.value,
        poDocName: poDocName.value,
        poQty:     poQty.value   ?? 0.0,
        poRate:    poRate.value  ?? 0.0,
      );
    }
  }

  // ── Init helpers ──────────────────────────────────────────────────────────────
  void initForCreate({
    required String code,
    required String name,
    required String uom,
    String? batchNo,
  }) {
    editingItemName.value = null;
    itemCode.value        = code;
    itemName.value        = name;
    itemUom.value         = uom;

    batchController.text = batchNo ?? '';
    rackController.clear();
    qtyController.clear();
    itemWarehouse.value  = null;

    poItemId.value  = '';
    poDocName.value = '';
    poQty.value     = null;
    poRate.value    = null;

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
    editingItemName.value = item.name;
    itemCode.value        = item.itemCode;
    itemName.value        = item.itemName ?? '';
    itemUom.value         = item.uom ?? '';

    batchController.text = item.batchNo ?? '';
    rackController.text  = item.rack    ?? '';
    qtyController.text   = item.qty.toString();
    itemWarehouse.value  = item.warehouse;

    poItemId.value  = item.purchaseOrderItem ?? '';
    poDocName.value = item.purchaseOrder     ?? '';
    poQty.value     = item.purchaseOrderQty;
    poRate.value    = item.rate != null && item.rate! > 0 ? item.rate : null;

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

  // ── PR-specific batch validation override ───────────────────────────────────
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
    batchError.value        = '';
    batchInfoTooltip.value  = null;
    isBatchValid.value      = false;

    try {
      final existing = await ApiProvider().getList(
        'Batch',
        filters: {
          'name': trimmed,
          'item': itemCode.value,
        },
        fields: ['name', 'expiry_date', 'manufacturing_date'],
      );

      if (existing.isNotEmpty) {
        final row       = existing.first;
        final expiryRaw = row['expiry_date'] as String?;
        final mfgRaw    = row['manufacturing_date'] as String?;

        final parts = <String>[];
        if (mfgRaw    != null && mfgRaw.isNotEmpty)    parts.add('Mfg: $mfgRaw');
        if (expiryRaw != null && expiryRaw.isNotEmpty) parts.add('Exp: $expiryRaw');
        batchInfoTooltip.value = parts.isEmpty ? null : parts.join('  ·  ');

        isBatchValid.value    = true;
        isBatchReadOnly.value = true;
        await fetchBatchBalance();
        validateSheet();
        return;
      }

      // New-batch branch: disallow when batch text == the scanned EAN.
      // Commit 6: fixed from _parent.lastScannedBarcode.value
      //           to     _parent.currentScannedEan.
      final scanned = _parent.currentScannedEan.trim();
      if (scanned.isNotEmpty && scanned == trimmed) {
        batchError.value = 'Batch cannot be identical to scanned EAN/barcode.';
        validateSheet();
        return;
      }

      isBatchValid.value     = true;
      isBatchReadOnly.value  = true;
      batchError.value       = 'New Batch';
      batchInfoTooltip.value =
          'This batch does not exist yet and will be created on submit.';
      batchBalance.value     = 0.0;
      validateSheet();
    } catch (e) {
      log('[PR-Item] validateBatch error: $e', name: 'PR-Item');
      batchError.value = 'Validation error: $e';
      validateSheet();
    } finally {
      isValidatingBatch.value = false;
    }
  }

  // ── Rack validation override ──────────────────────────────────────────────────
  @override
  Future<void> validateRack(String rack) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty) {
      resetRack();
      validateSheet();
      return;
    }

    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;

    try {
      // PR target rack must exist in selected warehouse; stock qty not required.
      final rows = await ApiProvider().getStockBalanceWithDimension(
        itemCode:  itemCode.value,
        warehouse: resolvedWarehouse,
        batchNo:   null,
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

  // ── Helpers ────────────────────────────────────────────────────────────────────
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
    poItemId.value  = '';
    poDocName.value = '';
    poQty.value     = null;
    poRate.value    = null;
    resetBatch();
    resetRack();
    validateSheet();
  }

  // Commit 6: named message: param.
  void showError(String msg) => GlobalSnackbar.error(message: msg);
}
