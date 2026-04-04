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
///
/// DN-2:
///   - posItemQty overrides the PosSerialMixin default (0.0) to return
///     the actual POS-Upload qty cap for the selected serial via the
///     parent controller.  This enables posSerialCapText (added in DN-1)
///     to produce a meaningful "remaining / cap" ratio string.
///   - liveRemaining is written in validateSheet() so the chip updates
///     live as the user types a qty value.
///   - liveRemaining is seeded in initForEdit() so the chip is correct
///     immediately when the sheet opens on an existing item.
///
/// DN-6:
///   - initForEdit() serial seed guard relaxed: when availableSerialNos
///     is empty at init time (POS Upload async load not yet complete),
///     selectedSerial is seeded unconditionally so the value is not
///     silently dropped.  When availableSerialNos is non-empty the
///     original contains() guard is preserved.
///   - captureSerialSnapshot() called after selectedSerial is seeded so
///     the dirty-check baseline matches the opened state (prevents false
///     isDirty = true immediately on open).
///   - initForNewItem() also calls captureSerialSnapshot() for symmetry.
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {

  // ── Parent back-reference ──────────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  DeliveryNoteFormController get parent => _parent;

  // ── Local reactive state ───────────────────────────────────
  final RxString itemCodeRx       = ''.obs;
  final RxString itemNameRx       = ''.obs;
  final RxString itemUomRx        = ''.obs;
  final RxString itemGroupRx      = ''.obs;
  final RxString currentVariantOf = ''.obs;

  final RxBool isExistingItem = false.obs;
  final RxInt  editingIndex   = (-1).obs;

  final RxMap<String, double> rackStockMapRx = <String, double>{}.obs;

  // ── Base abstract overrides ───────────────────────────────────────
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

  // ── qtyInfoText / qtyInfoTooltip ──────────────────────────────────
  @override
  String get qtyInfoText => '';

  @override
  final RxnString qtyInfoTooltip = RxnString(null);

  // ── PosSerialMixin: posItemQty override (DN-2) ────────────────────────
  /// Total POS-Upload qty cap for the currently selected serial.
  ///
  /// Delegates to the parent form controller which reads the PosUpload
  /// document.  Returns double.infinity (treated as "no cap" by
  /// posSerialCapText, which returns null) when no serial is selected
  /// or no POS Upload is loaded.
  @override
  double get posItemQty =>
      _parent.posQtyCapForSerial(selectedSerial.value ?? '');

  // ── adjustQty ──────────────────────────────────────────────────
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, double.infinity);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem ──────────────────────────────────────────────
  @override
  void deleteCurrentItem() {
    if (!isExistingItem.value || editingIndex.value < 0) return;
    _parent.deliveryNote.value?.items.removeAt(editingIndex.value);
    _parent.deliveryNote.refresh();
    Get.back();
  }

  // ── PosSerialMixin wiring ────────────────────────────────────────────
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

  // ── Legacy name aliases ────────────────────────────────────────────
  RxString get itemCodeValue  => itemCodeRx;
  RxString get itemNameValue  => itemNameRx;
  RxString get itemUomValue   => itemUomRx;
  RxString get itemGroupValue => itemGroupRx;

  // ── AutoFillRackMixin wiring ────────────────────────────────────────
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

  // ── initialise() entry point ────────────────────────────────────────
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

  // ── Lifecycle / init ──────────────────────────────────────────────
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
    selectedSerial.value  = null;
    liveRemaining.value   = 0.0;   // DN-2: explicit reset for new-item mode
    rackStockMapRx.clear();
    isSheetValid.value = false;

    removeSheetListeners();
    addSheetListeners();
    snapshotState();
    captureSerialSnapshot();   // DN-6: baseline serial = null for new items

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

    // Bug 1 fix (relaxed by DN-6): seed selectedSerial from the item's
    // persisted value.
    //
    // DN-6 guard logic:
    //   - If availableSerialNos is non-empty (POS Upload already loaded),
    //     only seed if the value is in the list — prevents a
    //     DropdownButtonFormField assertion on an unlisted value.
    //   - If availableSerialNos is empty (POS Upload not yet loaded or
    //     no POS Upload attached), seed unconditionally.  SharedSerialField
    //     hides the dropdown when serials.isEmpty, so there is no
    //     assertion risk; the value will be available once the dropdown
    //     becomes visible.
    final persistedSerial = item.customInvoiceSerialNumber;
    final serials = availableSerialNos;
    if (persistedSerial != null && persistedSerial.isNotEmpty) {
      if (serials.isEmpty || serials.contains(persistedSerial)) {
        selectedSerial.value = persistedSerial;
      } else {
        // Serial exists on the item but is not in the loaded list —
        // log a warning and leave the dropdown unset rather than
        // throwing a DropdownButtonFormField assertion.
        log(
          '[DN-Item] initForEdit: persisted serial "$persistedSerial" '
          'is not in availableSerialNos $serials — dropdown left unset.',
          name: 'DN-Item',
        );
        selectedSerial.value = null;
      }
    } else {
      selectedSerial.value = null;
    }

    // DN-2: seed liveRemaining immediately so the POS cap chip shows the
    // correct remaining qty as soon as the sheet opens in edit mode.
    _seedLiveRemaining(serial: persistedSerial, excludeName: item.name);

    rackStockMapRx.clear();
    isSheetValid.value = false;

    removeSheetListeners();
    addSheetListeners();
    snapshotState();
    captureSerialSnapshot();   // DN-6: baseline = seeded serial, not null

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

  // ── liveRemaining helpers (DN-2) ───────────────────────────────────────────

  /// Writes liveRemaining based on [_parent.remainingQtyForSerial], adjusted
  /// for the item currently in the sheet.
  ///
  /// [serial]      — the selected invoice serial number (may be null).
  /// [excludeName] — the name of the item being edited so its committed
  ///                  qty is not double-counted against the remaining cap.
  void _seedLiveRemaining({String? serial, String? excludeName}) {
    if (serial == null || serial.isEmpty) {
      liveRemaining.value = 0.0;
      return;
    }
    final cap  = _parent.posQtyCapForSerial(serial);
    if (cap == double.infinity) {
      liveRemaining.value = 0.0;  // chip hidden when no finite cap
      return;
    }
    final used = _parent.scannedQtyForSerial(serial, excludeItemName: excludeName);
    liveRemaining.value = (cap - used).clamp(0.0, cap);
  }

  /// Updates liveRemaining in response to qty field changes during active
  /// editing.  Called from validateSheet() so it runs on every keystroke.
  void _updateLiveRemaining() {
    final serial = selectedSerial.value;
    if (serial == null || serial.isEmpty) {
      liveRemaining.value = 0.0;
      return;
    }
    final cap = _parent.posQtyCapForSerial(serial);
    if (cap == double.infinity) {
      liveRemaining.value = 0.0;
      return;
    }
    final usedByOthers = _parent.scannedQtyForSerial(
      serial,
      excludeItemName: editingItemName.value,
    );
    final enteredQty = double.tryParse(qtyController.text) ?? 0.0;
    liveRemaining.value = (cap - usedByOthers - enteredQty).clamp(0.0, cap);
  }

  // ── Sheet validity ─────────────────────────────────────────────────
  @override
  void validateSheet() {
    final qty = double.tryParse(qtyController.text) ?? 0;
    isSheetValid.value = isBatchValid.value && qty > 0;

    // DN-2: keep liveRemaining in sync with every qty keystroke so the
    // POS cap chip reflects the qty the user is currently entering.
    _updateLiveRemaining();
  }

  // ── submit ─────────────────────────────────────────────────────
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
      rate:                       0.0,
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

  // ── Rack-map preload for AutoFillRack / RackPicker ──────────────────────
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
        final rack = (raw['rack'] ?? '').toString().trim();
        if (rack.isEmpty) continue;
        final qty = (raw['bal_qty'] as num?)?.toDouble() ?? 0.0;
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
    selectedSerial.value  = null;
    liveRemaining.value   = 0.0;
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
