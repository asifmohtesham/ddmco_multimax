import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
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
/// Commit 2 (compiler fix):
///   • Removed 'bool get isSheetLoading' override (type mismatch with base RxBool).
///   • isSheetValid is now written via isSheetValid.value in validateSheet().
///   • Implemented abstract members: isAddMode, qtyInfoText, qtyInfoTooltip,
///     sheetScanController, adjustQty, deleteCurrentItem, availableSerialNos.
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {
  final DeliveryNoteFormController _parent;

  DeliveryNoteItemFormController(this._parent);

  // ── Local reactive state ──────────────────────────────────────────────────
  final RxString itemCodeRx      = ''.obs;
  final RxString itemNameRx      = ''.obs;
  final RxString itemUomRx       = ''.obs;
  final RxString itemGroupRx     = ''.obs;
  final RxString currentVariantOf = ''.obs;

  final RxBool   isExistingItem  = false.obs;
  final RxInt    editingIndex    = (-1).obs;

  final RxMap<String, double> rackStockMapRx = <String, double>{}.obs;

  // ── Base overrides ──────────────────────────────────────────────────────
  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override bool get requiresBatch => true;
  @override bool get requiresRack  => false;
  @override Color get accentColor  => Colors.blueGrey;

  // isSheetLoading override REMOVED — base field is already RxBool.

  /// true when adding a new item; false when editing an existing one.
  @override
  bool get isAddMode => !isExistingItem.value;

  /// DN does not use an inline scanner; return null.
  @override
  MobileScannerController? get sheetScanController => null;

  // ── qtyInfoText / qtyInfoTooltip ───────────────────────────────────────────
  @override String    get qtyInfoText    => '';
  @override RxnString get qtyInfoTooltip => super.qtyInfoTooltip;

  // ── adjustQty ──────────────────────────────────────────────────────────────
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, double.infinity);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem ─────────────────────────────────────────────────────
  @override
  void deleteCurrentItem() {
    if (!isExistingItem.value || editingIndex.value < 0) return;
    _parent.items.removeAt(editingIndex.value);
    _parent.items.refresh();
    Get.back();
  }

  // ── PosSerialMixin wiring ────────────────────────────────────────────────
  @override List<dynamic> get posItems  => _parent.posItems;
  @override dynamic       get posUpload => _parent.posUpload.value;

  @override
  List<String> get availableSerialNos {
    if (posUpload == null) return const [];
    return posItems
        .map((e) => (e['serial_no'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── Legacy name aliases ──────────────────────────────────────────────────────
  RxString get itemCodeValue  => itemCodeRx;
  RxString get itemNameValue  => itemNameRx;
  RxString get itemUomValue   => itemUomRx;
  RxString get itemGroupValue => itemGroupRx;

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

  // ── Lifecycle / init ──────────────────────────────────────────────────────
  void initForNewItem({
    required String itemCode,
    required String itemName,
    required String uom,
    required String itemGroup,
    String variantOf = '',
    String? batchNo,
  }) {
    isExistingItem.value = false;
    editingIndex.value   = -1;
    editingItemName.value = null;

    this.itemCode.value       = itemCode;
    itemCodeRx.value          = itemCode;
    itemNameRx.value          = itemName;
    itemUomRx.value           = uom;
    itemGroupRx.value         = itemGroup;
    currentVariantOf.value    = variantOf;

    batchController.text      = batchNo ?? '';
    rackController.clear();
    qtyController.clear();

    resetBatch();
    resetRack();
    clearPosSerialSelection();
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
    isExistingItem.value = true;
    editingIndex.value   = index;
    editingItemName.value = item.name;

    this.itemCode.value    = item.itemCode;
    itemCodeRx.value       = item.itemCode;
    itemNameRx.value       = item.itemName;
    itemUomRx.value        = item.uom;
    itemGroupRx.value      = item.itemGroup ?? '';
    currentVariantOf.value = variantOf;

    batchController.text   = item.batchNo ?? '';
    rackController.text    = item.rack ?? '';
    qtyController.text     = item.qty.toString();

    resetBatch();
    resetRack();
    clearPosSerialSelection();
    rackStockMapRx.clear();
    isSheetValid.value = false;

    removeSheetListeners();
    addSheetListeners();
    snapshotState();

    if ((item.batchNo ?? '').isNotEmpty) {
      validateBatchOnInit(item.batchNo!);
    }
    if ((item.rack ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateRack(item.rack!);
      });
    }
  }

  // ── Sheet validity ──────────────────────────────────────────────────────
  // isSheetValid getter REMOVED — written via isSheetValid.value below.

  @override
  void validateSheet() {
    final qty = double.tryParse(qtyController.text) ?? 0;
    isSheetValid.value = isBatchValid.value && qty > 0;
  }

  // ── submit ───────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Enter a valid quantity');
    if (!isBatchValid.value)     throw Exception('Batch validation required');

    final item = DeliveryNoteItem(
      itemCode:    itemCode.value,
      itemName:    itemNameRx.value,
      uom:         itemUomRx.value,
      qty:         qty,
      batchNo:     batchController.text.trim(),
      rack:        rackController.text.trim().isEmpty ? null : rackController.text.trim(),
      itemGroup:   itemGroupRx.value,
      variantOf:   currentVariantOf.value.isEmpty ? null : currentVariantOf.value,
      serialNo:    selectedPosSerial.value,
      posQtyCap:   posSerialQtyCap,
    );

    if (isExistingItem.value && editingIndex.value >= 0) {
      _parent.items[editingIndex.value] = item;
      _parent.items.refresh();
    } else {
      _parent.items.add(item);
    }
  }

  // ── Rack-map preload for AutoFillRack / RackPicker ───────────────────────
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

  @override
  Future<void> maybeAutoFillRack() async {
    await preloadRackStockMap();
    await super.maybeAutoFillRack();
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
    clearPosSerialSelection();
    rackStockMapRx.clear();
  }

  String get currentItemDisplay =>
      [itemCode.value, itemNameRx.value].where((e) => e.trim().isNotEmpty).join(' - ');

  bool get hasExistingRackMap => rackStockMapRx.isNotEmpty;

  Future<void> ensureReadyForOpen() async {}

  @override
  void onClose() {
    removeSheetListeners();
    super.onClose();
  }
}
