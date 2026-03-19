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
/// Phase 2 changes:
///  - Step 2.1: ApiProvider access via typed field (no more untyped getter)
///  - Step 2.3: validateRack no longer emits a success snackbar (silent on
///    success, matching SE/DN behaviour)
///
/// Red Fix #1 (SRP — save ownership):
///  - submit() no longer calls savePurchaseReceipt() directly.
///  - submit() is a pure in-memory mutator: updates PurchaseReceipt.items
///    and sets _parent.isDirty = true.
///  - The parent coordinator (_openItemSheet.onSubmit) is responsible for
///    calling savePurchaseReceipt() after child.submit() completes.
///
/// Red Fix #2 (isAddingItemFlag):
///  - isAddingItemFlag now wired to _parent.isAddingItem (sheet-level flag),
///    NOT _parent.isSaving (document-level flag).
///  - isSheetLoading reflects sheet-specific work only, keeping the Save
///    button spinner semantically correct.
class PurchaseReceiptItemFormController extends ItemSheetControllerBase {
  // ── Step 2.1: typed ApiProvider ─────────────────────────────────────────────
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── Parent reference ──────────────────────────────────────────────────────────
  late PurchaseReceiptFormController _parent;

  // ── PR-specific state ─────────────────────────────────────────────────────────

  // PO linking
  var poItemId  = ''.obs;
  var poDocName = ''.obs;
  var poQty     = 0.0.obs;
  var poRate    = 0.0.obs;

  // Batch read-only toggle
  var isBatchReadOnly = false.obs;

  // EAN context for inside-sheet scan routing
  String currentScannedEan = '';

  // Variant / UOM metadata
  var variantOf = ''.obs;
  var uom       = ''.obs;

  // Warehouse derived from rack (overrides setWarehouse when present)
  var itemWarehouse = RxnString();

  // ── ItemSheetControllerBase contract ────────────────────────────────────────────

  @override
  String? get resolvedWarehouse =>
      itemWarehouse.value ?? _parent.setWarehouse.value;

  @override
  bool get requiresBatch => false; // PR allows new batches (not in system yet)

  @override
  bool get requiresRack => true;   // Target rack is mandatory for PR

  // ── ItemSheetControllerBase abstract stubs ──────────────────────────────────

  @override
  String? get qtyInfoText {
    if (poQty.value > 0) {
      return 'PO Qty: ${poQty.value % 1 == 0 ? poQty.value.toInt() : poQty.value}';
    }
    return null;
  }

  @override
  Future<void> deleteCurrentItem() async {
    if (editingItemName.value == null) return;
    final items = _parent.purchaseReceipt.value?.items ?? [];
    final item = items.firstWhere(
      (i) => i.name == editingItemName.value,
      orElse: () => throw StateError('Item not found'),
    );
    _parent.confirmAndDeleteItem(item);
  }

  // ── Initialisation ─────────────────────────────────────────────────────────────

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

    // ── Red Fix #2: wire isAddingItemFlag to sheet-level flag ────────────────
    // _parent.isAddingItem is the dedicated sheet spinner flag.
    // _parent.isSaving drives the AppBar SaveIconButton — separate concerns.
    isAddingItemFlag    = _parent.isAddingItem;
    isScanning.value    = _parent.isScanning.value;
    sheetScanController = _parent.barcodeController;

    // Core identity
    itemCode.value  = code;
    itemName.value  = name;
    variantOf.value = variantOfValue ?? '';
    uom.value       = uomValue       ?? '';

    // isAddMode (base field)
    isAddMode = editingItem == null;

    // Reset base state
    maxQty.value           = 0.0;
    rackStockMap.clear();
    rackStockTooltip.value = null;
    rackError.value        = null;
    batchError.value       = null;
    batchInfoTooltip.value = null;
    itemWarehouse.value    = null;

    // Reset PR-specific
    poItemId.value  = '';
    poDocName.value = '';
    poQty.value     = 0.0;
    poRate.value    = 0.0;

    if (editingItem != null) {
      _loadExistingItem(editingItem);
    } else {
      _loadNewItem(batchNo);
    }

    // Link to PO
    _parent.linkToPurchaseOrder(itemCode.value, this);

    // Base listeners
    initBaseListeners();
    captureSnapshot();

