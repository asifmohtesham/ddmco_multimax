import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:collection/collection.dart';
import 'purchase_order_form_controller.dart';

/// Item-level sheet controller for Purchase Order.
///
/// Commit 9 fix:
///   • isAddingItemFlag = _parent.isAddingItem  →  .value appended.
///     ItemSheetControllerBase declares `bool isAddingItemFlag` (plain bool);
///     assigning the RxBool directly caused a type mismatch at compile time.
///   • adjustQty kept as `int` — the base abstract is `void adjustQty(int delta)`.
class PurchaseOrderItemFormController extends ItemSheetControllerBase {
  late PurchaseOrderFormController _parent;

  // ── PO-specific field controllers ─────────────────────────────────────────
  final rateController         = TextEditingController();
  final scheduleDateController = TextEditingController();

  // ── PO-specific Rx ───────────────────────────────────────────────────────
  var sheetRate = 0.0.obs;
  double get sheetAmount =>
      (double.tryParse(qtyController.text) ?? 0.0) * sheetRate.value;

  // ── Dirty-check snapshot ────────────────────────────────────────────────
  double _initialQty  = 0.0;
  double _initialRate = 0.0;
  String _initialDate = '';

  // ── ItemSheetControllerBase abstract overrides ────────────────────────────

  @override
  String? get resolvedWarehouse => null; // PO has no warehouse concept

  @override
  bool get requiresBatch => false;

  @override
  bool get requiresRack => false;

  @override
  Color get accentColor => Colors.blue;

  @override
  bool get isAddMode => editingItemName.value == null;

  /// PO has no stock context; no qty-info label needed.
  @override
  String get qtyInfoText => '';

  @override
  RxnString get qtyInfoTooltip => RxnString(null);

  /// PO sheet has no embedded scanner.
  @override
  MobileScannerController? get sheetScanController => null;

  /// ±1 stepper, unbounded ceiling (PO has no stock cap).
  /// Commit 9: signature kept as `int` — base abstract is `void adjustQty(int delta)`.
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, double.infinity);
    qtyController.text =
        next.truncateToDouble() == next
            ? next.toInt().toString()
            : next.toStringAsFixed(2);
    validateSheet();
  }

  // ── Listener helpers ────────────────────────────────────────────────────────
  void _initPOListeners() {
    scheduleDateController.addListener(validateSheet);
    scheduleDateController.addListener(_resetSaveState);
    rateController.addListener(_onRateChanged);
    rateController.addListener(_resetSaveState);
  }

  void _removePOListeners() {
    scheduleDateController.removeListener(validateSheet);
    scheduleDateController.removeListener(_resetSaveState);
    rateController.removeListener(_onRateChanged);
    rateController.removeListener(_resetSaveState);
  }

  void _resetSaveState() {
    if (saveButtonState.value == SaveButtonState.success ||
        saveButtonState.value == SaveButtonState.error) {
      saveButtonState.value = SaveButtonState.idle;
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void onClose() {
    _removePOListeners();
    final rtc = rateController;
    final sdc = scheduleDateController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rtc.dispose();
      sdc.dispose();
    });
    super.onClose();
  }

  // ── Initialise ─────────────────────────────────────────────────────────────

  void initialise({
    required PurchaseOrderFormController parentController,
    required String code,
    required String name,
    required String uom,
    required double qty,
    required double rate,
    String? rowId,
    String? scheduleDate,
    String? owner,
    String? creation,
    String? modified,
    String? modifiedBy,
  }) {
    _parent = parentController;

    editingItemName.value = rowId;
    // isAddMode is a computed getter (rowId == null) — no assignment.

    itemCode.value = code;
    itemName.value = name;

    itemOwner.value      = owner;
    itemCreation.value   = creation;
    itemModified.value   = modified;
    itemModifiedBy.value = modifiedBy;

    // Commit 9: base declares `bool isAddingItemFlag` (plain bool).
    // Extract .value from the RxBool to satisfy the type.
    isAddingItemFlag = _parent.isAddingItem.value;

    qtyController.text          = qty.toStringAsFixed(0);
    rateController.text         = rate.toStringAsFixed(2);
    scheduleDateController.text =
        scheduleDate ?? FormattingHelper.formatDate(DateTime.now());

    sheetRate.value = rate;

    _initialQty  = qty;
    _initialRate = rate;
    _initialDate = scheduleDateController.text;

    initBaseListeners();
    _initPOListeners();
    captureSnapshot();

    final storage = Get.find<StorageService>();
    if (storage.getAutoSubmitEnabled()) {
      setupAutoSubmit(
        onValid: () async {
          if (_parent.isEditable && _parent.isItemSheetOpen.value) {
            await submit();
          }
        },
      );
    }

    validateSheet();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _onRateChanged() {
    sheetRate.value = double.tryParse(rateController.text) ?? 0.0;
    validateSheet();
  }

  // ── validateSheet ──────────────────────────────────────────────────────────

  @override
  void validateSheet() {
    if (!_parent.isEditable) {
      isSheetValid.value = false;
      return;
    }

    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0)                                         { isSheetValid.value = false; return; }
    if (scheduleDateController.text.isEmpty)              { isSheetValid.value = false; return; }
    if ((double.tryParse(rateController.text) ?? -1) < 0) { isSheetValid.value = false; return; }

    if (!isAddMode) {
      final currentRate = double.tryParse(rateController.text) ?? 0;
      final dirty = qty         != _initialQty  ||
                    currentRate != _initialRate  ||
                    scheduleDateController.text != _initialDate;
      isSheetValid.value = dirty;
    } else {
      isSheetValid.value = true;
    }
  }

  // ── deleteCurrentItem ────────────────────────────────────────────────────────

  @override
  Future<void> deleteCurrentItem() async {
    if (editingItemName.value == null) return;
    final item = _parent.purchaseOrder.value?.items
        .firstWhereOrNull((i) => i.name == editingItemName.value);
    if (item == null) return;
    _parent.confirmAndDeleteItem(item);
  }

  // ── submit ────────────────────────────────────────────────────────────────────

  @override
  Future<void> submit() async {
    final qty  = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return;
    final rate         = double.tryParse(rateController.text) ?? 0.0;
    final scheduleDate = scheduleDateController.text;

    if (!isAddMode && editingItemName.value != null) {
      final existing = _parent.purchaseOrder.value?.items
          .firstWhereOrNull((i) => i.name == editingItemName.value);
      if (existing == null) return;
      final updated = PurchaseOrderItem(
        name:         existing.name,
        itemCode:     existing.itemCode,
        itemName:     existing.itemName,
        qty:          qty,
        receivedQty:  existing.receivedQty,
        rate:         rate,
        amount:       qty * rate,
        uom:          existing.uom,
        description:  existing.description,
        scheduleDate: scheduleDate,
        owner:        existing.owner,
        creation:     existing.creation,
        modified:     existing.modified,
        modifiedBy:   existing.modifiedBy,
      );
      _parent.updateItemLocally(updated);
    } else {
      final uniqueId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      final newItem = PurchaseOrderItem(
        name:         uniqueId,
        itemCode:     itemCode.value,
        itemName:     itemName.value,
        qty:          qty,
        receivedQty:  0.0,
        rate:         rate,
        amount:       qty * rate,
        uom:          '',
        scheduleDate: scheduleDate,
      );
      _parent.addItemLocally(newItem);
    }
    Get.back();
  }
}
