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
///
/// Commit 6 (QtyFieldWithPlusMinusDelegate wiring):
///  • effectiveMaxQty overrides base: poQty.value when positive, else
///    double.infinity (PO-qty is the only ceiling for inbound receipts;
///    batch/rack balances are irrelevant for incoming stock).
///  • adjustQty clamps to effectiveMaxQty (was double.infinity).
///  • validateSheet additionally enforces qty <= poQty ceiling in the
///    validity gate, and writes isQtyValid.value / qtyError.value so
///    SharedQtyField can show an inline error beneath the qty field.
///  • docStatus seeded in initForEdit / reset in initForCreate so the
///    ever() worker in ItemSheetControllerBase.onInit locks isQtyReadOnly
///    when docstatus == 1 (submitted).
class PurchaseReceiptItemFormController extends ItemSheetControllerBase {

  // ── Parent back-reference ───────────────────────────────────────────────
  late PurchaseReceiptFormController _parent;

  PurchaseReceiptFormController get parent => _parent;

  // ── In-sheet scan context ──────────────────────────────────────────────
  String currentScannedEan = '';

  // ── Parent-backed warehouse ───────────────────────────────────────────
  final RxnString itemWarehouse = RxnString();

  @override
  String? get resolvedWarehouse =>
      itemWarehouse.value ?? _parent.setWarehouse.value;

  // ── Abstract overrides ───────────────────────────────────────────────
  @override bool get requiresBatch => false;
  @override bool get requiresRack  => true;
  @override Color get accentColor  => Colors.purple;

  @override
  bool get isAddMode => editingItemName.value == null;

  @override
  MobileScannerController? get sheetScanController => null;

  // ── QtyFieldWithPlusMinusDelegate: effectiveMaxQty (Commit 6) ────────
  /// Effective qty ceiling for PR: the PO ordered qty when positive.
  ///
  /// PO qty is the only meaningful ceiling for inbound receipts — batch
  /// and rack balances are zero for goods not yet received.
  ///
  /// Returns [double.infinity] when no PO is linked or its qty is zero
  /// (uncapped entry).
  ///
  /// Overrides [ItemSheetControllerBase.effectiveMaxQty].
  @override
  double get effectiveMaxQty {
    final po = poQty.value;
    if (po != null && po > 0) return po;
    return double.infinity;
  }

  /// Qty-info label: shows max from PO ordered qty when available.
  @override
  String? get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff == double.infinity) return null;
    return 'PO Qty: ${eff.toStringAsFixed(eff.truncateToDouble() == eff ? 0 : 2)}';
  }

  /// Backing RxnString for the qty-info tooltip (ceiling breakdown).
  @override
  final RxnString qtyInfoTooltip = RxnString(null);

  // ── PO link metadata ─────────────────────────────────────────────────────
  final RxString  poItemId  = ''.obs;
  final RxString  poDocName = ''.obs;
  final RxnDouble poQty     = RxnDouble();
  final RxnDouble poRate    = RxnDouble();

  // ── Additional reactive fields ───────────────────────────────────────────
  final RxString itemUom = ''.obs;

  // ── initialise() entry point ───────────────────────────────────────────
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

    _parent.linkToPurchaseOrder(code, this);
  }

  // ── validateSheet ───────────────────────────────────────────────────────────
  @override
  void validateSheet() {
    final qty  = double.tryParse(qtyController.text) ?? 0.0;
    final ceil = effectiveMaxQty;
    final qtyOk  = qty > 0;
    final ceilOk = ceil == double.infinity || qty <= ceil;

    // ── isQtyValid / qtyError (Commit 6) ─────────────────────────────
    if (!qtyOk) {
      isQtyValid.value = false;
      qtyError.value   = qty == 0.0 ? '' : 'Enter a quantity greater than 0';
    } else if (!ceilOk) {
      isQtyValid.value = false;
      final ceilStr = ceil.toStringAsFixed(
          ceil.truncateToDouble() == ceil ? 0 : 2);
      qtyError.value = 'Qty cannot exceed PO qty of $ceilStr';
    } else {
      isQtyValid.value = true;
      qtyError.value   = '';
    }

    final ok = qtyOk && ceilOk && isRackValid.value;
    isSheetValid.value      = ok;
    saveButtonVisible.value = ok;

    // Update qty-info tooltip with PO qty ceiling.
    final po = poQty.value;
    qtyInfoTooltip.value = (po != null && po > 0)
        ? 'Ordered: ${po.toStringAsFixed(0)}'
        : null;
  }

  // ── adjustQty ──────────────────────────────────────────────────────────────
  /// Increments or decrements qty by [delta], clamped to
  /// [0.0, effectiveMaxQty] (Commit 6: was clamped to double.infinity).
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, effectiveMaxQty);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem ─────────────────────────────────────────────────────
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
    // Commit 6: reset docStatus → unlocks isQtyReadOnly via ever() worker.
    docStatus.value       = 0;
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
    isQtyValid.value = false;
    qtyError.value   = '';
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
    // Commit 6: seed docStatus so the ever() worker locks isQtyReadOnly
    // when the item is submitted (docstatus == 1).
    docStatus.value       = item.docstatus ?? 0;
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
    isQtyValid.value = false;
    qtyError.value   = '';
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

      rackBalance.value = 0.0;
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

  void showError(String msg) => GlobalSnackbar.error(message: msg);
}
