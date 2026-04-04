import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Shared base + mixins
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_pos_serial.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_autofill_rack.dart';

// Data layer
import 'package:multimax/app/data/providers/api_provider.dart';

// Domain model
import 'package:multimax/app/data/models/delivery_note_model.dart';

// Parent controller
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';

/// Item-level sheet controller for Delivery Note.
///
/// Group B fixes (on top of Commit 7):
///   B3 — deleteCurrentItem() called _parent.items.refresh() on a plain
///        List<DeliveryNoteItem>.  .refresh() does not exist on List;
///        replaced with _parent.deliveryNote.refresh() (the Rx wrapper).
///   B4 — submit() passed posQtyCap: _posQtyCap to the DeliveryNoteItem
///        constructor.  DeliveryNoteItem has no such field; argument removed.
///
/// Error E2 fix:
///   maybeAutoFillRack() overrides the AutoFillRackMixin method to inject
///   a preloadRackStockMap() step before autofill runs.  The original code
///   called `await super.maybeAutoFillRack()` but `super.` resolves only
///   through the class hierarchy — it cannot dispatch into a mixin method
///   when the mixin does not declare maybeAutoFillRack on the base class.
///   Fix: after preloading, call `autoFillRackForQty(qty)` directly —
///   this is the public mixin entry-point that contains the core selection
///   logic, and it is always available on `this`.
///
/// Commit 1 fix:
///   initForEdit() now seeds selectedSerial and preserves rackController
///   text so the sheet opens with the item's existing serial and rack
///   values pre-populated (Bugs 1 & 3 from the DN item-form discrepancy
///   report).
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {

  // ── Parent back-reference ──────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  DeliveryNoteFormController get parent => _parent;

  // ── Local reactive state ───────────────────────────────────────────────
  final RxString itemCodeRx       = ''.obs;
  final RxString itemNameRx       = ''.obs;
  final RxString itemUomRx        = ''.obs;
  final RxString itemGroupRx      = ''.obs;
  final RxString currentVariantOf = ''.obs;

  final RxBool isExistingItem = false.obs;
  final RxInt  editingIndex   = (-1).obs;

  final RxMap<String, double> rackStockMapRx = <String, double>{}.obs;

  // ── Base abstract overrides ────────────────────────────────────────────
  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override bool  get requiresBatch => true;
  @override bool  get requiresRack  => false;
  @override Color get accentColor   => Colors.blueGrey;

  @override
  bool get isAddMode => !isExistingItem.value;

  @override
  MobileScannerController? get sheetScanController => null;

  // ── qtyInfoText / qtyInfoTooltip ───────────────────────────────────────
  @override
  String get qtyInfoText => '';

  @override
  final RxnString qtyInfoTooltip = RxnString(null);

  // ── adjustQty ──────────────────────────────────────────────────────────
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, double.infinity);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem ──────────────────────────────────────────────────
  @override
  void deleteCurrentItem() {
    if (!isExistingItem.value || editingIndex.value < 0) return;
    _parent.deliveryNote.value?.items.removeAt(editingIndex.value);
    _parent.deliveryNote.refresh();
    Get.back();
  }

  // ── PosSerialMixin wiring ──────────────────────────────────────────────
  @override
  List<String> get availableSerialNos {
    final upload = _parent.posUpload.value;
    if (upload == null) return const [];
    return upload.items
        .map((e) => e.idx.toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  double get _posQtyCap {
    final serial = selectedSerial.value;
    if (serial == null || serial.isEmpty) return double.infinity;
    return _parent.posQtyCapForSerial(serial);
  }

  // ── Legacy name aliases ────────────────────────────────────────────────
  RxString get itemCodeValue  => itemCodeRx;
  RxString get itemNameValue  => itemNameRx;
  RxString get itemUomValue   => itemUomRx;
  RxString get itemGroupValue => itemGroupRx;

  // ── AutoFillRackMixin wiring ───────────────────────────────────────────
  @override String  get mixinItemCode  => itemCode.value;
  @override String? get mixinWarehouse => resolvedWarehouse;
  @override String  get mixinBatch     => batchController.text;
  @override double  get mixinQty       => double.tryParse(qtyController.text) ?? 0.0;
  @override Map<String, double> get rackStockMap => Map<String, double>.from(rackStockMapRx);

  @override
  void onRackAutoFilled(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  // ── initialise() entry point ───────────────────────────────────────────
  void initialise({
    required DeliveryNoteFormController parent,
    required String code,
    required String name,
    String?  batchNo,
    String?  scannedEan8,
    String?  variantOf,
    DeliveryNoteItem? editingItem,
  }) {
    _parent = parent;

    if (editingItem != null) {
      final items = parent.deliveryNote.value?.items ?? [];
      final idx   = items.indexWhere((i) => i.name == editingItem.name);
      initForEdit(
        index:    idx >= 0 ? idx : 0,
        item:     editingItem,
        variantOf: variantOf ?? editingItem.customVariantOf ?? '',
      );
    } else {
      initForNewItem(
        itemCode:  code,
        itemName:  name,
        uom:       'Nos',
        itemGroup: '',
        variantOf: variantOf ?? '',
        batchNo:   batchNo,
      );
    }
  }

  // ── Lifecycle / init ───────────────────────────────────────────────────
  void initForNewItem({
    required String itemCode,
    required String itemName,
    required String uom,
    required String itemGroup,
    String variantOf = '',
    String? batchNo,
  }) {
    isExistingItem.value  = false;
    editingIndex.value    = -1;
    editingItemName.value = null;

    this.itemCode.value    = itemCode;
    itemCodeRx.value       = itemCode;
    itemNameRx.value       = itemName;
    itemUomRx.value        = uom;
    itemGroupRx.value      = itemGroup;
    currentVariantOf.value = variantOf;

    batchController.text = batchNo ?? '';
    rackController.clear();
    qtyController.clear();

    resetBatch();
    resetRack();
    selectedSerial.value = null;
    rackStockMapRx.clear();
    isSheetValid.value = false;

    removeSheetListeners();
    addSheetListeners();
    snapshotState();

    if ((batchNo ?? '').isNotEmpty) {
      validateBatchOnInit(batchNo!);
    }
  }

  void initForEdit({
    required int index,
    required DeliveryNoteItem item,
    String variantOf = '',
  }) {
    isExistingItem.value  = true;
    editingIndex.value    = index;
    editingItemName.value = item.name;

    this.itemCode.value    = item.itemCode;
    itemCodeRx.value       = item.itemCode;
    itemNameRx.value       = item.itemName ?? '';
    itemUomRx.value        = item.uom ?? '';
    itemGroupRx.value      = item.itemGroup ?? '';
    currentVariantOf.value = variantOf;

    // Stash field values before the reset block clears controller state.
    final existingRack   = item.rack    ?? '';
    final existingBatch  = item.batchNo ?? '';
    final existingQty    = item.qty.toString();

    // Reset validation state without clearing the text controllers yet —
    // we will re-apply the saved values immediately below.
    resetBatch();
    resetRack();

    // Re-apply saved values so the sheet opens pre-populated.
    batchController.text = existingBatch;
    rackController.text  = existingRack;
    qtyController.text   = existingQty;

    // Bug 1 fix: seed selectedSerial from the item's persisted value so
    // the Invoice Serial No dropdown shows the correct selection on open.
    // Guard: only assign if the serial exists in availableSerialNos to
    // avoid a DropdownButtonFormField assertion on an unlisted value.
    final persistedSerial = item.customInvoiceSerialNumber;
    if (persistedSerial != null &&
        persistedSerial.isNotEmpty &&
        availableSerialNos.contains(persistedSerial)) {
      selectedSerial.value = persistedSerial;
    } else {
      selectedSerial.value = null;
    }

    rackStockMapRx.clear();
    isSheetValid.value = false;

    removeSheetListeners();
    addSheetListeners();
    snapshotState();

    if (existingBatch.isNotEmpty) {
      validateBatchOnInit(existingBatch);
    }
    // Bug 3 fix: the rack text is already in rackController at this point.
    // Trigger validation in a post-frame callback so the sheet widget tree
    // is fully built before the async validate call mutates Rx state.
    if (existingRack.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateRack(existingRack);
      });
    }
  }

  // ── Sheet validity ─────────────────────────────────────────────────────
  @override
  void validateSheet() {
    final qty = double.tryParse(qtyController.text) ?? 0;
    isSheetValid.value = isBatchValid.value && qty > 0;
  }

  // ── submit ─────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Enter a valid quantity');
    if (!isBatchValid.value)     throw Exception('Batch validation required');

    final item = DeliveryNoteItem(
      itemCode:                  itemCode.value,
      itemName:                  itemNameRx.value,
      uom:                       itemUomRx.value,
      qty:                       qty,
      rate:                      0.0,
      batchNo:                   batchController.text.trim(),
      rack:  rackController.text.trim().isEmpty ? null : rackController.text.trim(),
      itemGroup:                 itemGroupRx.value,
      customVariantOf:           currentVariantOf.value.isEmpty ? null : currentVariantOf.value,
      customInvoiceSerialNumber: selectedSerial.value,
    );

    if (isExistingItem.value && editingIndex.value >= 0) {
      _parent.deliveryNote.value?.items[editingIndex.value] = item;
      _parent.deliveryNote.refresh();
    } else {
      _parent.deliveryNote.value?.items.add(item);
      _parent.deliveryNote.refresh();
    }
  }

  // ── Rack-map preload for AutoFillRack / RackPicker ─────────────────────
  Future<void> preloadRackStockMap() async {
    final wh    = resolvedWarehouse;
    final batch = batchController.text.trim();
    if (itemCode.value.isEmpty || wh == null || wh.isEmpty || batch.isEmpty) return;

    try {
      final rows = await ApiProvider().getStockBalanceWithDimension(
        itemCode:  itemCode.value,
        warehouse: wh,
        batchNo:   batch,
      );
      final map = <String, double>{};
      for (final raw in rows) {
        final rack = (raw['custom_rack'] ?? '').toString().trim();
        if (rack.isEmpty) continue;
        final qty = (raw['qty'] as num?)?.toDouble() ?? 0.0;
        map[rack] = (map[rack] ?? 0) + qty;
      }
      rackStockMapRx.assignAll(map);
    } catch (e) {
      log('[DN-Item] preloadRackStockMap error: $e', name: 'DN-Item');
      rackStockMapRx.clear();
    }
  }

  /// E2 fix: maybeAutoFillRack() is declared on AutoFillRackMixin, not on
  /// ItemSheetControllerBase.  `super.maybeAutoFillRack()` fails at compile
  /// time because `super` cannot dispatch to a mixin method — it resolves
  /// only through the class chain.  The correct pattern is:
  ///   1. Run any pre-autofill work (preloadRackStockMap).
  ///   2. Call the mixin's public entry-point autoFillRackForQty(qty)
  ///      directly on `this`, which applies the warehouse-aware rack
  ///      selection logic defined in AutoFillRackMixin.
  @override
  Future<void> maybeAutoFillRack() async {
    await preloadRackStockMap();
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty > 0) autoFillRackForQty(qty);
  }

  @override
  Future<void> validateBatch(String batch) async {
    await super.validateBatch(batch);
    if (!isBatchValid.value) return;
    unawaited(maybeAutoFillRack());
  }

  @override
  Future<void> validateRack(String rack) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty) { resetRack(); return; }

    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;

    try {
      final qty = rackStockMapRx[trimmed];
      if (qty != null) {
        rackBalance.value = qty;
        isRackValid.value = true;
        return;
      }
      await super.validateRack(trimmed);
    } finally {
      isValidatingRack.value = false;
    }
  }

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
    resetBatch();
    resetRack();
    selectedSerial.value = null;
    rackStockMapRx.clear();
  }

  String get currentItemDisplay =>
      [itemCode.value, itemNameRx.value]
          .where((e) => e.trim().isNotEmpty)
          .join(' - ');

  bool get hasExistingRackMap => rackStockMapRx.isNotEmpty;

  Future<void> ensureReadyForOpen() async {}

  @override
  void onClose() {
    removeSheetListeners();
    super.onClose();
  }
}
