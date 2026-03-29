import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';

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
/// Commit C-2:
///   • [qtyInfoText]    → 'Max: N' (binding ceiling) or 'Max: -' (no ceiling).
///   • [qtyInfoTooltip] → '·'-separated breakdown of active ceilings, e.g.
///     'Serial: 3  ·  Batch: 8  ·  Rack: 72'.
///     Returns null when no ceiling is active → no tap target rendered.
///
/// Commit B:
///   • [effectiveMaxQty] ceiling chain: serial → stock → batch → rack → MR.
///
/// Commit A:
///   • [liveRemaining]    — Rx written in validateSheet(); drives chip rebuild.
///   • [posSerialCapText] — chip label, decoupled from qtyInfoText.
class StockEntryItemFormController extends ItemSheetControllerBase
    with PosSerialMixin, AutoFillRackMixin {
  // ── Parent reference ─────────────────────────────────────────────
  late StockEntryFormController _parent;
  StockEntryFormController get parent => _parent;

  // ── SE-specific extra TECs ────────────────────────────────────────────
  final TextEditingController sourceRackController = TextEditingController();
  final TextEditingController targetRackController = TextEditingController();

  // ── SE-specific validation state ─────────────────────────────────────────
  var isSourceRackValid      = false.obs;
  var isTargetRackValid      = false.obs;
  var isValidatingSourceRack = false.obs;
  var isValidatingTargetRack = false.obs;

  // ── Warehouse derivation ──────────────────────────────────────────────
  var derivedSourceWarehouse = RxnString();
  var derivedTargetWarehouse = RxnString();
  var itemSourceWarehouse    = RxnString();
  var itemTargetWarehouse    = RxnString();

  // ── Balance state ──────────────────────────────────────────────────
  var batchBalance          = 0.0.obs;
  var rackBalance           = 0.0.obs;
  var validationMaxQty      = 0.0.obs;
  var isLoadingBatchBalance = false.obs;
  var isLoadingRackBalance  = false.obs;

  // ── Commit A: reactive remaining for chip ──────────────────────────────
  var liveRemaining = 0.0.obs;

  // ── Dirty-check snapshots ─────────────────────────────────────────────
  String _snapshotSourceRack = '';
  String _snapshotTargetRack = '';

  // ── AutoFillRackMixin hooks ─────────────────────────────────────────────
  @override
  TextEditingController get autoFillRackController => sourceRackController;

  @override
  void onAutoFillRackSelected(String rack) => validateDualRack(rack, true);

  // ── ItemSheetControllerBase contract ────────────────────────────────────
  @override
  String? get resolvedWarehouse =>
      itemSourceWarehouse.value ??
      derivedSourceWarehouse.value ??
      _parent.selectedFromWarehouse.value;

  @override
  bool get requiresBatch => true;

  @override
  bool get requiresRack => false;

  // ── P1-C: isSheetLoading override ──────────────────────────────────────
  @override
  bool get isSheetLoading =>
      super.isSheetLoading ||
      isValidatingSourceRack.value ||
      isValidatingTargetRack.value;

  // ── posSerialCapText: dedicated chip label (Commit A) ───────────────────
  //
  // Returns 'Invoice #N — Remaining: X / Y pcs'.
  // Decoupled from qtyInfoText so the chip and the Qty badge serve
  // independent purposes after Commit C.
  String? get posSerialCapText {
    final serial = selectedSerial.value;
    if (serial == null || serial == '0' || serial.isEmpty) return null;
    if (_parent.posUpload.value == null) return null;

    final serialNo  = int.tryParse(serial) ?? 0;
    final cap       = _parent.posQtyCapForSerial(serial);
    final used      = _parent.scannedQtyForSerial(
      serial, excludeItemName: editingItemName.value);
    final currentQty = double.tryParse(qtyController.text) ?? 0.0;     final remaining = (cap - used - currentQty).clamp(0.0, cap);

    String _fmt(double v) =>
        v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

    return 'Invoice #$serialNo \u2014 Remaining: ${_fmt(remaining)} / ${_fmt(cap)} pcs';
  }

  // ── qtyInfoText: 'Max: N' or 'Max: -' (Commit C-2) ─────────────────────
  //
  // Returns 'Max: -' when no ceiling is active so the badge is always
  // present (signals 'ceiling not yet computed') rather than absent.
  @override
  String? get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff >= 999999.0) return 'Max: -';
    final n = eff % 1 == 0 ? eff.toInt().toString() : eff.toStringAsFixed(2);
    return 'Max: $n';
  }

  // ── qtyInfoTooltip: breakdown shown on badge tap (Commit C-2) ───────────
  //
  // Builds a · -separated list of every active ceiling with its value.
  // Returns null when no ceiling is active → widget hides tap target.
  @override
  String? get qtyInfoTooltip {
    final parts = <String>[];

    // Serial remaining (POS)
    final serial = selectedSerial.value;
    if (serial != null &&
        serial != '0' &&
        serial.isNotEmpty &&
        _parent.posUpload.value != null) {
      final cap  = _parent.posQtyCapForSerial(serial);
      final used = _parent.scannedQtyForSerial(
          serial, excludeItemName: editingItemName.value);
      final currentQty = double.tryParse(qtyController.text) ?? 0.0;         final rem  = (cap - used - currentQty).clamp(0.0, cap);
      final remStr = rem % 1 == 0
          ? rem.toInt().toString()
          : rem.toStringAsFixed(2);
      parts.add('Serial: $remStr');
    }

    // Batch balance
    if (batchBalance.value > 0) {
      final b = batchBalance.value;
      parts.add('Batch: ${b % 1 == 0 ? b.toInt() : b.toStringAsFixed(2)}');
    }

    // Rack balance
    if (isSourceRackValid.value && rackBalance.value > 0) {
      final r = rackBalance.value;
      parts.add('Rack: ${r % 1 == 0 ? r.toInt() : r.toStringAsFixed(2)}');
    }

    // MR cap
    if (validationMaxQty.value > 0) {
      final m = validationMaxQty.value;
      parts.add('MR: ${m % 1 == 0 ? m.toInt() : m.toStringAsFixed(2)}');
    }

    if (parts.isEmpty) return null;
    return parts.join('  \u00b7  ');
  }

  // ── deleteCurrentItem ───────────────────────────────────────────────────
  @override
  Future<void> deleteCurrentItem() async {
    final name = editingItemName.value;
    if (name == null) return;
    final item = _parent.stockEntry.value?.items
        .firstWhereOrNull((i) => i.name == name);
    if (item != null) _parent.confirmAndDeleteItem(item);
  }

  // ── PosSerialMixin contract ───────────────────────────────────────────────
  @override
  List<String> get availableSerialNos => _parent.posUploadSerialOptions;

  // ── Initialisation ─────────────────────────────────────────────────────
  void initialise({
    required StockEntryFormController parent,
    required String code,
    required String variantOf,
    required String name,
    required String itemName,
    String? batchNo,
    StockEntryItem? editingItem,
    String scannedEan8 = '',
    List<Map<String, dynamic>> mrReferenceItems = const [],
  }) {
    _parent = parent;
    currentScannedEan = scannedEan8;
    isAddingItemFlag  = _parent.isAddingItem;

    itemCode.value      = code;
    this.itemName.value = itemName;
    maxQty.value        = 0.0;
    rackStockMap.clear();
    rackStockTooltip.value = null;
    rackError.value        = null;
    batchError.value       = null;
    batchInfoTooltip.value = null;
    isBatchValid.value     = false;
    isRackValid.value      = false;

    isSourceRackValid.value      = false;
    isTargetRackValid.value      = false;
    derivedSourceWarehouse.value = null;
    derivedTargetWarehouse.value = null;
    itemSourceWarehouse.value    = null;
    itemTargetWarehouse.value    = null;
    batchBalance.value           = 0.0;
    rackBalance.value            = 0.0;
    validationMaxQty.value       = 0.0;
    isLoadingBatchBalance.value  = false;
    isLoadingRackBalance.value   = false;
    isBatchReadOnly.value        = false;
    liveRemaining.value          = 0.0;
    sourceRackController.clear();
    targetRackController.clear();

    if (mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems.firstWhereOrNull(
          (r) => r['item_code'].toString().trim().toLowerCase() ==
              code.trim().toLowerCase());
      if (ref != null) {
        validationMaxQty.value = (ref['qty'] as num).toDouble();
      }
    }

    if (editingItem != null) {
      _loadExistingItem(editingItem, mrReferenceItems);
    } else {
      _loadNewItem(batchNo, mrReferenceItems);
    }

    isAddMode = editingItem == null;

    initBaseListeners();
    initAutoFillListener();
    sourceRackController.addListener(validateSheet);
    targetRackController.addListener(validateSheet);
    ever(selectedSerial, (_) => validateSheet());
    ever(itemSourceWarehouse, (_) async {
      await _updateAvailableStock();
      await _updateBatchBalance();
    });

    captureSnapshot();
    captureSerialSnapshot();
    _snapshotSourceRack = sourceRackController.text;
    _snapshotTargetRack = targetRackController.text;

    if (editingItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _updateAvailableStock();
        await _updateBatchBalance();
      });
    }

    validateSheet();
    fetchAllRackStocks();
  }

  void _loadExistingItem(
    StockEntryItem item,
    List<Map<String, dynamic>> mrReferenceItems,
  ) {
    editingItemName.value = item.name;
    itemOwner.value      = item.owner;
    itemCreation.value   = item.creation;
    itemModified.value   = item.modified;
    itemModifiedBy.value = item.modifiedBy;

    final qty = item.qty;
    qtyController.text        = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    batchController.text      = item.batchNo ?? '';
    sourceRackController.text = item.rack    ?? '';
    targetRackController.text = item.toRack  ?? '';
    selectedSerial.value      = item.customInvoiceSerialNumber;

    if (_parent.entrySource == StockEntrySource.materialRequest &&
        (selectedSerial.value == null || selectedSerial.value!.isEmpty)) {
      selectedSerial.value = '0';
    }

    isBatchValid.value           = item.batchNo != null && item.batchNo!.isNotEmpty;
    isBatchReadOnly.value        = isBatchValid.value;
    isSourceRackValid.value      = item.rack   != null && item.rack!.isNotEmpty;
    isTargetRackValid.value      = item.toRack != null && item.toRack!.isNotEmpty;
    itemSourceWarehouse.value    = item.sWarehouse;
    itemTargetWarehouse.value    = item.tWarehouse;
    derivedSourceWarehouse.value = item.sWarehouse;
    derivedTargetWarehouse.value = item.tWarehouse;

    if (item.batchNo != null && item.batchNo!.contains('-')) {
      currentScannedEan = item.batchNo!.split('-').first;
    }

    log('[SE:ItemSheet] loaded existing item=${item.name} batch=${item.batchNo}',
        name: 'SE:ItemSheet');
  }

  void _loadNewItem(
    String? batchNo,
    List<Map<String, dynamic>> mrReferenceItems,
  ) {
    editingItemName.value = null;
    itemOwner.value = itemCreation.value = itemModified.value = itemModifiedBy.value = null;

    batchController.text = batchNo ?? '';
    qtyController.clear();
    selectedSerial.value = null;

    if (_parent.entrySource == StockEntrySource.materialRequest) {
      selectedSerial.value = '0';
    }

    isBatchValid.value    = batchNo != null && batchNo.isNotEmpty;
    isBatchReadOnly.value = isBatchValid.value;

    if (isBatchValid.value) validateBatchOnInit(batchNo!);

    log('[SE:ItemSheet] new item code=${itemCode.value} batch=$batchNo',
        name: 'SE:ItemSheet');
  }

  // ── validateSheet ───────────────────────────────────────────────────────
  @override
  void validateSheet() {
    bool valid = true;

    final qty    = double.tryParse(qtyController.text) ?? 0;
    final effMax = effectiveMaxQty;
    if (qty <= 0) valid = false;
    if (effMax < 999999.0 && qty > effMax) valid = false;

    if (batchController.text.isEmpty || !isBatchValid.value) valid = false;
    if (!isValidRacks()) valid = false;

    if (_parent.entrySource == StockEntrySource.materialRequest) {
      if (!_checkMrConstraints()) valid = false;
    } else if (_parent.entrySource == StockEntrySource.posUpload) {
      if (!_checkPosConstraints()) valid = false;
    }

    if (!validateSerial()) valid = false;

    // Commit A: sync liveRemaining → chip Obx rebuilds on qty change
    final serial = selectedSerial.value;
    if (serial != null &&
        serial != '0' &&
        serial.isNotEmpty &&
        _parent.posUpload.value != null) {
      final cap  = _parent.posQtyCapForSerial(serial);
      final used = _parent.scannedQtyForSerial(
          serial, excludeItemName: editingItemName.value);
      final currentQty = double.tryParse(qtyController.text) ?? 0.0;         liveRemaining.value = (cap - used - currentQty).clamp(0.0, cap);
    } else {
      liveRemaining.value = 0.0;
    }

    isFormDirty.value = isFieldsDirty ||
        sourceRackController.text != _snapshotSourceRack ||
        targetRackController.text != _snapshotTargetRack ||
        isSerialDirty;

    if (editingItemName.value != null && !isFormDirty.value) valid = false;
    isSheetValid.value = valid;
  }

  // ── submit ─────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty        = double.tryParse(qtyController.text) ?? 0;
    final batch      = batchController.text;
    final sourceRack = sourceRackController.text;
    final targetRack = targetRackController.text;
    final sWh = itemSourceWarehouse.value ??
        derivedSourceWarehouse.value ??
        _parent.selectedFromWarehouse.value;
    final tWh = itemTargetWarehouse.value ??
        derivedTargetWarehouse.value ??
        _parent.selectedToWarehouse.value;
    final serial = selectedSerial.value;

    if (editingItemName.value != null && editingItemName.value!.isNotEmpty) {
      _parent.updateItemLocally(
          editingItemName.value!, qty, batch, sourceRack, targetRack,
          sWh, tWh, serial);
    } else {
      _parent.addItemLocally(
          qty, batch, sourceRack, targetRack, sWh, tWh, serial);
    }
  }

  // ── effectiveMaxQty ─────────────────────────────────────────────────────
  double get effectiveMaxQty {
    double limit = 999999.0;

    // 1. POS serial remaining
    final serial = selectedSerial.value;
    if (serial != null &&
        serial != '0' &&
        serial.isNotEmpty &&
        _parent.posUpload.value != null) {
      final cap  = _parent.posQtyCapForSerial(serial);
      final used = _parent.scannedQtyForSerial(
          serial, excludeItemName: editingItemName.value);
      final rem  = (cap - used).clamp(0.0, double.infinity);
      if (rem < limit) limit = rem;
    }

    // 2. Total stock
    if (maxQty.value > 0 && maxQty.value < limit) limit = maxQty.value;

    // 3. Batch balance
    if (batchBalance.value > 0 && batchBalance.value < limit)
      limit = batchBalance.value;

    // 4. Rack balance
    if (isSourceRackValid.value &&
        rackBalance.value > 0 &&
        rackBalance.value < limit) limit = rackBalance.value;

    // 5. MR cap
    if (validationMaxQty.value > 0 && validationMaxQty.value < limit)
      limit = validationMaxQty.value;

    return limit;
  }

  // ── Rack rule helper ───────────────────────────────────────────────────
  bool isValidRacks() {
    final type = _parent.selectedStockEntryType.value;
    final needsSource = [
      'Material Issue', 'Material Transfer', 'Material Transfer for Manufacture'
    ].contains(type);
    final needsTarget = [
      'Material Receipt', 'Material Transfer', 'Material Transfer for Manufacture'
    ].contains(type);

    if (needsSource &&
        (sourceRackController.text.isEmpty || !isSourceRackValid.value))
      return false;
    if (needsTarget &&
        (targetRackController.text.isEmpty || !isTargetRackValid.value))
      return false;
    if (needsSource && needsTarget) {
      final src = sourceRackController.text.trim();
      final tgt = targetRackController.text.trim();
      if (src.isNotEmpty && src == tgt) {
        rackError.value = 'Source and Target Racks cannot be the same';
        return false;
      }
    }
    if (rackError.value == 'Source and Target Racks cannot be the same') {
      rackError.value = null;
    }
    return true;
  }

  // ── MR / POS constraint helpers ─────────────────────────────────────────
  bool _checkMrConstraints() {
    if (_parent.mrReferenceItems.isEmpty) return true;
    final code = itemCode.value.trim().toLowerCase();
    final ref  = _parent.mrReferenceItems.firstWhereOrNull(
        (r) => r['item_code'].toString().trim().toLowerCase() == code);
    if (ref == null) return true;
    final allowed = (ref['qty'] as num).toDouble();
    validationMaxQty.value = allowed;
    final entered = double.tryParse(qtyController.text) ?? 0;
    return entered <= allowed;
  }

  bool _checkPosConstraints() {
    if (_parent.selectedStockEntryType.value != 'Material Issue') return true;
    if (selectedSerial.value == null || selectedSerial.value!.isEmpty) {
      if (!_parent.customReferenceNoController.text.startsWith('MAT-STE-')) {
        if (_parent.posUploadSerialOptions.isNotEmpty) return false;
      }
    }
    return true;
  }

  // ── validateBatch (SE-specific override) ────────────────────────────────
  @override
  Future<void> validateBatch(String batch) async {
    batchError.value = null;
    if (batch.isEmpty) return;

    if (batch.contains('-')) {
      final parts = batch.split('-');
      if (parts.length >= 2 && parts[0] == parts[1]) {
        isBatchValid.value    = false;
        isBatchReadOnly.value = false;
        batchError.value      = 'Invalid Batch: Batch ID cannot match EAN';
        validateSheet();
        return;
      }
    }

    isValidatingBatch.value = true;
    try {
      final api = Get.find<ApiProvider>();
      final response = await api.getDocumentList(
        'Batch',
        filters: {'item': itemCode.value, 'name': batch},
        fields: ['name', 'custom_packaging_qty'],
      );
      if (response.statusCode == 200 &&
          response.data['data'] != null &&
          (response.data['data'] as List).isNotEmpty) {
        final batchData = response.data['data'][0];
        isBatchValid.value    = true;
        isBatchReadOnly.value = true;
        final double pkgQty =
            (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
        if (pkgQty > 0) {
          qtyController.text = pkgQty % 1 == 0
              ? pkgQty.toInt().toString()
              : pkgQty.toString();
        }
        await _updateAvailableStock();
        await _updateBatchBalance();
        unawaited(fetchAllRackStocks());

        final enteredQty = double.tryParse(qtyController.text) ?? 0.0;
        if (batchBalance.value > 0 && enteredQty > batchBalance.value) {
          batchError.value =
              'Qty ($enteredQty) exceeds Batch balance '
              '(${batchBalance.value.toStringAsFixed(0)}) in warehouse';
          GlobalSnackbar.error(
              message: 'Entered qty exceeds available Batch balance of '
                  '${batchBalance.value.toStringAsFixed(0)} in warehouse');
        }
      } else {
        isBatchValid.value    = false;
        isBatchReadOnly.value = false;
        GlobalSnackbar.error(message: 'Batch not found for this item');
      }
    } catch (e) {
      isBatchValid.value    = false;
      isBatchReadOnly.value = false;
      GlobalSnackbar.error(message: 'Failed to validate batch: $e');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  void resetBatchValidation() {
    isBatchValid.value    = false;
    isBatchReadOnly.value = false;
    batchError.value      = null;
    validateSheet();
  }

  // ── validateDualRack ─────────────────────────────────────────────────────
  Future<void> validateDualRack(String rack, bool isSource) async {
    if (rack.isEmpty) {
      if (isSource) {
        isSourceRackValid.value      = false;
        derivedSourceWarehouse.value = null;
      } else {
        isTargetRackValid.value      = false;
        derivedTargetWarehouse.value = null;
      }
      validateSheet();
      return;
    }

    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
        if (isSource) {
          derivedSourceWarehouse.value = wh;
          itemSourceWarehouse.value    = wh;
        } else {
          derivedTargetWarehouse.value = wh;
          itemTargetWarehouse.value    = wh;
        }
      }
    }

    if (isSource) isValidatingSourceRack.value = true;
    else          isValidatingTargetRack.value = true;

    try {
      final api = Get.find<ApiProvider>();
      final response = await api.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        if (isSource) {
          isSourceRackValid.value = true;
          final enteredQty = double.tryParse(qtyController.text) ?? 0.0;
          if (batchBalance.value > 0 && enteredQty > batchBalance.value) {
            batchError.value =
                'Qty ($enteredQty) exceeds Batch balance '
                '(${batchBalance.value.toStringAsFixed(0)}) in warehouse';
            GlobalSnackbar.error(
                message: 'Entered qty exceeds available Batch balance of '
                    '${batchBalance.value.toStringAsFixed(0)} in warehouse');
          } else {
            if (batchError.value != null &&
                batchError.value!.contains('Batch balance')) {
              batchError.value = null;
            }
          }
        } else {
          isTargetRackValid.value = true;
        }
      } else {
        if (isSource) isSourceRackValid.value = false;
        else          isTargetRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      if (isSource) isSourceRackValid.value = false;
      else          isTargetRackValid.value = false;
    } finally {
      if (isSource) isValidatingSourceRack.value = false;
      else          isValidatingTargetRack.value = false;
      validateSheet();
    }
  }

  void resetSourceRackValidation() {
    isSourceRackValid.value = false;
    validateSheet();
  }

  void resetTargetRackValidation() {
    isTargetRackValid.value = false;
    validateSheet();
  }

  // ── Stock / batch balance fetchers ──────────────────────────────────────
  Future<void> _updateAvailableStock() async {
    final type = _parent.selectedStockEntryType.value;
    final isSourceOp = [
      'Material Issue', 'Material Transfer', 'Material Transfer for Manufacture'
    ].contains(type);

    if (!isSourceOp) {
      maxQty.value               = 999999.0;
      rackBalance.value          = 0.0;
      isLoadingRackBalance.value = false;
      return;
    }

    final effectiveWh = itemSourceWarehouse.value ??
        derivedSourceWarehouse.value ??
        _parent.selectedFromWarehouse.value;

    if (effectiveWh == null || effectiveWh.isEmpty) {
      maxQty.value = rackBalance.value = 0.0;
      isLoadingRackBalance.value = false;
      rackError.value = 'No Warehouse Selected';
      return;
    }

    isLoadingRackBalance.value = true;
    final batch = batchController.text.trim();
    final rack  = sourceRackController.text.trim();

    try {
      final api = Get.find<ApiProvider>();
      final response = await api.getStockBalance(
        itemCode:  itemCode.value,
        warehouse: effectiveWh,
        batchNo:   batch.isNotEmpty ? batch : null,
      );

      if (response.statusCode == 200 &&
          response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        double total = 0.0, rackBal = 0.0;
        for (final row in result) {
          if (row is! Map) continue;
          final rowQty = (row['bal_qty'] as num?)?.toDouble() ?? 0.0;
          total += rowQty;
          if (rack.isNotEmpty && row['rack'] == rack) rackBal += rowQty;
        }
        maxQty.value      = total;
        rackBalance.value = rack.isNotEmpty ? rackBal : 0.0;

        if (rack.isNotEmpty && rackBal <= 0) {
          rackError.value =
              'Insufficient stock in Rack: $rack (Warehouse: $effectiveWh)';
          GlobalSnackbar.error(
              message:
                  'Insufficient stock in Rack: $rack (Warehouse: $effectiveWh)');
          isSourceRackValid.value = false;
        }
      }
    } catch (e) {
      log('[SE:ItemSheet] _updateAvailableStock error: $e', name: 'SE:ItemSheet');
    } finally {
      isLoadingRackBalance.value = false;
    }
  }

  Future<void> _updateBatchBalance() async {
    final batch = batchController.text.trim();
    if (batch.isEmpty || itemCode.value.isEmpty) {
      batchBalance.value          = 0.0;
      isLoadingBatchBalance.value = false;
      return;
    }
    isLoadingBatchBalance.value = true;
    final warehouse = itemSourceWarehouse.value ??
        derivedSourceWarehouse.value ??
        _parent.selectedFromWarehouse.value;
    try {
      final api = Get.find<ApiProvider>();
      final response = await api.getBatchWiseBalance(
          itemCode.value, batch, warehouse: warehouse);
      if (response.statusCode == 200 &&
          response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        double total = 0.0;
        for (final row in result) {
          if (row is Map) {
            final val = row['balance_qty'] ?? row['bal_qty'] ??
                row['qty_after_transaction'] ?? row['qty'];
            total += (val as num?)?.toDouble() ?? 0.0;
          }
        }
        batchBalance.value = total;
      } else {
        batchBalance.value = 0.0;
      }
    } catch (e) {
      batchBalance.value = 0.0;
      log('[SE:ItemSheet] _updateBatchBalance error: $e', name: 'SE:ItemSheet');
    } finally {
      isLoadingBatchBalance.value = false;
    }
  }

  // ── Sheet scan helpers ──────────────────────────────────────────────────
  void applyRackScan(String code) {
    final type = _parent.selectedStockEntryType.value;
    if (type == 'Material Transfer' ||
        type == 'Material Transfer for Manufacture') {
      if (sourceRackController.text.isEmpty) {
        sourceRackController.text = code;
        validateDualRack(code, true);
      } else {
        if (code == sourceRackController.text) {
          rackError.value = 'Source and Target Racks cannot be the same';
          return;
        }
        targetRackController.text = code;
        validateDualRack(code, false);
      }
    } else if (type == 'Material Issue') {
      sourceRackController.text = code;
      validateDualRack(code, true);
    } else if (type == 'Material Receipt') {
      targetRackController.text = code;
      validateDualRack(code, false);
    }
  }

  bool get needsRackScanFallback {
    final type = _parent.selectedStockEntryType.value;
    if (type == 'Material Issue')   return sourceRackController.text.isEmpty;
    if (type == 'Material Receipt') return targetRackController.text.isEmpty;
    if (type == 'Material Transfer' ||
        type == 'Material Transfer for Manufacture') {
      return sourceRackController.text.isEmpty ||
          targetRackController.text.isEmpty;
    }
    return false;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────
  @override
  void onClose() {
    disposeAutoFillListener();
    sourceRackController.removeListener(validateSheet);
    targetRackController.removeListener(validateSheet);
    final src = sourceRackController;
    final tgt = targetRackController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      src.dispose();
      tgt.dispose();
    });
    super.onClose();
  }

  // ── Test-support helpers ────────────────────────────────────────────────
  // ignore: use_setters_to_change_properties
  void testInjectParent(StockEntryFormController parent) {
    _parent = parent;
  }

  bool isValidQty() {
    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return false;
    final effMax = effectiveMaxQty;
    if (effMax < 999999.0 && qty > effMax) return false;
    return true;
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(qtyController.text) ?? 0;
    final next    = current + delta;
    if (next <= 0) {
      qtyController.text = '';
      validateSheet();
      return;
    }
    final effMax = effectiveMaxQty;
    if (effMax < 999999.0 && next > effMax) return;
    qtyController.text =
        next % 1 == 0 ? next.toInt().toString() : next.toString();
    validateSheet();
  }

  void setInitialSnapshot({
    String qty        = '',
    String batch      = '',
    String sourceRack = '',
    String targetRack = '',
  }) {
    qtyController.text        = qty;
    batchController.text      = batch;
    sourceRackController.text = sourceRack;
    targetRackController.text = targetRack;
    captureSnapshot();
    _snapshotSourceRack = sourceRack;
    _snapshotTargetRack = targetRack;
  }
}
