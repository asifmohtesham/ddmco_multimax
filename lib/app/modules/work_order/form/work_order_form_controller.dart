import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/models/work_order_operation_model.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
import 'package:multimax/app/data/services/scan_service.dart';

class WorkOrderFormController extends GetxController {
  final WorkOrderProvider _provider = Get.find<WorkOrderProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  StreamSubscription<String>? _barcodeScanSubscription;

  // ── Route args ─────────────────────────────────────────────────────────────────────
  late String name;
  late String mode; // 'new' | 'view'

  // ── Rx state ───────────────────────────────────────────────────────────────────────
  final isLoading = true.obs;
  final isSaving = false.obs;
  final isDirty = false.obs;
  final isFetchingBom = false.obs;
  final isFetchingWarehouses = false.obs;
  final isFetchingItems = false.obs;

  // ── Operations state ───────────────────────────────────────────────────────────────
  final isSubmitting       = false.obs;
  final isCreatingJobCards = false.obs;
  final operations         = <WorkOrderOperation>[].obs;

  final workOrder = Rx<WorkOrder?>(null);

  // ── Dropdown / picker data ─────────────────────────────────────────────────────────
  final bomOptions = <String>[].obs;
  final itemOptions = <String>[].obs;

  // ── Form controllers ───────────────────────────────────────────────────────────────
  final itemController         = TextEditingController();
  final bomController          = TextEditingController();
  final qtyController          = TextEditingController();
  final plannedStartController = TextEditingController();
  final expectedEndController  = TextEditingController();
  final wipWarehouseController = TextEditingController();
  final fgWarehouseController  = TextEditingController();
  final descriptionController  = TextEditingController();

  // ── Observables for reactive UI ──────────────────────────────────────────────────
  final selectedItem     = RxnString();
  final selectedBom      = RxnString();
  final selectedItemName = RxnString();
  final isItemValid      = false.obs;
  final isBomValid       = false.obs;
  final isQtyValid       = false.obs;

  // ── Barcode scanning ────────────────────────────────────────────────────────────────
  StreamSubscription<String>? _barcodeScanSubscription;

  // ── Lifecycle ───────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    name = Get.arguments?['name'] ?? '';
    mode = Get.arguments?['mode'] ?? 'view';

    qtyController.addListener(_validateForm);
    itemController.addListener(_validateForm);

    // Subscribe to barcode scan events
    _barcodeScanSubscription = ScanService.instance.scanStream.listen((barcode) {
      if (canEdit && barcode.isNotEmpty) {
        itemController.text = barcode;
        searchItems(barcode);
      }
    });

