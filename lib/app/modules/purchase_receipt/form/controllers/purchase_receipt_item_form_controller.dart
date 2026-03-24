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
/// Red Fix #1 (SRP — save ownership):
///  - submit() no longer calls savePurchaseReceipt() directly.
///  - The parent coordinator (_openItemSheet.onSubmit) owns saving.
///
/// Standardisation S2:
///  - isScanning is a proper Rx bind (not a value copy).
///
/// Standardisation S3:
///  - deleteCurrentItem uses firstWhereOrNull + silent early-return.
///
/// Standardisation S4:
///  - submit() delegates to parent.addItemLocally / updateItemLocally,
///    matching the SE/DN pattern.  All model-construction logic lives in
///    the parent form controller, not in the child item controller.
///
/// Standardisation S1 (base):
///  - isBatchReadOnly, currentScannedEan, validateBatchOnInit in base.
///
/// Sheet-close responsibility:
///  - submit() does NOT call Get.back().
///  - Sheet dismissal is owned exclusively by the parent coordinator
///    (_openItemSheet onSubmit lambda), matching the SRP boundary
///    established in Phase-1 (commit f2aeb9a).
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

  // ── S3: null-safe deleteCurrentItem ─────────────────────────────────────────
  @override
  Future<void> deleteCurrentItem() async {
    final name = editingItemName.value;
    if (name == null) return;
    final items = _parent.purchaseReceipt.value?.items ?? [];
    final item  = items.cast<PurchaseReceiptItem?>().firstWhere(
      (i) => i?.name == name,
      orElse: () => null,
    );
    if (item != null) _parent.confirmAndDeleteItem(item);
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
    currentScannedEan = scannedEan ?? ''; // S1: base field

    // S2: proper Rx bind so scan bar reacts live
    isAddingItemFlag    = _parent.isAddingItem;
    isScanning          = _parent.isScanning;
    sheetScanController = _parent.barcodeController;

    // Core identity
    itemCode.value  = code;
    itemName.value  = name;
    variantOf.value = variantOfValue ?? '';
    uom.value       = uomValue       ?? '';

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

    _parent.linkToPurchaseOrder(itemCode.value, this);
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

    itemWarehouse.value   = item.warehouse;
    isBatchValid.value    = item.batchNo != null && item.batchNo!.isNotEmpty;
    isBatchReadOnly.value = isBatchValid.value; // S1
    isRackValid.value     = item.rack != null && item.rack!.isNotEmpty;

    poItemId.value  = item.purchaseOrderItem ?? '';
    poDocName.value = item.purchaseOrder     ?? '';
    if (poItemId.value.isNotEmpty) {
      poQty.value = _parent.getOrderedQty(poItemId.value);
    }

    if (item.batchNo != null && item.batchNo!.contains('-')) {
      currentScannedEan = item.batchNo!.split('-').first; // S1
    }

    log('[PR:ItemSheet] loaded existing item=${item.name} batch=${item.batchNo} rack=${item.rack}',
        name: 'PR:ItemSheet');
  }

  void _loadNewItem(String? batchNo) {
    editingItemName.value = null;
    itemOwner.value = itemCreation.value = itemModified.value = itemModifiedBy.value = null;

    batchController.text = batchNo ?? '';
    rackController.clear();
    qtyController.clear();

    isBatchValid.value    = false;
    isBatchReadOnly.value = false; // S1
    isRackValid.value     = false;

    if (batchNo != null && batchNo.isNotEmpty) {
      validateBatchOnInit(batchNo); // S1: base method
    }

    log('[PR:ItemSheet] new item code=${itemCode.value} batch=$batchNo',
        name: 'PR:ItemSheet');
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

    if (batch.contains('-')) {
      final parts = batch.split('-');
      if (parts.length >= 2 && parts[0] == parts[1]) {
        batchError.value        = 'Invalid Batch: Batch ID cannot match EAN';
        isBatchValid.value      = false;
        isBatchReadOnly.value   = false;
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
        batchInfoTooltip.value = pkgQty > 0 ? 'Packaging Qty: \$pkgQty' : null;
        GlobalSnackbar.success(message: 'Existing Batch found');
      } else {
        GlobalSnackbar.info(message: 'New Batch will be created');
      }

      isBatchValid.value    = true;
      isBatchReadOnly.value = true;
      batchError.value      = null;
    } catch (e) {
      isBatchValid.value    = false;
      isBatchReadOnly.value = false;
      batchError.value      = 'Error validating batch';
      GlobalSnackbar.error(message: 'Error validating batch');
      log('[PR:ItemSheet] validateBatch error: \$e', name: 'PR:ItemSheet');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  // ── Rack validation override ────────────────────────────────────────────

  @override
  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) {
      isRackValid.value = false;
      validateSheet();
      return;
    }
    isValidatingRack.value = true;

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

  void applyRackScan(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  @override
  void resetRack() {
    isRackValid.value   = false;
    itemWarehouse.value = null;
    rackError.value     = null;
    validateSheet();
  }

  // ── S4: submit — delegates to parent only (sheet close owned by parent coordinator)

  @override
  Future<void> submit() async {
    final qty      = double.tryParse(qtyController.text) ?? 0;
    final batch    = batchController.text;
    final rack     = rackController.text;
    final warehouse = itemWarehouse.value ?? _parent.setWarehouse.value ?? '';

    if (editingItemName.value != null && editingItemName.value!.isNotEmpty) {
      _parent.updateItemLocally(
        editingItemName.value!, qty, batch, rack, warehouse);
    } else {
      _parent.addItemLocally(
        itemCode.value, itemName.value, qty, batch, rack, warehouse,
        uom: uom.value,
        variantOf: variantOf.value,
        poItemId:  poItemId.value,
        poDocName: poDocName.value,
        poQty:     poQty.value,
        poRate:    poRate.value,
      );
    }
  }
}
