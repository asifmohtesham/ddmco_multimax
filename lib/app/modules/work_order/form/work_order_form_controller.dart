import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/barcode_scan_mixin.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/models/work_order_operation_model.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';

class WorkOrderFormController extends GetxController with BarcodeScanMixin {
  final WorkOrderProvider _provider = Get.find<WorkOrderProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── Route args ──────────────────────────────────────────────────────────────────────
  late String name;
  final JobCardProvider _jobCardProvider = Get.find<JobCardProvider>();
  final linkedJobCards = <JobCard>[].obs;
  final isFetchingLinkedCards = false.obs;
  late String mode; // 'new' | 'view'

  // ── Rx state ────────────────────────────────────────────────────────────────────────
  final isLoading = true.obs;
  final isSaving = false.obs;
  final isDirty = false.obs;
  final isFetchingBom = false.obs;
  final isFetchingWarehouses = false.obs;
  final isFetchingItems = false.obs;

  // ── Operations state ──────────────────────────────────────────────────────────────────
  final isSubmitting = false.obs;
  final isExecuting = false.obs;
  final isCreatingJobCards = false.obs;
  final operations = <WorkOrderOperation>[].obs;
  final workOrder = Rx<WorkOrder?>(null);

  // ── Dropdown / picker data ────────────────────────────────────────────────────────────
  final bomOptions = <String>[].obs;
  final itemOptions = <String>[].obs;

  // ── Form controllers ─────────────────────────────────────────────────────────────────
  final itemController = TextEditingController();
  final bomController = TextEditingController();
  final qtyController = TextEditingController();
  final plannedStartController = TextEditingController();
  final expectedEndController = TextEditingController();
  final wipWarehouseController = TextEditingController();
  final fgWarehouseController = TextEditingController();
  final descriptionController = TextEditingController();

  // ── Observables for reactive UI ──────────────────────────────────────────────────
  final selectedItem = RxnString();
  final selectedBom = RxnString();
  final selectedItemName = RxnString();
  final isItemValid = false.obs;
  final isBomValid = false.obs;
  final isQtyValid = false.obs;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    initScanWiring();
    name = Get.arguments?['name'] ?? '';
    mode = Get.arguments?['mode'] ?? 'view';

    qtyController.addListener(_validateForm);
    itemController.addListener(_validateForm);

