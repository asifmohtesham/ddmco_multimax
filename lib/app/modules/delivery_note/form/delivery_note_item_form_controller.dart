import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/shared/barcode_listener_mixin.dart';
import 'package:multimax/app/shared/item_sheet/barcode_aware_mixin.dart';

// Shared base + mixins
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_autofill_rack.dart';

// Picker
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';

// Data layer
import 'package:multimax/app/data/providers/api_provider.dart';

// Domain model
import 'package:multimax/app/data/models/delivery_note_model.dart';

// Parent controller
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';

/// Item-level sheet controller for Delivery Note.
///
/// Commit 4 (SerialFieldMixin adoption):
///   - Replaced `with PosSerialMixin` with `with SerialFieldMixin`.
///   - Removed private _seedLiveRemaining() and _updateLiveRemaining();
///     both delegated to SerialFieldMixin.computeLiveRemaining().
///   - posItemQtyForSerial(String serial) replaces posItemQty getter;
///     delegates to _parent.posQtyCapForSerial(serial).
///   - sumQtyUsedForSerial(String serial) added; delegates to
///     _parent.scannedQtyForSerial() which walks items in-memory.
///   - savedQtyForRow(String rowId) added; looks up the item's saved qty
///     from _parent.items by name for edit-mode double-count prevention.
///   - effectiveMaxQty: replaced posItemQty with
///     posItemQtyForSerial(selectedSerial.value ?? '').
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
///   a preloadRackStockMap() step before autofill runs.
///
/// Commit 1 fix:
///   initForEdit() now seeds selectedSerial and preserves rackController
///   text so the sheet opens with the item's existing serial and rack
///   values pre-populated (Bugs 1 & 3 from the DN item-form discrepancy
///   report).
///
/// DN-6:
///   - initForEdit() serial seed guard relaxed.
///   - captureSerialSnapshot() called after selectedSerial is seeded.
///   - initForNewItem() also calls captureSerialSnapshot() for symmetry.
///
/// Commit 7 (SharedRackField universal refactor):
///   - canBrowseRacks overridden: returns true when itemCode is non-empty.
///   - browseRacks() overridden with the full RackPickerController lifecycle.
///
/// Commit 6 (QtyFieldWithPlusMinusDelegate wiring):
///   - effectiveMaxQty overrides base: min(batchBalance, rackBalance,
///     liveRemaining) — three-way minimum per Q4 spec.
///   - adjustQty clamps to effectiveMaxQty.
///   - validateSheet writes isQtyValid.value and qtyError.value.
///   - docStatus seeded in initForEdit / reset in initForNewItem.
///
/// fix(docstatus): read from parent document, not item row.
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with SerialFieldMixin, AutoFillRackMixin, BarcodeListenerMixin, BarcodeAwareMixin {

  // ── Parent back-reference ──────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  DeliveryNoteFormController get parent => _parent;

  // ── Local reactive state ───────────────────────────────────────────────────
  final RxString itemCodeRx       = ''.obs;
  final RxString itemNameRx       = ''.obs;
  final RxString itemUomRx        = ''.obs;
  final RxString itemGroupRx      = ''.obs;
  final RxString currentVariantOf = ''.obs;

  final RxBool isExistingItem = false.obs;
  final RxInt  editingIndex   = (-1).obs;

  final RxMap<String, double> rackStockMapRx = <String, double>{}.obs;

  // ── EAN-8 barcode context (for deprecated batch label reassembly) ──────────
  /// Stores the 8-digit EAN8 barcode of the current item, set at sheet-open
  /// time by initialise(). Used by handleScan to reassemble Batch No from
  /// deprecated SHIPMENT-* label formats.
  String _itemEan8 = '';
  String get itemEan8 => _itemEan8;

  // Also pass into initForNewItem and reset in initForEdit:
  // initForNewItem: _itemEan8 already set above, no param needed
  // initForEdit: _itemEan8 = item.batchNo?.split('-').first ?? '' (or keep from initialise)

  // ── Base abstract overrides ────────────────────────────────────────────────
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

  // ── qtyInfoText / qtyInfoTooltip ───────────────────────────────────────────
  @override
  String? get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff == double.infinity) return null;
    return 'Max: ${eff.toStringAsFixed(eff.truncateToDouble() == eff ? 0 : 2)}';
  }

  @override
  final RxnString qtyInfoTooltip = RxnString(null);

  // ── QtyFieldWithPlusMinusDelegate: effectiveMaxQty ────────────────────────
  @override
  double get effectiveMaxQty {
    double? ceil;

    final batch = batchBalance.value;
    if (batch > 0) {
      ceil = (ceil == null) ? batch : (batch < ceil ? batch : ceil);
    }

    final rack = rackBalance.value;
    if (rack > 0) {
      ceil = (ceil == null) ? rack : (rack < ceil ? rack : ceil);
    }

    final serial = selectedSerial.value;
    if (serial != null && serial.isNotEmpty) {
      final cap = posItemQtyForSerial(serial);
      if (cap != double.infinity && cap > 0) {
        ceil = (ceil == null) ? cap : (cap < ceil ? cap : ceil);
      }
    }

    return ceil ?? double.infinity;
  }

  // ── SerialFieldMixin: posItemQtyForSerial override ────────────────────────
  /// Delegates to the parent controller's POS qty-cap lookup.
  /// The parent resolves serial (= idx string) → PosUploadItem.quantity.
  @override
  double posItemQtyForSerial(String serial) =>
      _parent.posQtyCapForSerial(serial);

  // ── SerialFieldMixin: sumQtyUsedForSerial override ────────────────────────
  /// Walks the parent document's in-memory items list synchronously.
  /// Excludes the row currently being edited to avoid double-counting
  /// (savedQtyForRow adds it back with the correct value).
  @override
  double sumQtyUsedForSerial(String serial) =>
      _parent.scannedQtyForSerial(
        serial,
        excludeItemName: editingItemName.value,
      );

  // ── SerialFieldMixin: savedQtyForRow override ─────────────────────────────
  /// Returns the already-saved qty of the row being edited.
  /// Used by computeLiveRemaining to undo the double-count exclusion
  /// performed by sumQtyUsedForSerial above, then subtract the live
  /// typed qty instead.
  @override
  double savedQtyForRow(String rowId) {
    final item = _parent.items.firstWhere(
      (i) => i.name == rowId,
      orElse: () => DeliveryNoteItem(
        itemCode: '', qty: 0.0, rate: 0.0,
      ),
    );
    return item.qty;
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

  // ── deleteCurrentItem ──────────────────────────────────────────────────────
  @override
  void deleteCurrentItem() {
    if (!isExistingItem.value || editingIndex.value < 0) return;
    _parent.deliveryNote.value?.items.removeAt(editingIndex.value);
    Get.back();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_parent.isClosed) _parent.deliveryNote.refresh();
    });
  }

  // ── SerialFieldMixin wiring ────────────────────────────────────────────────
  @override
  List<String> get availableSerialNos {
    final upload = _parent.posUpload.value;
    if (upload == null) return const [];
    return upload.items
        .map((e) => e.idx.toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── SerialFieldMixin: rich dropdown row metadata ──────────────────────────
  /// Resolves serial (= idx string) → PosUploadItem → SerialDropdownItem so
  /// the dropdown shows a two-line tile: item name + ×qty.
  ///
  /// Returns null when the parent has no POS Upload loaded or when the
  /// serial does not map to a known POS item — the widget falls back to the
  /// plain index badge in those cases.
  @override
  SerialDropdownItem? posDropdownItemFor(String serial) {
    final upload = _parent.posUpload.value;
    if (upload == null) return null;

    // serial == idx.toString(); find the PosUploadItem with matching idx.
    final idx = int.tryParse(serial);
    if (idx == null) return null;

    final posItem = upload.items.firstWhereOrNull((i) => i.idx == idx);
    if (posItem == null) return null;

    return SerialDropdownItem(
      serial:    serial,
      itemName:  posItem.itemName,
      qty:       posItem.quantity.toDouble(),
      remaining: liveRemaining.value,
    );
  }

  // ── Legacy name aliases ────────────────────────────────────────────────────
  RxString get itemCodeValue  => itemCodeRx;
  RxString get itemNameValue  => itemNameRx;
  RxString get itemUomValue   => itemUomRx;
  RxString get itemGroupValue => itemGroupRx;

  // ── AutoFillRackMixin wiring ───────────────────────────────────────────────
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

  // ── RackBrowseDelegate ─────────────────────────────────────────────────────
  @override
  bool get canBrowseRacks => itemCode.value.isNotEmpty;

  static const _kPickerTag = 'dn_rack_picker';

  @override
  Future<RackPickerResult?> browseRacks() async {
    if (!canBrowseRacks) return null;
    if (isValidatingRack.value) return null;

    final ctx = Get.context;
    if (ctx == null) return null;

    final pickerCtrl = Get.put(RackPickerController(), tag: _kPickerTag);

    try {
      unawaited(pickerCtrl.load(
        itemCode:     itemCode.value,
        batchNo:      batchController.text.trim(),
        warehouse:    resolvedWarehouse ?? '',
        requestedQty: double.tryParse(qtyController.text) ?? 0.0,
        currentRack:  rackController.text.trim(),
        fallbackMap:  Map<String, double>.from(rackStockMapRx),
      ));

      String? selectedRackId;

      await showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => RackPickerSheet(
          pickerTag: _kPickerTag,
          onSelected: (rack) {
            selectedRackId = rack;
          },
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
      log('[DN-Item] browseRacks error: $e', name: 'DN-Item');
      return null;
    } finally {
      if (Get.isRegistered<RackPickerController>(tag: _kPickerTag)) {
        Get.delete<RackPickerController>(tag: _kPickerTag);
      }
    }
  }

  // ── initialise() entry point ───────────────────────────────────────────────
  void initialise({
    required DeliveryNoteFormController parent,
    required String code,
    required String name,
    String?  batchNo,
    String?  scannedEan8,
    String?  variantOf,
    DeliveryNoteItem? editingItem,
  }) {
    // ── EAN-8 barcode context (for deprecated batch label reassembly) ──────────
    _itemEan8 = scannedEan8 ?? '';
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

  // ── Lifecycle / init ───────────────────────────────────────────────────────
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
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;

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
    liveRemaining.value   = 0.0;
    rackStockMapRx.clear();
    isSheetValid.value = false;
    isQtyValid.value   = false;
    qtyError.value     = '';

    removeSheetListeners();
    addSheetListeners();
    snapshotState();
    captureSerialSnapshot();

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
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;

    this.itemCode.value    = item.itemCode;
    itemCodeRx.value       = item.itemCode;
    itemNameRx.value       = item.itemName ?? '';
    itemUomRx.value        = item.uom ?? '';
    itemGroupRx.value      = item.itemGroup ?? '';
    currentVariantOf.value = variantOf;

    final existingRack  = item.rack    ?? '';
    final existingBatch = item.batchNo ?? '';
    final existingQty   = item.qty.toString();

    resetBatch();
    resetRack();

    batchController.text = existingBatch;
    rackController.text  = existingRack;
    qtyController.text   = existingQty;

    final persistedSerial = item.customInvoiceSerialNumber;
    final serials = availableSerialNos;
    if (persistedSerial != null && persistedSerial.isNotEmpty) {
      if (serials.isEmpty || serials.contains(persistedSerial)) {
        selectedSerial.value = persistedSerial;
      } else {
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

    // Seed liveRemaining at open time using the mixin formula so the badge
    // is correct before the user types anything.
    final existingQtyDouble = item.qty;
    computeLiveRemaining(
      currentTypedQty: existingQtyDouble,
      editingRowId: item.name,
    );

    rackStockMapRx.clear();
    isSheetValid.value = false;
    isQtyValid.value   = false;
    qtyError.value     = '';

    removeSheetListeners();
    addSheetListeners();
    snapshotState();
    captureSerialSnapshot();

    if (existingBatch.isNotEmpty) {
      validateBatchOnInit(existingBatch);
    }
    if (existingRack.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateRack(existingRack);
      });
    }
  }

  // ── Sheet validity ─────────────────────────────────────────────────────────
  @override
  void validateSheet() {
    final qty  = double.tryParse(qtyController.text);
    final ceil = effectiveMaxQty;
    final qtyOk  = qty != null && qty > 0;
    final ceilOk = ceil == double.infinity || (qty != null && qty <= ceil);

    if (!qtyOk) {
      isQtyValid.value = false;
      qtyError.value   = qty == null ? '' : 'Enter a quantity greater than 0';
    } else if (!ceilOk) {
      isQtyValid.value = false;
      final ceilStr = ceil.toStringAsFixed(
          ceil.truncateToDouble() == ceil ? 0 : 2);
      qtyError.value = 'Qty cannot exceed $ceilStr';
    } else {
      isQtyValid.value = true;
      qtyError.value   = '';
    }

    isSheetValid.value = isBatchValid.value && qtyOk && ceilOk;

    // Update live-remaining badge via mixin formula.
    computeLiveRemaining(
      currentTypedQty: qty ?? 0.0,
      editingRowId: editingItemName.value,
    );
  }

  // ── submit ─────────────────────────────────────────────────────────────────
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
    } else {
      _parent.deliveryNote.value?.items.add(item);
    }

    // ✅ Defer the Rx notification to the NEXT frame so the sheet's
    // exit animation completes before the parent list rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_parent.isClosed) _parent.deliveryNote.refresh();
    });
  }

  // ── Rack-map preload for AutoFillRack / RackPicker ─────────────────────────
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

  // ── BarcodeAwareMixin: handleScan override for deprecated batch labels ──────
  /// The base BarcodeAwareMixin.handleScan handles current-format scans
  /// ('20003609-ESU') correctly — ean is non-empty so raw is used as-is.
  ///
  /// This override adds handling for deprecated SHIPMENT-* formats and plain
  /// Batch ID scans where no EAN8 prefix is present in the scanned string.
  /// The Batch ID is extracted and prepended with the stored _itemEan8 to
  /// form the correct Batch No ('20003609-ESU').
  @override
  Future<void> handleScan(String raw) async {
    // ── Rack-first gate (your rule) ──────────────────────────────────────────
    // If the first hyphen-delimited token is neither an 8-digit numeric EAN-8
    // nor the deprecated "SHIPMENT" prefix, it is a rack asset code.
    // Route immediately — do NOT pass through splitEanBatch or _extractBatchId.
    final firstToken = raw.split('-').first;
    final isEan8     = firstToken.length == 8 && int.tryParse(firstToken) != null;
    final isShipment = firstToken.toUpperCase() == 'SHIPMENT';

    if (!isEan8 && !isShipment && raw.contains('-')) {
      applyRackScan(raw);
      return;
    }

    // ── Batch paths (unchanged) ───────────────────────────────────────────────
    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);

    if (ean.isNotEmpty) {
      // Current format: raw is the full Batch No (e.g. '20003609-ESU').
      batchController.text = raw;
      await validateBatch(raw);
      return;
    }

    // Deprecated SHIPMENT-* format: extract Batch ID and prepend item EAN-8.
    final extractedId = _extractBatchId(raw);
    final fullBatchNo = _itemEan8.isNotEmpty
        ? '$_itemEan8-$extractedId'
        : extractedId;

    batchController.text = fullBatchNo;
    await validateBatch(fullBatchNo);
  }

  /// Splits [raw] on '-', discards the literal token 'SHIPMENT' (any case),
  /// and discards any token shorter than 3 characters.
  /// Returns the first surviving token, or [raw] unchanged if none survive.
  ///
  /// Examples:
  ///   'SHIPMENT-ESU'       → 'ESU'
  ///   'SHIPMENT-24-ESU'    → 'ESU'  (discards '24' — length < 3)
  ///   'SHIPMENT-24-ESU-1'  → 'ESU'  (discards '24' and '1')
  ///   'ESU'                → 'ESU'  (no hyphens, passes through as-is via
  ///                                   the ean.isNotEmpty guard above, so
  ///                                   this method is only called for
  ///                                   hyphenated SHIPMENT-* strings in
  ///                                   practice — but handles plain too)
  String _extractBatchId(String raw) {
    final candidates = raw.split('-').where((p) =>
    p.toUpperCase() != 'SHIPMENT' &&
        p.length >= 3
    ).toList();
    return candidates.isNotEmpty ? candidates.first : raw;
  }

  // ── BarcodeAwareMixin: applyRackScan ─────────────────────────────────────
  /// Called by BarcodeAwareMixin._routeScan when the scan pattern matches a
  /// rack barcode (KA-WH-DXB1-101A), either after batch is valid or before.
  ///
  /// Writes the rack name to [rackController] and triggers [validateRack]
  /// for API confirmation (fetches rack balance, sets isRackValid).
  @override
  void applyRackScan(String code) {
    rackController.text = code;
    validateRack(code);   // base-class API round-trip — sets isRackValid + rackBalance
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
