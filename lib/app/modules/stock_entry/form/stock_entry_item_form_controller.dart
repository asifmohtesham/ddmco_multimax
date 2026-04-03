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
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

/// Item-level sheet controller for Stock Entry.
///
/// Commit P3-3:
///   • [openBatchPicker]  → overrides base; pre-fetches [batchWiseHistory]
///     before delegating to [ItemSheetControllerBase.openBatchPicker].
///
/// Commit C-2:
///   • [qtyInfoText]    → 'Max: N' (binding ceiling) or 'Max: -' (no ceiling).
///   • [qtyInfoTooltip] → '·'-separated breakdown of active ceilings.
///
/// Commit 2 (compiler fix):
///   • Removed duplicate liveRemaining / qtyInfoTooltip field declarations
///     (both now live in ItemSheetControllerBase).
///   • Removed broken 'bool get isSheetLoading' override.
///   • isSheetValid is now written via isSheetValid.value in validateSheet().
///   • Implemented abstract members: isAddMode, sheetScanController,
///     adjustQty, deleteCurrentItem.
class StockEntryItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {

  // ── Parent back-reference ──────────────────────────────────────────────────
  final StockEntryFormController _parent;
  StockEntryItemFormController(this._parent);

  StockEntryFormController get parent => _parent;

  // ── Abstract overrides ──────────────────────────────────────────────────
  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override bool get requiresBatch => true;
  @override bool get requiresRack  => false;
  @override Color get accentColor  => Colors.purple;

  /// true when opening the sheet to add a new item (not editing an existing one).
  @override
  bool get isAddMode => editingItemName.value == null;

  /// Scanner controller for the sheet scan footer; SE supports scanning.
  @override
  MobileScannerController? get sheetScanController => null; // wired per-sheet if needed

  // ── Batch-wise history (for BatchPickerSheet) ──────────────────────────
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

  // ── P3-3: openBatchPicker override ───────────────────────────────────────────
  @override
  Future<void> openBatchPicker() async {
    if (batchWiseHistory.isEmpty && !isLoadingBatchHistory.value) {
      unawaited(fetchBatchWiseHistory());
    }
    await super.openBatchPicker();
  }

  // ── POS serial mixin wiring ──────────────────────────────────────────────
  @override PosUploadModel? get posUpload => _parent.posUpload.value;
  @override List<dynamic>   get posItems  => _parent.posItems;

  // ── PosSerialMixin: availableSerialNos ──────────────────────────────────────
  @override
  List<String> get availableSerialNos {
    // Derive from posItems if available; fallback to empty list.
    if (posUpload == null) return const [];
    return posItems
        .map((e) => (e['serial_no'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── Derived / computed ────────────────────────────────────────────────────
  // NOTE: liveRemaining and qtyInfoTooltip are declared in
  // ItemSheetControllerBase — do NOT re-declare them here.

  String get posSerialCapText {
    final cap = posSerialQtyCap;
    if (cap == null) return '';
    return 'Serial: $cap';
  }

  @override
  String get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff == null) return 'Max: -';
    return 'Max: ${eff.toStringAsFixed(eff.truncateToDouble() == eff ? 0 : 2)}';
  }

  /// Returns the base field declared in ItemSheetControllerBase.
  @override
  RxnString get qtyInfoTooltip => super.qtyInfoTooltip;

  // Narrowest ceiling: POS serial → batch balance → rack balance → MR qty.
  double? get effectiveMaxQty {
    double? ceil;
    final serial = posSerialQtyCap?.toDouble();
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

  // ── State ──────────────────────────────────────────────────────────────
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

  // ── AutoFillRackMixin wiring ──────────────────────────────────────────────
  @override String  get mixinItemCode  => itemCode.value;
  @override String? get mixinWarehouse => resolvedWarehouse;
  @override String  get mixinBatch     => batchController.text;
  @override double  get mixinQty       => double.tryParse(qtyController.text) ?? 0.0;
  @override Map<String, double> get rackStockMap => _rackStockMap;

  final Map<String, double> _rackStockMap = {};

  @override
  void onRackAutoFilled(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  // ── Dual-rack state ──────────────────────────────────────────────────────────
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

  // ── Sheet-valid gate (writes RxBool in validateSheet) ────────────────────────
  // isSheetLoading override REMOVED — base field is already RxBool.
  // isSheetValid getter REMOVED — written via isSheetValid.value in validateSheet().

  @override
  void validateSheet() {
    // ─ validity ───────────────────────────────────────────────────────────
    final qty  = double.tryParse(qtyController.text);
    final ceil = effectiveMaxQty;
    final valid = isBatchValid.value &&
        qty != null && qty > 0 &&
        (ceil == null || qty <= ceil);
    isSheetValid.value = valid;

    // ─ liveRemaining ─────────────────────────────────────────────────────
    final qtyVal = qty ?? 0.0;
    liveRemaining.value = (ceil != null) ? (ceil - qtyVal).clamp(0.0, ceil) : 0.0;

    // ─ tooltip breakdown ───────────────────────────────────────────────────
    final parts = <String>[];
    final serial = posSerialQtyCap;
    if (serial != null) parts.add('Serial: $serial');
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

  // ── deleteCurrentItem (abstract impl) ──────────────────────────────────────
  @override
  void deleteCurrentItem() {
    final rowId = editingItemName.value;
    if (rowId == null) return;
    _parent.removeItemByRowId(rowId);
    Get.back();
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

  // ── Init helpers ──────────────────────────────────────────────────────────────
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

    batchController.text = item.batchNo ?? '';
    rackController.text  = item.rack    ?? '';
    qtyController.text   = item.qty.toString();

    final mrMatch = mrReferenceItems.firstWhereOrNull(
      (r) => r['item_code'] == item.itemCode,
    );
    if (mrMatch != null) {
      linkMrItem(
        mrName:   mrMatch['parent']   as String? ?? '',
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
        if (!isClosed) validateRack(item.rack!);
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

  // ── submit ───────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Invalid quantity');
    _parent.addOrUpdateItem(
      itemCode:  itemCode.value,
      itemName:  itemName.value,
      uom:       uom.value,
      qty:       qty,
      batchNo:   isBatchValid.value ? batchController.text : null,
      rack:      isRackValid.value  ? rackController.text  : null,
      mrName:    _mrName,
      mrItemName: _mrItemName,
    );
  }

  // ── Rack validation override (uses rackStockMap) ─────────────────────────
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
    rackController.text = rackId;
    validateRack(rackId);
  }

  // ── Snackbar helpers ────────────────────────────────────────────────────────
  void showError(String msg)   => GlobalSnackbar.error(msg);
  void showSuccess(String msg) => GlobalSnackbar.success(msg);
}
