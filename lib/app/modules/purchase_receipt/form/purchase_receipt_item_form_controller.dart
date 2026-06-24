import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/barcode_listener_mixin.dart';
import 'package:multimax/app/shared/item_sheet/barcode_aware_mixin.dart';
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';

/// Item-level sheet controller for Purchase Receipt.
///
/// PR differences from SE / DN:
///  - No PosSerialMixin (no invoice serial number)
///  - No AutoFillRackMixin (incoming goods — operator specifies target rack)
///  - Rack is REQUIRED (isSheetValid stays false until rack validated)
///  - Batch validation accepts both existing AND new batches ("New Batch" flow)
///  - PO-linking state lives here (poItemId, poDocName, poQty, poRate)
///  • EAN-equals-batch guard (custom PR rule)
///
/// Commit (warehouse-from-rack fix):
///  • validateRack now fetches the 'warehouse' field from the Rack doctype
///    and writes it to itemWarehouse, matching SE / DN behaviour.
///  • handleRackPicked applies result.warehouse before the validateRack
///    round-trip so resolvedWarehouse is immediately correct.
///  • applyRackScan clears itemWarehouse before re-validation to prevent
///    stale warehouse from a previous scan being read during the async gap.
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
///
/// fix(docstatus): read from parent document, not item row.
///   PurchaseReceiptItem does not carry a docstatus field — docstatus belongs
///   to the parent PurchaseReceipt only.  Both initForCreate and initForEdit
///   now read _parent.purchaseReceipt.value?.docstatus ?? 0.
class PurchaseReceiptItemFormController extends ItemSheetControllerBase
    with BarcodeListenerMixin, BarcodeAwareMixin {

  // ── Parent back-reference ───────────────────────────────────────────────
  late PurchaseReceiptFormController _parent;

  PurchaseReceiptFormController get parent => _parent;

  // ── In-sheet scan context ──────────────────────────────────────────────
  String currentScannedEan = '';

  // ── BarcodeAwareMixin: handleScan with rack-first gate ────────────────────
  /// Routing priority (mirrors DeliveryNoteItemFormController.handleScan):
  ///   1. Rack barcode    → applyRackScan
  ///   2. Current EAN-8 format ("{EAN}-{BatchID}") → raw is the full Batch No
  ///   3. Deprecated SHIPMENT-* / plain Batch ID   → prepend currentScannedEan
  @override
  Future<void> handleScan(String raw) async {
    final firstToken = raw.split('-').first;
    final isEan8     = firstToken.length == 8 && int.tryParse(firstToken) != null;
    final isShipment = firstToken.toUpperCase() == 'SHIPMENT';

    if (!isEan8 && !isShipment && raw.contains('-')) {
      applyRackScan(raw);
      return;
    }

    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);

    if (ean.isNotEmpty) {
      batchController.text = raw;
      await validateBatch(raw);
      return;
    }

    final extractedId = _extractBatchId(raw);
    final fullBatchNo = currentScannedEan.isNotEmpty
        ? '$currentScannedEan-$extractedId'
        : extractedId;

    if (currentScannedEan == extractedId) return;

    batchController.text = fullBatchNo;
    await validateBatch(fullBatchNo);
  }

  /// Splits [raw] on '-', discards 'SHIPMENT' (any case) and tokens < 3 chars.
  /// Returns the first surviving token, or [raw] unchanged when none survive.
  String _extractBatchId(String raw) {
    final candidates = raw
        .split('-')
        .where((p) => p.toUpperCase() != 'SHIPMENT' && p.length >= 3)
        .toList();
    return candidates.isNotEmpty ? candidates.first : raw;
  }

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

  // ── QtyFieldWithPlusMinusDelegate: effectiveMaxQty (Commit 6) ────────
  @override
  double get effectiveMaxQty =>
      poQtyCeiling(poQty.value, allowOverReceipt: allowOverReceipt.value);

  @override
  String? get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff == double.infinity) return null;
    return 'PO Qty: ${eff.toStringAsFixed(eff.truncateToDouble() == eff ? 0 : 2)}';
  }

  @override
  final RxnString qtyInfoTooltip = RxnString(null);

  // ── PO link metadata ─────────────────────────────────────────────────────
  final RxString  poItemId  = ''.obs;
  final RxString  poDocName = ''.obs;
  final RxnDouble poQty     = RxnDouble();
  final RxnDouble poRate    = RxnDouble();

  /// When true, the qty cap is lifted and fully-received PO rows become
  /// linkable. Mirrors Delivery Note's `allowFullSerials`. Reset on each
  /// sheet open.
  final RxBool allowOverReceipt = false.obs;

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
    String?  itemGroupValue,
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
      this.itemGroup.value = itemGroupValue ?? '';
      this.variantOf.value = variantOfValue ?? '';
    }

    _parent.linkToPurchaseOrder(code, this);

    // Re-run after linkToPurchaseOrder so qtyInfoText and effectiveMaxQty
    // reflect the now-populated poQty (initForCreate calls validateSheet
    // before poQty is set, leaving the PO Qty chip and progress bar blank).
    validateSheet();
  }

  // ── validateSheet ───────────────────────────────────────────────────────────
  @override
  void validateSheet() {
    final qty  = double.tryParse(qtyController.text) ?? 0.0;
    final ceil = effectiveMaxQty;
    final qtyOk  = qty > 0;
    final ceilOk = ceil == double.infinity || qty <= ceil;

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

    final po = poQty.value;
    qtyInfoTooltip.value = (po != null && po > 0)
        ? 'Ordered: ${po.toStringAsFixed(0)}'
        : null;
  }

  // ── adjustQty ──────────────────────────────────────────────────────────────
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
    _parent.deleteItem(item);
  }

  // ── submit ────────────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty       = double.tryParse(qtyController.text) ?? 0.0;
    final batch     = batchController.text.trim();
    final rack      = rackController.text.trim();
    final warehouse = resolvedWarehouse ?? '';

    if (editingItemName.value != null) {
      parent.updateItem(editingItemName.value!, qty, batch, rack, warehouse);
      await parent.saveDocument();
      return;
    }

    // Resolve a VALID Purchase Order Item before adding (design Section 3).
    final result = parent.resolvePoLink(itemCode.value,
        allowOverReceipt: allowOverReceipt.value);
    switch (result.outcome) {
      case PoLinkOutcome.autoLinked:
        parent.applyPoLink(this, result.linked!);
      case PoLinkOutcome.needsPicker:
        final chosen = await parent.showPoLinkPicker(
          itemCode: itemCode.value,
          candidates: result.allForItem,
          initialAllowOverReceipt: allowOverReceipt.value,
        );
        if (chosen == null) throw const PoLinkAbortedException();
        parent.applyPoLink(this, chosen);
      case PoLinkOutcome.blocked:
        GlobalSnackbar.error(message: result.reason!);
        throw const PoLinkAbortedException();
    }

    parent.addItem(
      itemCode.value, itemName.value, qty, batch, rack, warehouse,
      uom:       itemUom.value,
      poItemId:  poItemId.value,
      poDocName: poDocName.value,
      poQty:     poQty.value  ?? 0.0,
      poRate:    poRate.value ?? 0.0,
    );
    await parent.saveDocument();
  }

  // ── Init helpers ──────────────────────────────────────────────────────────────
  void initForCreate({
    required String code,
    required String name,
    required String uom,
    String? batchNo,
  }) {
    editingItemName.value = null;
    // fix(docstatus): docstatus belongs to the parent document, not the item
    // row. Read from parent PurchaseReceipt to drive the isQtyReadOnly lock.
    docStatus.value       = _parent.purchaseReceipt.value?.docstatus ?? 0;
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
    allowOverReceipt.value = false;

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
    // fix(docstatus): docstatus belongs to the parent document, not the item
    // row. Read from parent PurchaseReceipt to drive the isQtyReadOnly lock.
    docStatus.value       = _parent.purchaseReceipt.value?.docstatus ?? 0;
    itemCode.value        = item.itemCode;
    itemName.value        = item.itemName ?? '';
    itemUom.value         = item.uom ?? '';
    itemGroup.value       = item.itemGroup ?? '';
    variantOf.value       = item.customVariantOf ?? '';

    batchController.text = item.batchNo ?? '';
    rackController.text  = item.rack    ?? '';
    qtyController.text   = item.qty.toString();
    itemWarehouse.value  = item.warehouse;

    poItemId.value  = item.purchaseOrderItem ?? '';
    poDocName.value = item.purchaseOrder     ?? '';
    poQty.value     = item.purchaseOrderQty;
    poRate.value    = item.rate != null && item.rate! > 0 ? item.rate : null;
    allowOverReceipt.value = false;

    resetBatch();
    isQtyValid.value = false;
    qtyError.value   = '';
    removeSheetListeners();
    addSheetListeners();
    rackController.text = item.rack ?? '';

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

  // ── BatchNoBrowseDelegate ──────────────────────────────────────────────────

  /// Batch picker is available as soon as an item is loaded.
  /// For PR, batches are inbound so itemCode alone is sufficient to browse.
  @override
  bool get canBrowseBatch => itemCode.value.isNotEmpty;

  static const _kBatchPickerTag = 'pr_batch_picker';

  @override
  Future<String?> browseBatches() async {
    if (!canBrowseBatch) return null;
    if (isValidatingBatch.value) return null;

    final ctx = Get.context;
    if (ctx == null) return null;

    try {
      return await showBatchPickerSheet(
        ctx,
        itemCode:    itemCode.value,
        warehouse:   resolvedWarehouse,
        accentColor: accentColor,
      );
    } catch (e) {
      log('[PR-Item] browseBatches error: $e', name: 'PR-Item');
      return null;
    }
  }

  @override
  Future<void> handleBatchPicked(String batchNo) async {
    if (batchNo.trim().isEmpty) return;
    batchController.text = batchNo.trim();
    await validateBatch(batchNo.trim());
  }

  // ── Rack validation override ──────────────────────────────────────────────────
  /// For Purchase Receipt the rack is a *destination* for incoming goods.
  /// Validate by Rack doctype existence — NOT by current stock balance.
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
      final rows = await ApiProvider().getList(
        'Rack',
        filters: {'name': trimmed},
        fields: ['name', 'warehouse'],
      );

      if (rows.isEmpty) {
        rackError.value = 'Rack "$trimmed" not found.';
        validateSheet();
        return;
      }

      // Derive warehouse from the Rack doctype — mirrors SE / DN behaviour.
      final derivedWh = rows.first['warehouse'] as String?;
      if (derivedWh != null && derivedWh.isNotEmpty) {
        itemWarehouse.value = derivedWh;
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

  // ── RackBrowseDelegate ─────────────────────────────────────────────────────

  /// Rack picker is available as soon as an item is loaded.
  /// For PR the rack is a destination; no stock-balance pre-filter is needed.
  @override
  bool get canBrowseRacks => itemCode.value.isNotEmpty;

  static const _kRackPickerTag = 'pr_rack_picker';

  @override
  Future<RackPickerResult?> browseRacks() async {
    if (!canBrowseRacks) return null;
    if (isValidatingRack.value) return null;

    final ctx = Get.context;
    if (ctx == null) return null;

    final pickerCtrl = Get.put(
      RackPickerController(),
      tag: _kRackPickerTag,
    );

    try {
      // For Purchase Receipt the rack is inbound: pass empty batchNo/fallbackMap
      // so the picker shows all racks in the warehouse without balance filtering.
      unawaited(pickerCtrl.load(
        itemCode:     itemCode.value,
        batchNo:      '',
        warehouse:    resolvedWarehouse ?? '',
        requestedQty: double.tryParse(qtyController.text) ?? 0.0,
        currentRack:  rackController.text.trim(),
        fallbackMap:  const {},
      ));

      String? selectedRackId;

      await showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => RackPickerSheet(
          pickerTag:  _kRackPickerTag,
          onSelected: (rack) { selectedRackId = rack; },
        ),
      );

      if (selectedRackId == null || selectedRackId!.isEmpty) return null;

      final entry = pickerCtrl.entries.firstWhere(
            (e) => e.rackName == selectedRackId,
        orElse: () => RackPickerEntry(
          rackName:     selectedRackId!,
          location:     null,
          availableQty: 0.0,
          requestedQty: double.tryParse(qtyController.text) ?? 0.0,
        ),
      );

      return RackPickerResult(
        rackId:       entry.rackName,
        availableQty: entry.availableQty,
        warehouse:    entry.warehouseName,
        raw:          const {},
      );
    } catch (e) {
      log('[PR-Item] browseRacks error: $e', name: 'PR-Item');
      return null;
    } finally {
      if (Get.isRegistered<RackPickerController>(tag: _kRackPickerTag)) {
        Get.delete<RackPickerController>(tag: _kRackPickerTag);
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────────
  @override
  void applyRackScan(String rackId) {
    final id = rackId.trim();
    if (id.isEmpty) return;
    // Clear any previously derived warehouse so a re-scan of a different
    // rack does not leave the old warehouse value in place during the async gap.
    itemWarehouse.value = null;
    rackController.text = id;
    validateRack(id).then((_) => validateSheet());
  }

  /// Called by the base after [browseRacks] returns a non-null result.
  /// Writes the rack name and triggers existence validation.
  @override
  Future<void> handleRackPicked(RackPickerResult result) async {
    // Apply picker-resolved warehouse immediately (before the API round-trip
    // in validateRack overwrites it) so resolvedWarehouse is correct as soon
    // as the rack is accepted — mirrors SE/DN behaviour.
    if (result.warehouse != null && result.warehouse!.isNotEmpty) {
      itemWarehouse.value = result.warehouse;
    }
    rackController.text = result.rackId;
    await validateRack(result.rackId);
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

  @override
  void onClose() {
    disposeBarcodeListener();  // BarcodeAwareMixin safety-net disposal
    super.onClose();
  }
}
