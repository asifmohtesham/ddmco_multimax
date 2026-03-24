import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:collection/collection.dart';
import '../purchase_order_form_controller.dart';

class PurchaseOrderItemFormController extends ItemSheetControllerBase {
  late PurchaseOrderFormController _parent;

  // ── PO-specific field controllers ─────────────────────────────────────────
  final rateController         = TextEditingController();
  final scheduleDateController = TextEditingController();

  // ── PO-specific Rx ───────────────────────────────────────────────────────
  var sheetRate = 0.0.obs;
  double get sheetAmount => (double.tryParse(qtyController.text) ?? 0.0) * sheetRate.value;

  // ── Dirty-check snapshot ─────────────────────────────────────────────────
  double _initialQty  = 0.0;
  double _initialRate = 0.0;
  String _initialDate = '';

  // ── ItemSheetControllerBase overrides ─────────────────────────────────────

  @override
  String? get resolvedWarehouse => null; // PO has no warehouse concept

  @override
  bool get requiresBatch => false;

  @override
  bool get requiresRack => false;

  @override
  String? get qtyInfoText => null; // no stock context on outbound orders

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onClose() {
    rateController.dispose();
    scheduleDateController.dispose();
    super.onClose(); // disposes qtyController + base controllers
  }

  // ── Initialise — called by parent _openItemSheet() ────────────────────────

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

    // ── Base: add-mode flag & editing context ──────────────────────────────
    editingItemName.value = rowId;
    isAddMode             = rowId == null;

    // ── Base: item identity ────────────────────────────────────────────────
    itemCode.value = code;
    itemName.value = name;

    // ── Base: metadata footer ──────────────────────────────────────────────
    itemOwner.value      = owner;
    itemCreation.value   = creation;
    itemModified.value   = modified;
    itemModifiedBy.value = modifiedBy;

    // ── Base: parent saving flag ───────────────────────────────────────────
    isAddingItemFlag = _parent.isAddingItem;

    // ── PO-specific fields ─────────────────────────────────────────────────
    qtyController.text          = qty.toStringAsFixed(0);
    rateController.text         = rate.toStringAsFixed(2);
    scheduleDateController.text =
        scheduleDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    sheetRate.value = rate;

    // ── Dirty-check snapshot ───────────────────────────────────────────────
    _initialQty  = qty;
    _initialRate = rate;
    _initialDate = scheduleDateController.text;

    // ── Base: wire shared qty listener + capture snapshot ─────────────────
    initBaseListeners();
    scheduleDateController.addListener(validateSheet);
    rateController.addListener(_onRateChanged);
    captureSnapshot();

    // ── Auto-submit ────────────────────────────────────────────────────────
    final storage = Get.find<StorageService>();
    setupAutoSubmit(
      enabled:       storage.getAutoSubmitEnabled(),
      delaySeconds:  storage.getAutoSubmitDelay(),
      isSheetOpen:   _parent.isItemSheetOpen,
      isSubmittable: () => _parent.isEditable,
      onAutoSubmit:  submit,
    );

    validateSheet();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _onRateChanged() {
    sheetRate.value = double.tryParse(rateController.text) ?? 0.0;
    validateSheet();
  }

  // ── ItemSheetControllerBase: validateSheet ────────────────────────────────

  @override
  void validateSheet() {
    if (!_parent.isEditable) {
      isSheetValid.value = false;
      return;
    }

    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) { isSheetValid.value = false; return; }
    if (scheduleDateController.text.isEmpty) { isSheetValid.value = false; return; }
    if ((double.tryParse(rateController.text) ?? -1) < 0) { isSheetValid.value = false; return; }

    // Edit mode: require at least one field to have changed.
    if (!isAddMode) {
      final currentRate = double.tryParse(rateController.text) ?? 0;
      final dirty = qty != _initialQty ||
          currentRate != _initialRate ||
          scheduleDateController.text != _initialDate;
      isSheetValid.value = dirty;
    } else {
      isSheetValid.value = true;
    }
  }

  // ── ItemSheetControllerBase: deleteCurrentItem ────────────────────────────

  @override
  Future<void> deleteCurrentItem() async {
    if (editingItemName.value == null) return;
    final item = _parent.purchaseOrder.value?.items
        .firstWhereOrNull((i) => i.name == editingItemName.value);
    if (item == null) return;
    _parent.confirmAndDeleteItem(item);
  }

  // ── ItemSheetControllerBase: submit ───────────────────────────────────────

  @override
  Future<void> submit() async {
    final qty  = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return;
    final rate         = double.tryParse(rateController.text) ?? 0.0;
    final scheduleDate = scheduleDateController.text;

    if (!isAddMode && editingItemName.value != null) {
      // Edit path — preserve all server-side metadata fields.
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
      // Add path.
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
