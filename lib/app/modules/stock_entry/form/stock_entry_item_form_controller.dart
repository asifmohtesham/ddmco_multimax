import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/models/batch_wise_balance_row.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_pos_serial.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_autofill_rack.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

/// Item-level sheet controller for Stock Entry.
///
/// Commit 4 (compiler fix):
///   • resolvedWarehouse now reads selectedFromWarehouse.value.
///   • POS wiring re-done: availableSerialNos derives from
///     _parent.posUploadSerialOptions; serial ceiling reads
///     _parent.remainingQtyForSerial(selectedSerial.value).
///   • deleteCurrentItem delegates to _parent.confirmAndDeleteItem().
///   • submit() delegates to _parent.updateItemLocally() / addItemLocally()
///     with the correct signatures.
///   • autoFillRackController / onAutoFillRackSelected wired to the
///     dual-rack sourceRackController / validateDualRack per mixin docs.
///
/// Commit 7:
///   • validateSheet() now gates on isSourceRackValid for SE types that
///     require a source rack (Material Issue / Transfer / Transfer for Mfg).
///   • validateDualRack() clears rackError on success for both sides.
class StockEntryItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {

  // ── Parent back-reference ──────────────────────────────────────────────────
  late StockEntryFormController _parent;

  StockEntryFormController get parent => _parent;

  // ── Abstract overrides ────────────────────────────────────────────────────

  /// Source warehouse for this item — drives batch-balance and rack-autofill.
  ///
  /// Uses the header-level selectedFromWarehouse; individual item rows may
  /// carry their own sWarehouse but the sheet always operates against the
  /// header for consistency.
  @override
  String? get resolvedWarehouse => _parent.selectedFromWarehouse.value;

  @override bool get requiresBatch => true;
  @override bool get requiresRack  => false;
  @override Color get accentColor  => Colors.purple;

  /// true when the sheet was opened for a new item (not editing).
  @override
  bool get isAddMode => editingItemName.value == null;

  /// SE does not embed an in-sheet camera scanner; returns null.
  @override
  MobileScannerController? get sheetScanController => null;

  // ── Batch-wise history (for BatchPickerSheet) ──────────────────────────────
  final RxList<BatchWiseBalanceRow> _batchWiseHistory = <BatchWiseBalanceRow>[].obs;
  @override List<BatchWiseBalanceRow> get batchWiseHistory => _batchWiseHistory;

  final RxBool _isLoadingBatchHistory = false.obs;
  @override RxBool get isLoadingBatchHistory => _isLoadingBatchHistory;

  @override
  Future<void> fetchBatchWiseHistory() async {
    if (_isLoadingBatchHistory.value) return;
    _isLoadingBatchHistory.value = true;
    try {
      final rows = await ApiProvider().getBatchWiseBalance(
        itemCode:  itemCode.value,
        warehouse: resolvedWarehouse,
      );
      _batchWiseHistory.assignAll(
        rows.map((r) => BatchWiseBalanceRow.fromMap(r)).toList(),
      );
    } catch (e) {
      log('[SE-Item] fetchBatchWiseHistory error: $e', name: 'SE-Item');
    } finally {
      _isLoadingBatchHistory.value = false;
    }
  }

  // ── openBatchPicker override ───────────────────────────────────────────────
  @override
  Future<void> openBatchPicker() async {
    if (batchWiseHistory.isEmpty && !isLoadingBatchHistory.value) {
      unawaited(fetchBatchWiseHistory());
    }
    await super.openBatchPicker();
  }

  // ── PosSerialMixin: availableSerialNos ─────────────────────────────────────
  /// Derives from the parent's posUploadSerialOptions RxList<String> which is
  /// populated by StockEntryFormController.fetchPosUpload().
  @override
  List<String> get availableSerialNos => _parent.posUploadSerialOptions;

  // ── AutoFillRackMixin hooks ────────────────────────────────────────────────

  /// Autofill writes the source rack, not the generic rackController.
  @override
  TextEditingController get autoFillRackController => sourceRackController;