    if (mode == 'new') {
      _initNew();
    } else {
      _fetchDocument();
    }
  }

  @override
  void onClose() {
    _barcodeScanSubscription?.cancel();
    itemController.dispose();
    bomController.dispose();
    qtyController.dispose();
    plannedStartController.dispose();
    expectedEndController.dispose();
    wipWarehouseController.dispose();
    fgWarehouseController.dispose();
    descriptionController.dispose();
    super.onClose();
  }

  bool get canEdit => workOrder.value?.docstatus == 0 || mode == 'new';
  bool get canSave =>
      isDirty.value && isItemValid.value && isBomValid.value && isQtyValid.value;

  // ── Computed: submit & job card guards ────────────────────────────────────────────

  /// True when the Work Order is a saved draft (docstatus 0, not new)
  /// and no other async operation is in progress.
  bool get canSubmit =>
      mode != 'new' &&
      workOrder.value?.docstatus == 0 &&
      !isSaving.value &&
      !isSubmitting.value;

  /// True when the Work Order is submitted (docstatus 1) and at least one
  /// operation still has pending qty remaining.
  bool get canCreateJobCards {
    final wo = workOrder.value;
    if (wo == null || wo.docstatus != 1) return false;
    if (isCreatingJobCards.value) return false;
    return operations.any(
      (op) => !op.isCompleted && op.pendingQty(wo.qty) > 0,
    );
  }

  // ── Init new ───────────────────────────────────────────────────────────────────────

  void _initNew() {
    final today = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    plannedStartController.text = today;
    qtyController.text = '1';

    // ── Apply prefill from BOM form / list ───────────────────────────────────
    final prefill =
        Get.arguments?['prefill'] as Map<String, dynamic>? ?? {};

    if (prefill.isNotEmpty) {
      final item     = prefill['production_item'] as String? ?? '';
      final itemName = prefill['item_name']        as String? ?? '';
      final bomNo    = prefill['bom_no']           as String? ?? '';
      final qty      = prefill['qty'];
      final wip      = prefill['wip_warehouse']    as String? ?? '';
      final fg       = prefill['fg_warehouse']     as String? ?? '';

      if (item.isNotEmpty) {
        itemController.text        = item;
        selectedItem.value         = item;
        selectedItemName.value     = itemName.isNotEmpty ? itemName : item;
        isItemValid.value          = true;
      }

      if (bomNo.isNotEmpty) {
        bomController.text = bomNo;
        selectedBom.value  = bomNo;
        isBomValid.value   = true;
      }

      if (qty != null) {
        final q = qty is double ? qty : (qty as num).toDouble();
        qtyController.text = q % 1 == 0 ? q.toInt().toString() : q.toString();
      }

      if (wip.isNotEmpty) wipWarehouseController.text = wip;
      if (fg.isNotEmpty)  fgWarehouseController.text  = fg;

      // If a BOM is prefilled skip the typeahead — load warehouses from it.
      if (bomNo.isNotEmpty && (wip.isEmpty || fg.isEmpty)) {
        isFetchingBom.value = true;
        _applyBom(bomNo).then((_) => isFetchingBom.value = false);
      }
    }
    // ───────────────────────────────────────────────────────────────────

    isLoading.value = false;
    isDirty.value   = prefill.isNotEmpty; // pre-dirtied if prefilled
    _validateForm();

    workOrder.value = WorkOrder(
      name:             'New Work Order',
      productionItem:   selectedItem.value ?? '',
      itemName:         selectedItemName.value ?? '',
      bomNo:            selectedBom.value ?? '',
      qty:              double.tryParse(qtyController.text) ?? 1,
      producedQty:      0,
      status:           'Draft',
      plannedStartDate: plannedStartController.text,
      docstatus:        0,
    );
  }

  // ── Fetch document ─────────────────────────────────────────────────────────────────

  Future<void> _fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getWorkOrder(name);
      if (res.statusCode == 200 && res.data['data'] != null) {
        final wo = WorkOrder.fromJson(res.data['data']);
        workOrder.value = wo;
        _populateControllers(wo);
        operations.assignAll(wo.operations);
        isDirty.value = false;
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load Work Order');
    } finally {
      isLoading.value = false;
    }
  }

  void _populateControllers(WorkOrder wo) {
    itemController.text        = wo.productionItem;
    selectedItem.value         = wo.productionItem;
    selectedItemName.value     = wo.itemName;
    bomController.text         = wo.bomNo;
    selectedBom.value          = wo.bomNo;
    qtyController.text         =
        wo.qty % 1 == 0 ? wo.qty.toInt().toString() : wo.qty.toString();
    plannedStartController.text = wo.plannedStartDate;
    expectedEndController.text  = wo.expectedEndDate ?? '';
    wipWarehouseController.text = wo.wip_warehouse   ?? '';
    fgWarehouseController.text  = wo.fg_warehouse    ?? '';
    descriptionController.text  = wo.description     ?? '';
    _validateForm();
  }

  /// Public so the form screen's onChanged callbacks can call it directly.
  void markDirty() {
    if (!isLoading.value) isDirty.value = true;
  }

  // ==========================================================================
  // BOM Workflow Documentation (Commit 7)
  // ==========================================================================
  // The Work Order form implements robust BOM (Bill of Materials) handling:
  //
  // 1. Auto-fetch: When an Item is selected, _autoLoadBom() automatically:
  //    - Searches for BOMs associated with the selected Item
  //    - Auto-selects if only one BOM exists
  //    - Populates bomOptions for manual selection if multiple BOMs exist
  //
  // 2. Auto-fill warehouses: _applyBom() fetches BOM details and:
  //    - Auto-fills WIP (Work In Progress) warehouse from BOM
  //    - Auto-fills FG (Finished Goods) warehouse from BOM
  //    - Only fills empty fields (preserves user input)
  //
  // 3. BOM validation: _validateForm() ensures:
  //    - selectedBom is not null/empty before form submission
  //    - isBomValid flag controls save button state
  //
  // 4. Manual BOM selection: onBomSelected() allows users to:
  //    - Pick from multiple BOMs via DocTypePickerBottomSheet
  //    - Change BOM after initial auto-selection
  // ==========================================================================


  void _validateForm() {
    isItemValid.value = (selectedItem.value ?? '').isNotEmpty;
    isBomValid.value  = (selectedBom.value  ?? '').isNotEmpty;
    final qty = double.tryParse(qtyController.text) ?? 0;
    isQtyValid.value  = qty > 0;
  }

  // ── Item search ───────────────────────────────────────────────────────────────────

  Future<void> searchItems(String query) async {
    if (query.length < 2) {
      itemOptions.clear();
      return;
    }
    isFetchingItems.value = true;
    try {
      final res = await _apiProvider.getDocumentList(
        'Item',
        filters: {
          'name': ['like', '%$query%'],
          'is_sales_item': 0,
        },
        fields: ['name', 'item_name'],
        limit: 20,
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        itemOptions.value = (res.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (_) {} finally {
      isFetchingItems.value = false;
    }
  }

  void onItemSelected(String itemCode) async {
    selectedItem.value     = itemCode;
    itemController.text    = itemCode;
    itemOptions.clear();

    try {
      final res = await _apiProvider.getDocument('Item', itemCode);
      if (res.statusCode == 200 && res.data['data'] != null) {
        selectedItemName.value = res.data['data']['item_name'] ?? itemCode;
      }
    } catch (_) {}

    bomController.clear();
    selectedBom.value = null;
    isBomValid.value  = false;
    bomOptions.clear();
    markDirty();
    _validateForm();
    await _autoLoadBom(itemCode);
  }

  /// Auto-fetch BOMs when Item is selected.
  /// Searches for BOMs, auto-selects if only one exists, or populates options for user selection.

  Future<void> _autoLoadBom(String itemCode) async {
    isFetchingBom.value = true;
    try {
      final res = await _provider.searchBoms(itemCode);
      if (res.statusCode == 200 && res.data['data'] != null) {
        final list = res.data['data'] as List;
        if (list.isNotEmpty) {
          await _applyBom(list.first['name'] as String);
          return;
        }
      }
      final res2 = await _provider.getBomsForItem(itemCode);
      if (res2.statusCode == 200 && res2.data['data'] != null) {
        final list2 = res2.data['data'] as List;
        if (list2.isNotEmpty) {
          bomOptions.value = list2.map((e) => e['name'] as String).toList();
          if (list2.length == 1) {
            await _applyBom(list2.first['name'] as String);
          }
        }
      }
    } catch (_) {} finally {
      isFetchingBom.value = false;
    }
  }

  Future<void> _applyBom(String bomName) async {
    try {
      final res = await _provider.getBom(bomName);
      if (res.statusCode == 200 && res.data['data'] != null) {
          /// Apply BOM to Work Order: Fetch BOM details and auto-fill warehouses.
  /// Only populates empty warehouse fields to preserve user input.

        final bom = res.data['data'];
        bomController.text = bomName;
        selectedBom.value  = bomName;
        if (wipWarehouseController.text.isEmpty) {
          wipWarehouseController.text = bom['wip_warehouse'] ?? '';
        }
        if (fgWarehouseController.text.isEmpty) {
          fgWarehouseController.text = bom['fg_warehouse'] ?? '';
        }
        markDirty();
        _validateForm();
      }
    } catch (_) {}
  }

  void onBomSelected(String bomName) async {
    bomOptions.clear();
    await _applyBom(bomName);
  }
  /// Handle manual BOM selection from DocTypePicker.
  /// Called when user picks a BOM from the bottom sheet picker.

  
  // ── Date + time picker ────────────────────────────────────────────────────────────────

  Future<void> pickDate(TextEditingController ctrl) async {
    if (!canEdit) return;
    final now = DateTime.now();

    DateTime initial = now;
    try {
      if (ctrl.text.isNotEmpty) {
        initial = ctrl.text.contains(' ')
            ? DateFormat('yyyy-MM-dd HH:mm:ss').parse(ctrl.text)
            : DateFormat('yyyy-MM-dd').parse(ctrl.text);
      }
    } catch (_) {}

    final pickedDate = await showDatePicker(
      context: Get.context!,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null) return;

    final initialTime = TimeOfDay(
      hour:   initial.hour,
      minute: initial.minute,
    );
    final pickedTime = await showTimePicker(
      context: Get.context!,
      initialTime: initialTime,
    );

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime?.hour   ?? 0,
      pickedTime?.minute ?? 0,
    );
    ctrl.text = DateFormat('yyyy-MM-dd HH:mm:ss').format(combined);
    markDirty();
  }

  // ── Warehouse picker (bottom sheet) ───────────────────────────────────────────────

  void showWarehousePicker(TextEditingController ctrl) {
    if (!canEdit) return;
    
    showDocTypePickerBottomSheet(
      config: DocTypePickerConfig(
        doctype: 'Warehouse',
        title: 'Select Warehouse',
        columns: [
          DocTypePickerColumn.primary(
            fieldname: 'name',
            label: 'Warehouse',
          ),
        ],
        filters: {'is_group': 0},
        allowRefresh: true,
      ),
      onSelect: (selected) {
        ctrl.text = selected['name'] as String;
        markDirty();
      },
    );
  }

    // ── BOM picker (bottom sheet) ──────────────────────────────────────────────────────
  void showBomPicker() {
    if (!canEdit) return;
    
    final selectedItemCode = selectedItem.value;
    if (selectedItemCode == null || selectedItemCode.isEmpty) {
      GlobalSnackbar.info(message: 'Select an item first to load BOMs');
      return;
    }

    showDocTypePickerBottomSheet(
      config: DocTypePickerConfig(
        doctype: 'BOM',
        title: 'Select BOM',
        columns: [
          DocTypePickerColumn.primary(
            fieldname: 'name',
            label: 'BOM',
          ),
          DocTypePickerColumn.subtitle(
            fieldname: 'item',
            label: 'Item',
          ),
        ],
        filters: {
          'item': selectedItemCode,
          'is_active': 1,
          'is_default': ['in', [0, 1]],
        },
        allowRefresh: true,
      ),
      onSelect: (selected) {
        final bomName = selected['name'] as String;
        onBomSelected(bomName);
      },
    );
  }    ),
    );
  }

  // ── Adjust qty ────────────────────────────────────────────────────────────────────

  void adjustQty(int delta) {
    if (!canEdit) return;
    final current = double.tryParse(qtyController.text) ?? 0;
    final newVal  = (current + delta).clamp(1, double.infinity);
    qtyController.text =
        newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
    markDirty();
  }

  // ── Save ─────────────────────────────────────────────────────────────────────────

  Future<void> save() async {
    if (isSaving.value || !canSave) return;
    isSaving.value = true;

    final qty = double.tryParse(qtyController.text) ?? 0;
    final data = <String, dynamic>{
      'production_item': selectedItem.value,
      'bom_no':          selectedBom.value,
      'qty':             qty,
      'planned_start_date': plannedStartController.text,
      if (expectedEndController.text.isNotEmpty)
        'expected_end_date': expectedEndController.text,
      if (wipWarehouseController.text.isNotEmpty)
        'wip_warehouse': wipWarehouseController.text,
      if (fgWarehouseController.text.isNotEmpty)
        'fg_warehouse': fgWarehouseController.text,
      if (descriptionController.text.isNotEmpty)
        'description': descriptionController.text,
    };

    try {
      if (mode == 'new') {
        final res = await _provider.createWorkOrder(data);
        if (res.statusCode == 200 && res.data['data'] != null) {
          name = res.data['data']['name'];
          mode = 'view';
          await _fetchDocument();
          GlobalSnackbar.success(message: 'Work Order $name created');
          isDirty.value = false;
        } else {
          GlobalSnackbar.error(message: 'Failed to create Work Order');
        }
      } else {
        data['modified'] = workOrder.value?.modified;
        final res = await _provider.updateWorkOrder(name, data);
        if (res.statusCode == 200) {
          await _fetchDocument();
          GlobalSnackbar.success(message: 'Work Order updated');
          isDirty.value = false;
        } else {
          GlobalSnackbar.error(message: 'Failed to update Work Order');
        }
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Save failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────────────

  /// Submit the Work Order (docstatus 0 → 1).
  ///
  /// Guarded by [canSubmit]. Shows a confirmation dialog before proceeding.
  /// On success refreshes the document so [operations], [canSubmit], and
  /// [canCreateJobCards] all update reactively in the UI.
  Future<void> submitWorkOrder() async {
    if (!canSubmit) return;

    final confirmed = await GlobalDialog.confirm(
      title: 'Submit Work Order',
      message:
          'Submitting will lock this Work Order for editing. Continue?',
      confirmText: 'Submit',
    );
    if (confirmed != true) return;

    isSubmitting.value = true;
    try {
      final res = await _provider.submitWorkOrder(name);
      if (res.statusCode == 200) {
        await _fetchDocument();
        GlobalSnackbar.success(message: 'Work Order $name submitted');
      } else {
        GlobalSnackbar.error(message: 'Failed to submit Work Order');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Submit failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isSubmitting.value = false;
    }
  }

  // ── Create Job Cards ──────────────────────────────────────────────────────────────

  /// Create Job Cards for [selected] operations.
  ///
  /// [qtys] maps `WorkOrderOperation.name` → qty to manufacture per Job Card.
  /// Called by [JobCardCreationSheet] after the user confirms selection.
  ///
  /// On success refreshes the document so the operations list reflects the
  /// updated statuses returned by ERPNext after card creation.
  Future<void> createJobCards(
    List<WorkOrderOperation> selected,
    Map<String, double> qtys,
  ) async {
    if (!canCreateJobCards || selected.isEmpty) return;

    isCreatingJobCards.value = true;
    try {
      final payload = selected.map((op) {
        final qty = qtys[op.name] ?? op.pendingQty(workOrder.value!.qty);
        return op.toJobCardPayload(qty: qty);
      }).toList();

      final res = await _provider.makeJobCard(name, payload);

      if (res.statusCode == 200) {
        await _fetchDocument();
        final count = selected.length;
        GlobalSnackbar.success(
          message: '$count Job Card${count == 1 ? '' : 's'} created',
        );
      } else {
        GlobalSnackbar.error(message: 'Failed to create Job Cards');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Job Card creation failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isCreatingJobCards.value = false;
    }
  }

  // ── Discard guard ────────────────────────────────────────────────────────────────

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────────

  /// Extract a human-readable message from a [DioException].
  /// Falls back to [fallback] when no message can be parsed.
  String _extractErrorMessage(DioException e, String fallback) {
    try {
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        final exc = data['exception']?.toString() ?? '';
        if (exc.isNotEmpty) return exc.split(':').last.trim();
        final msg = data['message']?.toString() ?? '';
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return fallback;
  }
}