    validateSheet();
  }

  void _loadExistingItem(PurchaseReceiptItem item) {
    editingItemName.value = item.name;

    itemOwner.value      = item.owner;
    itemCreation.value   = item.creation;
    itemModified.value   = item.modified;
    itemModifiedBy.value = item.modifiedBy;

    batchController.text = item.batchNo ?? '';
    rackController.text  = item.rack    ?? '';
    qtyController.text   = item.qty.toString();

    itemWarehouse.value  = item.warehouse;

    isBatchValid.value    = item.batchNo != null && item.batchNo!.isNotEmpty;
    isBatchReadOnly.value = isBatchValid.value;
    isRackValid.value     = item.rack != null && item.rack!.isNotEmpty;

    poItemId.value  = item.purchaseOrderItem ?? '';
    poDocName.value = item.purchaseOrder     ?? '';
    if (poItemId.value.isNotEmpty) {
      poQty.value = _parent.getOrderedQty(poItemId.value);
    }

    if (item.batchNo != null && item.batchNo!.contains('-')) {
      currentScannedEan = item.batchNo!.split('-').first;
    }

    log('[PR:ItemSheet] loaded existing item=${item.name} batch=${item.batchNo} rack=${item.rack}',
        name: 'PR:ItemSheet');
  }

  // ── Step 5.2: _loadNewItem + validateBatchOnInit ──────────────────────────────

  void _loadNewItem(String? batchNo) {
    editingItemName.value = null;

    itemOwner.value      = null;
    itemCreation.value   = null;
    itemModified.value   = null;
    itemModifiedBy.value = null;

    batchController.text = batchNo ?? '';
    rackController.clear();
    qtyController.clear();

    isBatchValid.value    = false;
    isBatchReadOnly.value = false;
    isRackValid.value     = false;

    if (batchNo != null && batchNo.isNotEmpty) {
      validateBatchOnInit(batchNo);
    }

    log('[PR:ItemSheet] new item code=${itemCode.value} batch=$batchNo',
        name: 'PR:ItemSheet');
  }

  void validateBatchOnInit(String batch) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => validateBatch(batch));
  }

  // ── validateSheet ──────────────────────────────────────────────────────────────

  @override
  void validateSheet() {
    final qty = double.tryParse(qtyController.text) ?? 0;
    bool valid = qty > 0;

    if (batchController.text.isNotEmpty && !isBatchValid.value) valid = false;
    if (rackController.text.isEmpty || !isRackValid.value) valid = false;

    isFormDirty.value = isFieldsDirty;
    if (editingItemName.value != null && !isFormDirty.value) valid = false;

    isSheetValid.value = valid;
  }

  // ── PR batch validation override ──────────────────────────────────────────────

  @override
  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) return;
    batchError.value        = null;
    isValidatingBatch.value = true;

    // PR-specific guard: batch ID must not equal EAN-8
    if (batch.contains('-')) {
      final parts = batch.split('-');
      if (parts.length >= 2 && parts[0] == parts[1]) {
        batchError.value        = 'Invalid Batch: Batch ID cannot match EAN';
        isBatchValid.value      = false;
        isValidatingBatch.value = false;
        validateSheet();
        return;
      }
    }

    try {
      final response = await _apiProvider.getDocumentList(
        'Batch',
        filters: {'item': itemCode.value, 'name': batch},
        fields: ['name', 'custom_packaging_qty'],
      );

      final batchList = response.data['data'] as List? ?? [];
      if (batchList.isNotEmpty) {
        final batchData = batchList.first as Map<String, dynamic>;
        final double pkgQty =
            (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
        if (pkgQty > 0 && qtyController.text.isEmpty) {
          qtyController.text = pkgQty % 1 == 0
              ? pkgQty.toInt().toString()
              : pkgQty.toString();
        }
        batchInfoTooltip.value =
            pkgQty > 0 ? 'Packaging Qty: $pkgQty' : null;
        GlobalSnackbar.success(message: 'Existing Batch found');
      } else {
        // Batch not in system — allowed for PR (new batch creation)
        GlobalSnackbar.info(message: 'New Batch will be created');
      }

      isBatchValid.value    = true;
      isBatchReadOnly.value = true;
      batchError.value      = null;
    } catch (e) {
      isBatchValid.value = false;
      batchError.value   = 'Error validating batch';
      GlobalSnackbar.error(message: 'Error validating batch');
      log('[PR:ItemSheet] validateBatch error: $e', name: 'PR:ItemSheet');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  // ── Rack validation override ────────────────────────────────────────────────

  @override
  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) {
      isRackValid.value = false;
      validateSheet();
      return;
    }
    isValidatingRack.value = true;

    // Derive warehouse from rack code: ZONE-WH-NUM → WH-NUM - ZONE
    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        itemWarehouse.value = '${parts[1]}-${parts[2]} - ${parts[0]}';
      }
    }

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        isRackValid.value = true;
        validateSheet();
      } else {
        isRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      isRackValid.value = false;
      GlobalSnackbar.error(message: 'Rack validation failed');
    } finally {
      isValidatingRack.value = false;
      validateSheet();
    }
  }

  /// Delegate applyRackScan to the rack controller (mirrors SE/DN pattern).
  /// Called by parent's _handleSheetScan when a rack barcode is scanned
  /// inside the sheet — keeps parent ignorant of internal TEC details.
  void applyRackScan(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  void resetBatch() {
    isBatchValid.value    = false;
    isBatchReadOnly.value = false;
    batchError.value      = null;
    validateSheet();
  }

  void resetRack() {
    isRackValid.value   = false;
    itemWarehouse.value = null;
    validateSheet();
  }

  // ── submit ──────────────────────────────────────────────────────────────────────────
  //
  // Red Fix #1: submit() is now a PURE IN-MEMORY MUTATOR.
  //   - Updates PurchaseReceipt.items
  //   - Sets _parent.isDirty = true
  //   - Calls _parent.triggerHighlight
  //   - Does NOT call savePurchaseReceipt()
  //
  // The parent coordinator (_openItemSheet.onSubmit) calls savePurchaseReceipt()
  // after this method returns, maintaining the SE/DN responsibility boundary.

  @override
  Future<void> submit() async {
    if (!_parent.isEditable) return;

    final double qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return;

    final batch          = batchController.text;
    final rack           = rackController.text;
    final finalWarehouse = itemWarehouse.value ?? _parent.setWarehouse.value ?? '';
    final uniqueId       = editingItemName.value
        ?? 'local_${DateTime.now().millisecondsSinceEpoch}';

    final currentItems = _parent.purchaseReceipt.value?.items.toList() ?? [];
    final editIndex    = currentItems.indexWhere((i) => i.name == uniqueId);

    if (editIndex != -1) {
      final existing = currentItems[editIndex];
      currentItems[editIndex] = existing.copyWith(
        qty:       qty,
        batchNo:   batch,
        rack:      rack,
        warehouse: finalWarehouse.isNotEmpty ? finalWarehouse : existing.warehouse,
      );
    } else {
      final dupIdx = currentItems.indexWhere((i) =>
          i.itemCode == itemCode.value &&
          (i.batchNo  ?? '') == batch &&
          (i.rack     ?? '') == rack &&
          i.warehouse == finalWarehouse);

      if (dupIdx != -1) {
        final existing = currentItems[dupIdx];
        currentItems[dupIdx] = existing.copyWith(qty: existing.qty + qty);
        editingItemName.value = existing.name;
      } else {
        currentItems.add(PurchaseReceiptItem(
          name:              uniqueId,
          owner:             '',
          creation:          DateTime.now().toString(),
          itemCode:          itemCode.value,
          qty:               qty,
          itemName:          itemName.value,
          batchNo:           batch.isNotEmpty ? batch : null,
          rack:              rack.isNotEmpty  ? rack  : null,
          warehouse:         finalWarehouse,
          uom:               uom.value,
          stockUom:          uom.value,
          customVariantOf:   variantOf.value,
          purchaseOrderItem: poItemId.value.isNotEmpty  ? poItemId.value  : null,
          purchaseOrder:     poDocName.value.isNotEmpty ? poDocName.value : null,
          purchaseOrderQty:  poQty.value > 0            ? poQty.value     : null,
          rate:              poRate.value,
          idx:               currentItems.length + 1,
        ));
      }
    }

    // Rebuild receipt with updated items
    final old = _parent.purchaseReceipt.value!;
    _parent.purchaseReceipt.value = PurchaseReceipt(
      name:         old.name,
      postingDate:  old.postingDate,
      modified:     old.modified,
      creation:     old.creation,
      status:       old.status,
      docstatus:    old.docstatus,
      owner:        old.owner,
      postingTime:  old.postingTime,
      setWarehouse: old.setWarehouse,
      supplier:     old.supplier,
      currency:     old.currency,
      totalQty:     old.totalQty,
      grandTotal:   old.grandTotal,
      items:        currentItems,
    );

    _parent.triggerHighlight(editingItemName.value ?? uniqueId);
    _parent.isDirty.value = true;
    // NOTE: savePurchaseReceipt() is NOT called here.
    // The parent coordinator is responsible for persistence.
  }
}