  /// After autofill, validate as source rack (isSource = true).
  @override
  void onAutoFillRackSelected(String rack) => validateDualRack(rack, true);

  @override
  Map<String, double> get rackStockMap => _rackStockMap;

  // ── Dual-rack state ────────────────────────────────────────────────────────
  final TextEditingController sourceRackController = TextEditingController();
  final RxBool isSourceRackValid       = false.obs;
  final RxBool isValidatingSourceRack  = false.obs;

  final TextEditingController targetRackController = TextEditingController();
  final RxBool isTargetRackValid       = false.obs;
  final RxBool isValidatingTargetRack  = false.obs;

  final RxBool isLoadingRackBalance    = false.obs;

  final RxnString itemSourceWarehouse    = RxnString(null);
  final RxnString derivedSourceWarehouse = RxnString(null);
  final RxnString itemTargetWarehouse    = RxnString(null);
  final RxnString derivedTargetWarehouse = RxnString(null);

  final Map<String, double> _rackStockMap = {};

  void resetSourceRackValidation() {
    sourceRackController.clear();
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
  }

  void resetTargetRackValidation() {
    targetRackController.clear();
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
  }

  Future<void> validateDualRack(String rack, bool isSource) async {
    if (rack.isEmpty) {
      if (isSource) { resetSourceRackValidation(); } else { resetTargetRackValidation(); }
      return;
    }
    if (isSource) {
      isValidatingSourceRack.value = true;
      isSourceRackValid.value      = false;
    } else {
      isValidatingTargetRack.value = true;
      isTargetRackValid.value      = false;
    }
    try {
      if (isSource) {
        isLoadingRackBalance.value = true;
        if (_rackStockMap.containsKey(rack)) {
          rackBalance.value = _rackStockMap[rack]!;
        } else {
          await fetchRackBalance(rack);
        }
        isLoadingRackBalance.value = false;
        isSourceRackValid.value    = true;
      } else {
        isTargetRackValid.value = true;
      }
      // Commit 7: clear any stale rack error on success.
      rackError.value = '';
    } catch (e) {
      rackError.value = 'Rack validation error: $e';
      log('[SE-Item] validateDualRack error: $e', name: 'SE-Item');
      isLoadingRackBalance.value = false;
    } finally {
      if (isSource) { isValidatingSourceRack.value = false; }
      else          { isValidatingTargetRack.value = false; }
    }
  }

  @override
  void onClose() {
    try { sourceRackController.dispose(); } catch (_) {}
    try { targetRackController.dispose(); } catch (_) {}
    super.onClose();
  }

  // ── Derived / computed ─────────────────────────────────────────────────────

  /// POS serial qty ceiling: remaining capacity under the selected serial,
  /// or null when no POS context or no serial is selected.
  double? get _posSerialCeiling {
    final serial = selectedSerial.value;
    if (serial == null || serial.isEmpty) return null;
    if (_parent.posUpload.value == null) return null;
    final remaining = _parent.remainingQtyForSerial(serial);
    return remaining == double.infinity ? null : remaining;
  }

