import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';

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
/// Commit D (Rack-Picker extraction):
///   • Moved rack-picker bottom sheet UI into shared [RackPickerSheet].
///   • [applyRackScan] is the only public mutation API used by the picker.
///
/// Commit C:
///   • Added [editMode] support via [SharedBatchField] / [SharedRackField].
///   • Batch field is readOnly only when valid and warning-free.
///   • Warning states (soon-expiry) stay editable and show orange helper text.
///
/// Commit B:
///   • Added AutoFillRackMixin integration.
///   • [validateBatch] override calls base [fetchBatchBalance] +
///     [maybeAutoFillRack] once batch becomes valid.
///
/// Commit A:
///   • Extracted shared batch / rack logic into [ItemSheetControllerBase].
///   • This controller now only carries DN-specific rules and submission.
///
/// Notes:
///   • Rack is optional for DN; therefore [requiresRack] == false.
///   • Batch is mandatory for batched items; DN item sheet always uses a
///     batched item in current flow.
///   • `dart:async` import retained for [unawaited].
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

  // Rack-side pre-fetched map used by AutoFillRackMixin / rack picker
  final RxMap<String, double> rackStockMapRx = <String, double>{}.obs;

  // POS serial cap is maintained in mixin state (serial no + qty cap)

  // ── Base overrides ────────────────────────────────────────────────────────
  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override
  bool get requiresBatch => true;

  @override
  bool get requiresRack => false;

  @override
  Color get accentColor => Colors.blueGrey;

  @override
  bool get isSheetLoading => super.isSheetLoading;

  // The shared widgets expect these reactive fields directly on the controller.
  // Mirror the legacy names for zero-diff call-sites.
  RxString get itemCodeValue  => itemCodeRx;
  RxString get itemNameValue  => itemNameRx;
  RxString get itemUomValue   => itemUomRx;
  RxString get itemGroupValue => itemGroupRx;

  // Expose base [itemCode] through legacy slot expected by mixins/widgets.
  @override
  String get mixinItemCode => itemCode.value;

  @override
  String? get mixinWarehouse => resolvedWarehouse;

  @override
  String get mixinBatch => batchController.text;

  @override
  double get mixinQty => double.tryParse(qtyController.text) ?? 0.0;

  @override
  Map<String, double> get rackStockMap => Map<String, double>.from(rackStockMapRx);

  @override
  void onRackAutoFilled(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  // ── PosSerialMixin wiring ────────────────────────────────────────────────
  @override
  List<dynamic> get posItems => _parent.posItems;

  @override
  dynamic get posUpload => _parent.posUpload.value;

  // ── Derived UI helpers ───────────────────────────────────────────────────
  String get qtyInfoText => '';
  String? get qtyInfoTooltip => null;

  // ── Lifecycle / init ─────────────────────────────────────────────────────
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

    this.itemCode.value    = item.itemCode;
    itemCodeRx.value       = item.itemCode;
    itemNameRx.value       = item.itemName;
    itemUomRx.value        = item.uom;
    itemGroupRx.value      = item.itemGroup ?? '';
    currentVariantOf.value = variantOf;

    batchController.text   = item.batchNo ?? '';
    rackController.text    = item.rack ?? '';
    qtyController.text     = item.qty.toString();

    // Reset shared validation state before re-validating from pre-filled values.
    resetBatch();
    resetRack();
    clearPosSerialSelection();
    rackStockMapRx.clear();

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

  // ── Sheet validity ───────────────────────────────────────────────────────
  @override
  bool get isSheetValid {
    final qty = double.tryParse(qtyController.text) ?? 0;
    return isBatchValid.value && qty > 0;
  }

  @override
  void validateSheet() {
    // DN has no extra derived validation beyond the shared observable state.
    // setState-equivalent rebuilds are driven by Obx in the widgets.
  }

  // ── submit ────────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) {
      throw Exception('Enter a valid quantity');
    }
    if (!isBatchValid.value) {
      throw Exception('Batch validation required');
    }

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
    final wh = resolvedWarehouse;
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

  // ── AutoFillRack integration hooks ───────────────────────────────────────
  @override
  Future<void> maybeAutoFillRack() async {
    // Keep the mixin behaviour, but ensure the latest map is ready first.
    await preloadRackStockMap();
    await super.maybeAutoFillRack();
  }

  // ── Batch validation override (DN-specific) ──────────────────────────────
  @override
  Future<void> validateBatch(String batch) async {
    await super.validateBatch(batch);

    if (!isBatchValid.value) return;

    // Once batch becomes valid, refresh the rack map and attempt auto-fill.
    // Fire-and-forget to avoid blocking UI on slow inventory-dimension query.
    unawaited(maybeAutoFillRack());
  }

  // ── Rack validation override ──────────────────────────────────────────────
  @override
  Future<void> validateRack(String rack) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty) {
      resetRack();
      return;
    }

    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;

    try {
      // Prefer cached rack stock map (already scoped by item + batch + wh).
      final qty = rackStockMapRx[trimmed];
      if (qty != null) {
        rackBalance.value = qty;
        isRackValid.value = true;
        return;
      }

      // Fallback to shared API-backed validation path.
      await super.validateRack(trimmed);
    } finally {
      isValidatingRack.value = false;
    }
  }

  // ── Public API used by RackPickerSheet / scanner routes ──────────────────
  void applyRackScan(String rackId) {
    final id = rackId.trim();
    if (id.isEmpty) return;
    rackController.text = id;
    validateRack(id);
  }

  // ── Optional helpers used by form controller ─────────────────────────────
  void clearAll() {
    batchController.clear();
    rackController.clear();
    qtyController.clear();
    resetBatch();
    resetRack();
    clearPosSerialSelection();
    rackStockMapRx.clear();
  }

  // Convenience label for UI chips/tooltips if needed later.
  String get currentItemDisplay =>
      [itemCode.value, itemNameRx.value].where((e) => e.trim().isNotEmpty).join(' - ');

  // Helper used by future duplicate detection / UX.
  bool get hasExistingRackMap => rackStockMapRx.isNotEmpty;

  // Placeholder hook kept for parity with legacy controller shape.
  Future<void> ensureReadyForOpen() async {
    // No-op for now.
  }

  @override
  void onClose() {
    removeSheetListeners();
    super.onClose();
  }
}
