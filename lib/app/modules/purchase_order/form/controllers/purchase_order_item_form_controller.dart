import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import '../purchase_order_form_controller.dart';
import 'package:collection/collection.dart';

class PurchaseOrderItemFormController extends GetxController {
  late PurchaseOrderFormController _parent;

  // --- Form Key ---
  var itemFormKey = GlobalKey<FormState>();

  // --- Text Controllers ---
  final qtyController = TextEditingController();
  final rateController = TextEditingController();
  final scheduleDateController = TextEditingController();

  // --- Item Identity ---
  var itemCode = ''.obs;
  var itemName = ''.obs;
  var itemUom = ''.obs;
  var currentItemNameKey = RxnString(); // null = new item, non-null = editing

  // --- Metadata ---
  var itemOwner = RxnString();
  var itemCreation = RxnString();
  var itemModified = RxnString();
  var itemModifiedBy = RxnString();

  // --- Computed Rx ---
  var sheetQty = 0.0.obs;
  var sheetRate = 0.0.obs;
  double get sheetAmount => sheetQty.value * sheetRate.value;

  // --- Validation ---
  var isSheetValid = false.obs;

  // --- Dirty tracking snapshot ---
  double _initialQty = 0.0;
  double _initialRate = 0.0;
  String _initialDate = '';

  // --- Auto-submit ---
  Timer? _autoSubmitTimer;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onClose() {
    _autoSubmitTimer?.cancel();
    qtyController.dispose();
    rateController.dispose();
    scheduleDateController.dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // Initialise — called by parent after creating this controller
  // ---------------------------------------------------------------------------

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

    // Refresh form key every open so validators reset cleanly.
    itemFormKey = GlobalKey<FormState>();

    // Identity
    itemCode.value = code;
    itemName.value = name;
    itemUom.value = uom;
    currentItemNameKey.value = rowId;

    // Metadata
    itemOwner.value = owner;
    itemCreation.value = creation;
    itemModified.value = modified;
    itemModifiedBy.value = modifiedBy;

    // Field values
    qtyController.text = qty.toStringAsFixed(0);
    rateController.text = rate.toStringAsFixed(2);
    scheduleDateController.text =
        scheduleDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    sheetQty.value = qty;
    sheetRate.value = rate;

    // Snapshot for dirty check
    _initialQty = qty;
    _initialRate = rate;
    _initialDate = scheduleDateController.text;

    // Wire listeners
    qtyController.addListener(_onQtyChanged);
    rateController.addListener(_onRateChanged);
    scheduleDateController.addListener(validateSheet);

    _setupAutoSubmit();
    validateSheet();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _onQtyChanged() {
    sheetQty.value = double.tryParse(qtyController.text) ?? 0.0;
    validateSheet();
  }

  void _onRateChanged() {
    sheetRate.value = double.tryParse(rateController.text) ?? 0.0;
    validateSheet();
  }

  void _setupAutoSubmit() {
    final storage = Get.find<StorageService>();

    ever(isSheetValid, (bool valid) {
      _autoSubmitTimer?.cancel();
      if (valid && _parent.isEditable && storage.getAutoSubmitEnabled()) {
        final delay = storage.getAutoSubmitDelay();
        _autoSubmitTimer = Timer(Duration(seconds: delay), () {
          if (isSheetValid.value) submit();
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void validateSheet() {
    if (!_parent.isEditable) {
      isSheetValid.value = false;
      return;
    }

    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) { isSheetValid.value = false; return; }
    if (scheduleDateController.text.isEmpty) { isSheetValid.value = false; return; }

    // Dirty check: editing an existing item requires at least one field to have changed.
    if (currentItemNameKey.value != null) {
      final currentRate = double.tryParse(rateController.text) ?? 0;
      final dirty = qty != _initialQty ||
          currentRate != _initialRate ||
          scheduleDateController.text != _initialDate;
      isSheetValid.value = dirty;
    } else {
      isSheetValid.value = true; // New items are always submittable once valid.
    }
  }

  void adjustQty(double delta) {
    final current = double.tryParse(qtyController.text) ?? 0;
    final newVal = (current + delta).clamp(0.0, 999999.0);
    qtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
  }

  void submit() {
    final qty          = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return;
    final rate         = double.tryParse(rateController.text) ?? 0.0;
    final scheduleDate = scheduleDateController.text;

    if (currentItemNameKey.value != null) {
      // Edit path — preserve all server-side metadata fields
      final existing = _parent.purchaseOrder.value?.items
          .firstWhereOrNull((i) => i.name == currentItemNameKey.value);
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
      // Add path
      final uniqueId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      final newItem = PurchaseOrderItem(
        name:         uniqueId,
        itemCode:     itemCode.value,
        itemName:     itemName.value,
        qty:          qty,
        receivedQty:  0.0,
        rate:         rate,
        amount:       qty * rate,
        uom:          itemUom.value,
        scheduleDate: scheduleDate,
      );
      _parent.addItemLocally(newItem);
    }
    Get.back();
  }
}