  @override
  String get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff == null) return 'Max: -';
    return 'Max: ${eff.toStringAsFixed(eff.truncateToDouble() == eff ? 0 : 2)}';
  }

  @override
  RxnString get qtyInfoTooltip => super.qtyInfoTooltip;

  /// Narrowest ceiling: POS serial → batch balance → rack balance → MR qty.
  double? get effectiveMaxQty {
    double? ceil;
    final serial = _posSerialCeiling;
    if (serial != null) ceil = serial;
    final batch = batchBalance.value;
    if (batch > 0) {
      ceil = (ceil == null) ? batch : (batch < ceil ? batch : ceil);
    }
    final rack = rackBalance.value;
    if (rack > 0) {
      ceil = (ceil == null) ? rack : (rack < ceil ? rack : ceil);
    }
    final mr = _mrQty;
    if (mr != null && mr > 0) {
      ceil = (ceil == null) ? mr : (mr < ceil ? mr : ceil);
    }
    return ceil;
  }

  @override
  double get maxQty => effectiveMaxQty ?? 0.0;

  // ── State ──────────────────────────────────────────────────────────────────
  var uom              = ''.obs;
  var itemGroup        = ''.obs;
  var isBatchedItem    = false.obs;
  var isSerialisedItem = false.obs;
  var isEditingExisting = false.obs;
  String? editingOriginalBatch;

  // MR-link state
  String? _mrName;
  String? _mrItemName;
  double? _mrQty;
  String? _mrUom;
  String? _mrBatch;

  // ── Whether this SE type requires a source rack ───────────────────────────
  ///
  /// Commit 7: used by validateSheet() to gate Save on source-rack validity
  /// for outbound and transfer SE types.
  bool get _requiresSourceRack {
    final t = _parent.selectedStockEntryType.value;
    return t == 'Material Issue' ||
        t == 'Material Transfer' ||
        t == 'Material Transfer for Manufacture';
  }

  // ── Sheet-valid gate ───────────────────────────────────────────────────────

  @override
  void validateSheet() {
    final qty  = double.tryParse(qtyController.text);
    final ceil = effectiveMaxQty;

    // Commit 7: require a valid source rack for outbound / transfer types.
    final rackOk = !_requiresSourceRack || isSourceRackValid.value;

    final valid = isBatchValid.value &&
        qty != null && qty > 0 &&
        (ceil == null || qty <= ceil) &&
        rackOk;
    isSheetValid.value = valid;

    final qtyVal = qty ?? 0.0;
    liveRemaining.value = (ceil != null) ? (ceil - qtyVal).clamp(0.0, ceil) : 0.0;

    final parts = <String>[];
    final serial = _posSerialCeiling;
    if (serial != null) parts.add('Serial: ${serial.toStringAsFixed(0)}');
    final batchBal = batchBalance.value;
    if (batchBal > 0) parts.add('Batch: ${batchBal.toStringAsFixed(0)}');
    final rackBal = rackBalance.value;
    if (rackBal > 0) parts.add('Rack: ${rackBal.toStringAsFixed(0)}');
    final mr = _mrQty;
    if (mr != null && mr > 0) parts.add('MR: ${mr.toStringAsFixed(0)}');
    super.qtyInfoTooltip.value = parts.isEmpty ? null : parts.join('  ·  ');
  }

  // ── adjustQty (abstract impl) ──────────────────────────────────────────────
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, double.infinity);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem (abstract impl) ─────────────────────────────────────
  @override
  void deleteCurrentItem() {
    final rowId = editingItemName.value;
    if (rowId == null) return;
    final item = _parent.stockEntry.value?.items
        .firstWhereOrNull((i) => i.name == rowId);
    if (item == null) return;
    _parent.confirmAndDeleteItem(item);
  }

  // ── MR link ───────────────────────────────────────────────────────────────
  void linkMrItem({
    required String mrName,
    required String itemName,
    required double qty,
    required String uom,
    String? batchNo,
  }) {
    _mrName     = mrName;
    _mrItemName = itemName;
    _mrQty      = qty;
    _mrUom      = uom;
    _mrBatch    = batchNo;
  }

  void clearMrLink() {
    _mrName = _mrItemName = _mrUom = _mrBatch = null;
    _mrQty  = null;
  }

  String? get mrName     => _mrName;
  String? get mrItemName => _mrItemName;
  double? get mrQty      => _mrQty;
  String? get mrUom      => _mrUom;
  String? get mrBatch    => _mrBatch;

  // ── Init helpers ───────────────────────────────────────────────────────────
  void initForItem({
    required String code,
    required String name,
    required String uomValue,
    required String group,
    required bool   hasBatch,
    required bool   hasSerial,
  }) {
    itemCode.value         = code;
    itemName.value         = name;
    uom.value              = uomValue;
    itemGroup.value        = group;
    isBatchedItem.value    = hasBatch;
    isSerialisedItem.value = hasSerial;
  }

  void initForNewItem() {
    editingItemName.value    = null;
    isEditingExisting.value  = false;
    editingOriginalBatch     = null;
    clearMrLink();
    batchController.clear();
    rackController.clear();
    qtyController.clear();
    sourceRackController.clear();
    targetRackController.clear();
    isBatchValid.value    = false;
    isBatchReadOnly.value = false;
    batchError.value      = '';
    batchInfoTooltip.value = null;
    isRackValid.value     = false;
    rackError.value       = '';
    batchBalance.value    = 0.0;
    rackBalance.value     = 0.0;
    liveRemaining.value   = 0.0;
    isSheetValid.value    = false;
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
    isLoadingRackBalance.value   = false;
    _batchWiseHistory.clear();
  }

  void _loadExistingItem(
    StockEntryItem item,
    List<Map<String, dynamic>> mrReferenceItems,
  ) {
    isEditingExisting.value = true;
    editingOriginalBatch    = item.batchNo;
    editingItemName.value   = item.name;

    batchController.text        = item.batchNo ?? '';
    rackController.text         = item.rack    ?? '';
    sourceRackController.text   = item.rack    ?? '';
    targetRackController.text   = item.toRack  ?? '';
    qtyController.text          = item.qty.toString();

    // Restore selected POS serial if present.
    if (item.customInvoiceSerialNumber != null &&
        item.customInvoiceSerialNumber != '0') {
      selectedSerial.value = item.customInvoiceSerialNumber;
    }

    final mrMatch = mrReferenceItems.firstWhereOrNull(
      (r) => r['item_code'] == item.itemCode,
    );
    if (mrMatch != null) {
      linkMrItem(
        mrName:   mrMatch['parent']    as String? ?? '',
        itemName: mrMatch['item_name'] as String? ?? '',
        qty:      (mrMatch['qty'] as num?)?.toDouble() ?? 0.0,
        uom:      mrMatch['uom']       as String? ?? '',
        batchNo:  mrMatch['batch_no']  as String?,
      );
    }

    if (item.batchNo != null && item.batchNo!.isNotEmpty) {
      validateBatchOnInit(item.batchNo!);
    }
    if (item.rack != null && item.rack!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateDualRack(item.rack!, true);
      });
    }
    if (item.toRack != null && item.toRack!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateDualRack(item.toRack!, false);
      });
    }
  }

  Future<void> prepareForItem({
    required String itemCode,
    required String itemName,
    required String uom,
    required String itemGroup,
    required bool   hasBatch,
    required bool   hasSerial,
    StockEntryItem? existingItem,
    List<Map<String, dynamic>> mrReferenceItems = const [],
    String? scannedBatch,
  }) async {
    initForItem(
      code:      itemCode,
      name:      itemName,
      uomValue:  uom,
      group:     itemGroup,
      hasBatch:  hasBatch,
      hasSerial: hasSerial,
    );

    if (existingItem != null) {
      _loadExistingItem(existingItem, mrReferenceItems);
    } else {
      initForNewItem();
      if (scannedBatch != null && scannedBatch.isNotEmpty) {
        batchController.text = scannedBatch;
        validateBatchOnInit(scannedBatch);
      }
    }

    addSheetListeners();
    snapshotState();
  }

  /// Public entry point called by StockEntryFormController to wire the parent
  /// reference and start item initialisation in one step.
  ///
  /// This replaces the constructor-injection pattern so that GetX can
  /// instantiate the controller with [Get.put(StockEntryItemFormController())]
  /// and the parent wiring happens lazily.
  Future<void> initialise({
    required StockEntryFormController parent,
    required String code,
    required String name,
    String variantOf          = '',
    String itemName           = '',
    String? batchNo,
    StockEntryItem? editingItem,
    List<Map<String, dynamic>> mrReferenceItems = const [],
    String scannedEan8        = '',
  }) async {
    _parent = parent;

    // Fetch item metadata from the ERPNext Item doctype.
    String uomValue   = 'Nos';
    String group      = '';
    bool   hasBatch   = false;
    bool   hasSerial  = false;

    try {
      final meta = await ApiProvider().getDocument('Item', code);
      if (meta.statusCode == 200 && meta.data['data'] != null) {
        final d  = meta.data['data'] as Map<String, dynamic>;
        uomValue  = d['stock_uom']       as String? ?? 'Nos';
        group     = d['item_group']      as String? ?? '';
        hasBatch  = (d['has_batch_no']   as int?)    == 1;
        hasSerial = (d['has_serial_no']  as int?)    == 1;
      }
    } catch (e) {
      log('[SE-Item] initialise: failed to fetch item meta: $e', name: 'SE-Item');
    }

    await prepareForItem(
      itemCode:         code,
      itemName:         itemName,
      uom:              uomValue,
      itemGroup:        group,
      hasBatch:         hasBatch,
      hasSerial:        hasSerial,
      existingItem:     editingItem,
      mrReferenceItems: mrReferenceItems,
      scannedBatch:     batchNo,
    );

    // Store scanned EAN8 for in-sheet scan context.
    if (scannedEan8.isNotEmpty) currentScannedEan = scannedEan8;

    // Kick off rack-stock pre-load for autofill (non-blocking).
    unawaited(_preloadRackStockMap());
  }

  Future<void> _preloadRackStockMap() async {
    try {
      final rows = await ApiProvider().getStockBalanceWithDimension(
        itemCode:  itemCode.value,
        warehouse: resolvedWarehouse,
      );
      final map = <String, double>{};
      for (final r in rows) {
        final rack = r['custom_rack'] as String?;
        final qty  = (r['qty'] as num?)?.toDouble() ?? 0.0;
        if (rack != null && rack.isNotEmpty) map[rack] = qty;
      }
      seedRackStockMap(map);
    } catch (e) {
      log('[SE-Item] _preloadRackStockMap error: $e', name: 'SE-Item');
    }
  }

  // ── submit ─────────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Invalid quantity');

    final batch      = isBatchValid.value ? batchController.text : null;
    final srcRack    = isSourceRackValid.value ? sourceRackController.text : null;
    final tgtRack    = isTargetRackValid.value ? targetRackController.text : null;
    final serial     = selectedSerial.value;

    // Resolve warehouses: prefer item-level if known, else header.
    final sWh = itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value;
    final tWh = itemTargetWarehouse.value ?? _parent.selectedToWarehouse.value;

    final rowId = editingItemName.value;
    if (rowId != null) {
      _parent.updateItemLocally(
        rowId, qty, batch, srcRack, tgtRack, sWh, tWh, serial,
      );
    } else {
      _parent.addItemLocally(
        qty, batch, srcRack, tgtRack, sWh, tWh, serial,
      );
    }
  }

  // ── Rack validation override (uses rackStockMap cache) ────────────────────
  @override
  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) { resetRack(); return; }
    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;
    try {
      if (_rackStockMap.containsKey(rack)) {
        rackBalance.value = _rackStockMap[rack]!;
      } else {
        await fetchRackBalance(rack);
      }
      isRackValid.value = true;
    } catch (e) {
      rackError.value = 'Rack validation error: $e';
    } finally {
      isValidatingRack.value = false;
    }
  }

  void seedRackStockMap(Map<String, double> map) {
    _rackStockMap
      ..clear()
      ..addAll(map);
  }

  void applyRackScan(String rackId) {
    // Determine target: if source rack not yet set, fill source; else target.
    if (sourceRackController.text.isEmpty) {
      sourceRackController.text = rackId;
      validateDualRack(rackId, true);
    } else {
      targetRackController.text = rackId;
      validateDualRack(rackId, false);
    }
  }

  /// True when the sheet is awaiting a rack scan (no source rack set yet).
  bool get needsRackScanFallback => sourceRackController.text.isEmpty;

  // ── Snackbar helpers ───────────────────────────────────────────────────────
  void showError(String msg)   => GlobalSnackbar.error(msg);
  void showSuccess(String msg) => GlobalSnackbar.success(msg);
}