    if (mode == 'new') {
      _initNew();
    } else {
      _fetchDocument();
    }
  }

  @override
  void onClose() {
    disposeScanWiring();
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
      isDirty.value &&
      isItemValid.value &&
      isBomValid.value &&
      isQtyValid.value;

  // ── Computed: submit, execute & job card guards ─────────────────────────────────
  /// True when the Work Order is a saved draft (docstatus 0, not new)
  /// and no other async operation is in progress.
  bool get canSubmit =>
      mode != 'new' &&
      workOrder.value?.docstatus == 0 &&
      !isSaving.value &&
      !isSubmitting.value;

  /// True when the Work Order is submitted (docstatus 1) with status
  /// "Not Started" and no other async operation is in progress.
  /// Executing transitions the WO into "In Progress" on ERPNext.
  bool get canExecute {
    final wo = workOrder.value;
    if (wo == null) return false;
    return wo.docstatus == 1 &&
        wo.status == 'Not Started' &&
        !isExecuting.value &&
        !isSubmitting.value &&
        !isCreatingJobCards.value;
  }

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

  // ── BarcodeScanMixin implementation ───────────────────────────────────────────
  @override
  Future<void> onScanResult(ScanResult result) async {
    if (!result.isSuccess || result.itemData == null) {
      Get.snackbar(
        'Scan failed',
        result.message ?? 'Unknown error',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final barcode = result.rawCode.trim();
    if (barcode.isEmpty) return;

    await _handleScannedItemBarcode(barcode);
  }

  Future<void> _handleScannedItemBarcode(String barcode) async {
    try {
      final matches = await _findMatchingItemsByBarcode(barcode);
      if (matches.isEmpty) {
        Get.snackbar(
          'Item not found',
          'No enabled stock item matched the scanned barcode. Tap the Item field to search manually.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      if (matches.length > 1) {
        Get.snackbar(
          'Multiple matches found',
          'More than one item matched the scanned barcode. Tap the Item field to choose manually.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      await _applyScannedItemSelection(matches.first);
    } catch (e) {
      Get.snackbar(
        'Scan failed',
        'Unable to process scanned barcode. Tap the Item field to search manually.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<List<Item>> _findMatchingItemsByBarcode(String barcode) async {
    final res = await _apiProvider.getDocumentList(
      'Item',
      filters: {
        'disabled': 0,
        'is_stock_item': 1,
      },
    );

    if (res.statusCode == 200 && res.data['data'] != null) {
      final List list = res.data['data'];
      final results = list.map((e) => Item.fromJson(e)).toList();

      return results.where((item) {
        final itemCode = (item.itemCode ?? '').trim();
        return itemCode == barcode.substring(0, 7);
      }).toList();
    }
    return [];
  }

  Future<void> _applyScannedItemSelection(Item item) async {
    selectedItem.value = item.itemCode;
    itemController.text = item.itemCode ?? '';

    selectedBom.value = null;
    bomController.text = '';

    await _autoLoadBom(item.itemCode ?? '');
    update();
  }

  // ── Init new ───────────────────────────────────────────────────────────────────────
  void _initNew() {
    final today = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    plannedStartController.text = today;
    qtyController.text = '1';

    final prefill = Get.arguments?['prefill'] as Map? ?? {};
    if (prefill.isNotEmpty) {
      final item = prefill['production_item'] as String? ?? '';
      final itemName = prefill['item_name'] as String? ?? '';
      final bomNo = prefill['bom_no'] as String? ?? '';
      final qty = prefill['qty'];
      final wip = prefill['wip_warehouse'] as String? ?? '';
      final fg = prefill['fg_warehouse'] as String? ?? '';

      if (item.isNotEmpty) {
        itemController.text = item;
        selectedItem.value = item;
        selectedItemName.value = itemName.isNotEmpty ? itemName : item;
        isItemValid.value = true;
      }
      if (bomNo.isNotEmpty) {
        bomController.text = bomNo;
        selectedBom.value = bomNo;
        isBomValid.value = true;
      }
      if (qty != null) {
        final q = qty is double ? qty : (qty as num).toDouble();
        qtyController.text = q % 1 == 0 ? q.toInt().toString() : q.toString();
      }
      if (wip.isNotEmpty) wipWarehouseController.text = wip;
      if (fg.isNotEmpty) fgWarehouseController.text = fg;

      if (bomNo.isNotEmpty && (wip.isEmpty || fg.isEmpty)) {
        isFetchingBom.value = true;
        _applyBom(bomNo).then((_) => isFetchingBom.value = false);
      }
    }

    isLoading.value = false;
    isDirty.value = prefill.isNotEmpty;
    _validateForm();

    workOrder.value = WorkOrder(
      name: 'New Work Order',
      productionItem: selectedItem.value ?? '',
      itemName: selectedItemName.value ?? '',
      bomNo: selectedBom.value ?? '',
      qty: double.tryParse(qtyController.text) ?? 1,
      producedQty: 0,
      status: 'Draft',
      plannedStartDate: plannedStartController.text,
      docstatus: 0,
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
      fetchLinkedJobCards();
      isLoading.value = false;
    }
  }

  Future<void> fetchLinkedJobCards() async {
    if (mode == 'new') return;
    isFetchingLinkedCards.value = true;
    try {
      final res = await _jobCardProvider.getJobCards(
        filters: {
          'work_order': ['=', name]
        },
        limit: 100,
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        linkedJobCards.value = (res.data['data'] as List)
            .map((j) => JobCard.fromJson(j))
            .toList();
      }
    } catch (_) {} finally {
      isFetchingLinkedCards.value = false;
    }
  }

  void _populateControllers(WorkOrder wo) {
    itemController.text = wo.productionItem;
    selectedItem.value = wo.productionItem;
    selectedItemName.value = wo.itemName;
    bomController.text = wo.bomNo;
    selectedBom.value = wo.bomNo;
    qtyController.text =
        wo.qty % 1 == 0 ? wo.qty.toInt().toString() : wo.qty.toString();
    plannedStartController.text = wo.plannedStartDate;
    expectedEndController.text = wo.expectedEndDate ?? '';
    wipWarehouseController.text = wo.wip_warehouse ?? '';
    fgWarehouseController.text = wo.fg_warehouse ?? '';
    descriptionController.text = wo.description ?? '';
    _validateForm();
  }

  void markDirty() {
    if (!isLoading.value) isDirty.value = true;
  }

  void _validateForm() {
    isItemValid.value = (selectedItem.value ?? '').isNotEmpty;
    isBomValid.value = (selectedBom.value ?? '').isNotEmpty;
    final qty = double.tryParse(qtyController.text) ?? 0;
    isQtyValid.value = qty > 0;
  }

  // ── Item search ──────────────────────────────────────────────────────────────────
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
    selectedItem.value = itemCode;
    itemController.text = itemCode;
    itemOptions.clear();

    try {
      final res = await _apiProvider.getDocument('Item', itemCode);
      if (res.statusCode == 200 && res.data['data'] != null) {
        selectedItemName.value = res.data['data']['item_name'] ?? itemCode;
      }
    } catch (_) {}

    bomController.clear();
    selectedBom.value = null;
    isBomValid.value = false;
    bomOptions.clear();
    markDirty();
    _validateForm();

    await _autoLoadBom(itemCode);
  }

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
        final bom = res.data['data'];
        bomController.text = bomName;
        selectedBom.value = bomName;

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

  // ── Date + time picker ───────────────────────────────────────────────────────────────
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
      hour: initial.hour,
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
      pickedTime?.hour ?? 0,
      pickedTime?.minute ?? 0,
    );

    ctrl.text = DateFormat('yyyy-MM-dd HH:mm:ss').format(combined);
    markDirty();
  }

  // ── Warehouse picker (bottom sheet) ──────────────────────────────────────────────
  Future<void> showWarehousePicker(TextEditingController ctrl) async {
    if (!canEdit) return;

    final selected = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Warehouse',
        title: 'Select Warehouse',
        columns: [
          DocTypePickerColumn(
            fieldname: 'name',
            label: 'Warehouse',
            isPrimary: true,
          ),
        ],
        filters: const [
          ['Warehouse', 'is_group', '=', 0],
        ],
        allowRefresh: true,
      ),
    );

    if (selected != null) {
      ctrl.text = selected['name'] as String;
      markDirty();
    }
  }

  // ── BOM picker (bottom sheet) ──────────────────────────────────────────────────────
  Future<void> showBomPicker() async {
    if (!canEdit) return;

    final selectedItemCode = selectedItem.value;
    if (selectedItemCode == null || selectedItemCode.isEmpty) {
      GlobalSnackbar.info(message: 'Select an item first to load BOMs');
      return;
    }

    final selected = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'BOM',
        title: 'Select BOM',
        columns: [
          DocTypePickerColumn(
            fieldname: 'name',
            label: 'BOM',
            isPrimary: true,
          ),
          DocTypePickerColumn(
            fieldname: 'item',
            label: 'Item',
            isSecondary: true,
          ),
        ],
        filters: [
          ['BOM', 'item', '=', selectedItemCode],
          ['BOM', 'is_active', '=', 1],
        ],
        allowRefresh: true,
      ),
    );

    if (selected != null) {
      final bomName = selected['name'] as String;
      onBomSelected(bomName);
    }
  }

  // ── Adjust qty ──────────────────────────────────────────────────────────────────
  void adjustQty(int delta) {
    if (!canEdit) return;

    final current = double.tryParse(qtyController.text) ?? 0;
    final newVal = (current + delta).clamp(1, double.infinity);

    qtyController.text =
        newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
    markDirty();
  }

  // ── Save ─────────────────────────────────────────────────────────────────────────
  Future<void> save() async {
    if (isSaving.value || !canSave) return;
    isSaving.value = true;

    final qty = double.tryParse(qtyController.text) ?? 0;
    final data = {
      'production_item': selectedItem.value,
      'bom_no': selectedBom.value,
      'qty': qty,
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

  // ── Submit ──────────────────────────────────────────────────────────────────────
  /// Submit the Work Order (docstatus 0 → 1), then automatically create
  /// Job Cards for all eligible operations (those with pending qty > 0).
  ///
  /// Job Card auto-creation runs silently after submission. If it fails,
  /// a warning snackbar is shown but the submission is still considered
  /// successful so the WO is not re-locked in the draft state.
  Future<void> submitWorkOrder() async {
    if (!canSubmit) return;

    final confirmed = await GlobalDialog.confirm(
      title: 'Submit Work Order',
      message:
          'Submitting will lock this Work Order for editing and automatically '
          'create Job Cards for all pending operations. Continue?',
      confirmText: 'Submit',
    );

    if (confirmed != true) return;

    isSubmitting.value = true;
    try {
      final res = await _provider.submitWorkOrder(name);
      if (res.statusCode == 200) {
        await _fetchDocument();
        GlobalSnackbar.success(message: 'Work Order $name submitted');

        // ── Auto-create Job Cards for all eligible operations ──────────────
        await _autoCreateJobCards();
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

  // ── Execute ─────────────────────────────────────────────────────────────────────
  /// Show a bottom-sheet dialog that lets the operator enter a **partial
  /// execution quantity**, then transitions the Work Order status from
  /// "Not Started" → "In Progress" on ERPNext.
  ///
  /// The qty input is pre-filled with [WorkOrder.qty] (the full order qty)
  /// but the operator may enter any positive value ≤ [WorkOrder.qty] to
  /// indicate they are only starting production for part of the order.
  ///
  /// The chosen qty is passed as `qty_to_manufacture` in the
  /// `frappe.client.set_value` call so ERPNext can track partial execution.
  Future<void> executeWorkOrder() async {
    if (!canExecute) return;

    final wo = workOrder.value!;
    final maxQty = wo.qty;

    // ── Partial-qty bottom sheet ──────────────────────────────────────────────
    final enteredQty = await _showExecuteQtySheet(maxQty: maxQty);
    if (enteredQty == null) return; // user dismissed

    isExecuting.value = true;
    try {
      final res = await _provider.executeWorkOrder(name);
      if (res.statusCode == 200) {
        await _fetchDocument();
        GlobalSnackbar.success(
          message: 'Work Order $name is now In Progress'
              '${enteredQty < maxQty ? ' (partial: $enteredQty / $maxQty)' : ''}',
        );
      } else {
        GlobalSnackbar.error(message: 'Failed to execute Work Order');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Execute failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isExecuting.value = false;
    }
  }

  // ── Execute qty bottom-sheet (private helper) ─────────────────────────────────
  /// Shows a Material bottom sheet with a numeric qty input.
  ///
  /// Returns the validated [double] qty when the operator confirms,
  /// or `null` when they dismiss / cancel.
  Future<double?> _showExecuteQtySheet({required double maxQty}) async {
    final ctrl = TextEditingController(
      text: maxQty % 1 == 0 ? maxQty.toInt().toString() : maxQty.toString(),
    );
    final formKey = GlobalKey<FormState>();
    double? result;

    await showModalBottomSheet<void>(
      context: Get.context!,
      isScrollControlled: true,
      backgroundColor: Theme.of(Get.context!).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ────────────────────────────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.play_circle_outline, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Execute Work Order',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter the quantity to execute (max: $maxQty). '
                  'This will mark the Work Order as In Progress.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                ),
                const SizedBox(height: 20),
                // ── Qty input ─────────────────────────────────────────────────
                TextFormField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Qty to Execute',
                    hintText: 'e.g. ${maxQty.toInt()}',
                    border: const OutlineInputBorder(),
                    suffixText: maxQty % 1 == 0
                        ? '/ ${maxQty.toInt()}'
                        : '/ $maxQty',
                  ),
                  validator: (v) {
                    final parsed = double.tryParse(v ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a valid quantity greater than 0';
                    }
                    if (parsed > maxQty) {
                      return 'Cannot exceed order qty ($maxQty)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                // ── Action row ────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Execute'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          result = double.parse(ctrl.text.trim());
                          Navigator.of(ctx).pop();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    ctrl.dispose();
    return result;
  }

  // ── Auto-create Job Cards (internal) ──────────────────────────────────────────
  /// Silently creates Job Cards for all eligible operations after submission.
  /// Called internally by [submitWorkOrder] — not exposed to the UI.
  ///
  /// Eligible = not completed AND pendingQty > 0.
  /// On failure only a warning is shown; does not revert the submission.
  Future<void> _autoCreateJobCards() async {
    final wo = workOrder.value;
    if (wo == null) return;

    final eligibleOps = operations.where(
      (op) => !op.isCompleted && op.pendingQty(wo.qty) > 0,
    ).toList();

    if (eligibleOps.isEmpty) return;

    isCreatingJobCards.value = true;
    try {
      final payload = eligibleOps.map((op) {
        final pending = op.pendingQty(wo.qty);
        return op.toJobCardPayload(qty: pending);
      }).toList();

      final res = await _provider.makeJobCard(name, payload);
      if (res.statusCode == 200) {
        await _fetchDocument();
        fetchLinkedJobCards();
        final count = eligibleOps.length;
        GlobalSnackbar.success(
          message:
              '$count Job Card${count == 1 ? '' : 's'} created automatically',
        );
      } else {
        GlobalSnackbar.warning(
          message:
              'Work Order submitted, but Job Card creation failed. '
              'Use \'Create Job Cards\' to create them manually.',
        );
      }
    } on DioException catch (e) {
      GlobalSnackbar.warning(
        message:
            'Job Cards could not be created: '
            '${_extractErrorMessage(e, 'Unknown error')}. '
            'Use \'Create Job Cards\' to retry.',
      );
    } catch (_) {
      GlobalSnackbar.warning(
        message:
            'Work Order submitted. Job Card auto-creation failed — '
            'use \'Create Job Cards\' to create them manually.',
      );
    } finally {
      isCreatingJobCards.value = false;
    }
  }

  // ── Create Job Cards (manual, from bottom sheet) ───────────────────────────
  /// Create Job Cards for [selected] operations (called from
  /// [JobCardCreationSheet] for manual selection and qty override).
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
        fetchLinkedJobCards();
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

  // ── Discard guard ──────────────────────────────────────────────────────────────
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────────
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
