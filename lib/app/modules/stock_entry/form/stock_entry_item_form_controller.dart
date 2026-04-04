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
import 'package:multimax/app/shared/item_sheet/dual_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
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
/// Commit 5 (compiler fix):
///   • Add currentScannedEan String field (used by initialise() and
///     _openNewItemSheet in parent; not on base or any mixin).
///   • Remove redundant qtyInfoTooltip getter override — base RxnString is
///     the single source of truth; validateSheet() writes it correctly via
///     super.qtyInfoTooltip.value and SharedBatchField reads the same ref.
///   • Fix showError / showSuccess: use named `message:` param as required
///     by GlobalSnackbar.
///
/// Commit 7:
///   • validateSheet() now gates on isSourceRackValid for SE types that
///     require a source rack (Material Issue / Transfer / Transfer for Mfg).
///   • validateDualRack() clears rackError on success for both sides.
///
/// Commit 8:
///   • Implements [DualRackDelegate] — additive; no members change.
///     SharedDualRackSection now depends on the narrow interface rather than
///     this concrete class.
///
/// Commit 9 (build-2):
///   • Wires [RackFieldWithBrowseDelegate] picker flow: overrides
///     [canBrowseRacks], [browseRacks], and [handleRackPicked] with the
///     full SE-flavoured rack picker implementation so the shelves-icon
///     button in SharedRackField(editMode:true) becomes live for SE.
///   • fix: RackPickerResult now requires `availableQty`; pass 0.0 in the
///     onSelected callback — handleRackPicked calls validateRack() which
///     overwrites rackBalance with the live authoritative value before it
///     is ever read, so the 0.0 snapshot is never consumed.
class StockEntryItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin
    implements DualRackDelegate {

  // ── Parent back-reference ──────────────────────────────────────────────────────
  late StockEntryFormController _parent;

  StockEntryFormController get parent => _parent;

  // ── In-sheet scan context ───────────────────────────────────────────────
  String currentScannedEan = '';

  // ── Abstract overrides ─────────────────────────────────────────────────
  @override
  String? get resolvedWarehouse => _parent.selectedFromWarehouse.value;

  @override bool get requiresBatch => true;
  @override bool get requiresRack  => false;
  @override Color get accentColor  => Colors.purple;

  @override
  bool get isAddMode => editingItemName.value == null;

  @override
  MobileScannerController? get sheetScanController => null;

  // ── RackFieldWithBrowseDelegate: picker flow (Commit 9) ──────────────────

  /// Returns true when the picker preconditions are satisfied:
  ///   • itemCode is non-empty (item has been selected)
  ///   • resolvedWarehouse is non-null (source warehouse is known)
  @override
  bool get canBrowseRacks =>
      itemCode.value.isNotEmpty && resolvedWarehouse != null;

  /// Opens the rack picker sheet for the single-rack (non-dual) flow.
  ///
  /// Lifecycle mirrors [SharedDualRackSection._openRackPicker]:
  ///   1. Register a scoped [RackPickerController] with a timestamped tag.
  ///   2. Fire [RackPickerController.load] (non-blocking) with a snapshot
  ///      of [_rackStockMap] as fallbackMap.
  ///   3. Present [RackPickerSheet] via Get.bottomSheet.
  ///   4. Deferred-delete the controller in a post-frame callback.
  ///   5. Return [RackPickerResult] from the selected entry, or null.
  @override
  Future<RackPickerResult?> browseRacks() async {
    final tag = 'rack_picker_se_single_'
        '${DateTime.now().microsecondsSinceEpoch}';

    final ctrl = Get.put(RackPickerController(), tag: tag);

    unawaited(ctrl.load(
      itemCode:     itemCode.value,
      batchNo:      batchController.text.trim(),
      warehouse:    resolvedWarehouse ?? '',
      requestedQty: double.tryParse(qtyController.text) ?? 0.0,
      currentRack:  rackController.text.trim(),
      // Snapshot of the live rackStockMap so the Available Rack Balance
      // sheet is populated for non-batch items / before the batch-ledger
      // API returns data. Matches the fallbackMap pattern in
      // SharedDualRackSection._openRackPicker.
      fallbackMap:  Map<String, double>.from(_rackStockMap),
    ));

    RackPickerResult? result;

    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          // availableQty: 0.0 — the onSelected callback receives only the
          // rack String, not the full RackPickerEntry qty.  handleRackPicked
          // calls validateRack() immediately after, which writes the live
          // authoritative balance into rackBalance.value before it is read.
          result = RackPickerResult(rackId: rack, availableQty: 0.0);
        },
      ),
      isScrollControlled: true,
    );

    // Deferred delete: one frame so in-flight Obx rebuilds drain before
    // the controller is removed from the registry (prevents 'not found'
    // crash on the final rebuild triggered by onSelected).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    });

    return result;
  }

  /// SE post-pick hook: writes the selected rack into [rackController] and
  /// fires [validateRack]. Declared explicitly so the @override annotation
  /// documents the intentional standard behaviour and future SE-specific
  /// post-pick logic can be added here without touching the base class.
  @override
  Future<void> handleRackPicked(RackPickerResult result) async {
    rackController.text = result.rackId;
    await validateRack(result.rackId);
  }

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

  // ── PosSerialMixin: availableSerialNos ─────────────────────────────────────────
  @override
  List<String> get availableSerialNos => _parent.posUploadSerialOptions;

  // ── AutoFillRackMixin hooks ────────────────────────────────────────────────
  @override
  TextEditingController get autoFillRackController => sourceRackController;

  @override
  void onAutoFillRackSelected(String rack) => validateDualRack(rack, true);

  @override
  Map<String, double> get rackStockMap => _rackStockMap;

  // ── Dual-rack state ──────────────────────────────────────────────────────────
  @override final TextEditingController sourceRackController = TextEditingController();
  @override final RxBool isSourceRackValid       = false.obs;
  @override final RxBool isValidatingSourceRack  = false.obs;

  @override final TextEditingController targetRackController = TextEditingController();
  @override final RxBool isTargetRackValid       = false.obs;
  @override final RxBool isValidatingTargetRack  = false.obs;

  @override final RxBool isLoadingRackBalance    = false.obs;

  @override final RxnString itemSourceWarehouse    = RxnString(null);
  @override final RxnString derivedSourceWarehouse = RxnString(null);
  @override final RxnString itemTargetWarehouse    = RxnString(null);
  @override final RxnString derivedTargetWarehouse = RxnString(null);

  final Map<String, double> _rackStockMap = {};

  // ── DualRackDelegate: parent warehouse accessors ─────────────────────────
  @override
  RxnString get selectedFromWarehouse => _parent.selectedFromWarehouse;

  @override
  RxnString get selectedToWarehouse => _parent.selectedToWarehouse;

  @override
  RxString get selectedStockEntryType => _parent.selectedStockEntryType;

  // ── Dual-rack actions ──────────────────────────────────────────────────────
  @override
  void resetSourceRackValidation() {
    sourceRackController.clear();
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
  }

  @override
  void resetTargetRackValidation() {
    targetRackController.clear();
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
  }

  @override
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

  // ── Derived / computed ────────────────────────────────────────────────────────
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

  // ── Whether this SE type requires a source rack ──────────────────────────
  bool get _requiresSourceRack {
    final t = _parent.selectedStockEntryType.value;
    return t == 'Material Issue' ||
        t == 'Material Transfer' ||
        t == 'Material Transfer for Manufacture';
  }

  // ── Sheet-valid gate ────────────────────────────────────────────────────────
  @override
  void validateSheet() {
    final qty  = double.tryParse(qtyController.text);
    final ceil = effectiveMaxQty;

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
    qtyInfoTooltip.value = parts.isEmpty ? null : parts.join('  ·  ');
  }

  // ── adjustQty ───────────────────────────────────────────────────────────────────
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, double.infinity);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem ───────────────────────────────────────────────────────────
  @override
  void deleteCurrentItem() {
    final rowId = editingItemName.value;
    if (rowId == null) return;
    final item = _parent.stockEntry.value?.items
        .firstWhereOrNull((i) => i.name == rowId);
    if (item == null) return;
    _parent.confirmAndDeleteItem(item);
  }

  // ── MR link ───────────────────────────────────────────────────────────────────
  void linkMrItem({
    required String mrName,
    required String itemName,
    required String uom,
    required double qty,
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

    batchController.text        = item.batchNo ?? '';
    rackController.text         = item.rack    ?? '';
    sourceRackController.text   = item.rack    ?? '';
    targetRackController.text   = item.toRack  ?? '';
    qtyController.text          = item.qty.toString();

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

    if (scannedEan8.isNotEmpty) currentScannedEan = scannedEan8;

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

  // ── submit ────────────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Invalid quantity');

    final batch      = isBatchValid.value ? batchController.text : null;
    final srcRack    = isSourceRackValid.value ? sourceRackController.text : null;
    final tgtRack    = isTargetRackValid.value ? targetRackController.text : null;
    final serial     = selectedSerial.value;

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

  // ── validateRack override (uses rackStockMap cache) ──────────────────────
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
    if (sourceRackController.text.isEmpty) {
      sourceRackController.text = rackId;
      validateDualRack(rackId, true);
    } else {
      targetRackController.text = rackId;
      validateDualRack(rackId, false);
    }
  }

  bool get needsRackScanFallback => sourceRackController.text.isEmpty;

  // ── Snackbar helpers ──────────────────────────────────────────────────────────
  void showError(String msg)   => GlobalSnackbar.error(message: msg);
  void showSuccess(String msg) => GlobalSnackbar.success(message: msg);
}
