import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/barcode_scan_mixin.dart';
import 'package:multimax/app/data/mixins/dio_error_mixin.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/work_order_item_model.dart';
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/models/work_order_operation_model.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/work_order_execution_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/enums/save_result.dart';

class WorkOrderFormController extends GetxController with BarcodeScanMixin, DioErrorMixin {
  final WorkOrderProvider _provider = Get.find<WorkOrderProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── Route args ────────────────────────────────────────────────────────────
  late String name;
  final JobCardProvider _jobCardProvider = Get.find<JobCardProvider>();

  var linkedJobCards        = <JobCard>[].obs;
  var isFetchingLinkedCards = false.obs;

  /// True when every linked Job Card has status "Completed".
  bool get allJobCardsCompleted =>
      linkedJobCards.isNotEmpty &&
          linkedJobCards.every((jc) => jc.status == 'Completed');

  /// How many Job Cards have status "Completed".
  int get completedJobCardsCount =>
      linkedJobCards.where((jc) => jc.status == 'Completed').length;

  /// True when the WO is "In Process" AND all Job Cards are completed.
  /// Used to gate the "Finish Work Order" button.
  bool get canFinishWithJobCards {
    final wo = workOrder.value;
    if (wo?.status != 'In Process') return false;
    if (linkedJobCards.isEmpty) return true;  // no JCs → no gate
    return allJobCardsCompleted;
  }

  late String mode; // 'new' | 'view'

  // ── Rx state ──────────────────────────────────────────────────────────────
  final isLoading = true.obs;
  final isSaving = false.obs;
  final saveResult = SaveResult.idle.obs;
  final isDirty = false.obs;
  final isFetchingBom = false.obs;
  final isFetchingWarehouses = false.obs;
  final isFetchingItems = false.obs;
  final isCheckingTransfer = false.obs;
  final hasMaterialTransferSubmitted = false.obs;

  // ── Operations state ──────────────────────────────────────────────────────
  final isSubmitting = false.obs;
  final isExecuting = false.obs;
  final isCreatingJobCards = false.obs;
  final operations = <WorkOrderOperation>[].obs;
  final workOrder = Rx<WorkOrder?>(null);

  /// BOM operations cached when a BOM is selected in 'new' mode.
  /// Serialised into the WO creation payload so ERP pre-fills the
  /// operations child table, enabling Job Card creation after submit.
  final bomOperations = <BomOperation>[].obs;

  // ── Dropdown / picker data ────────────────────────────────────────────────
  final bomOptions = <String>[].obs;
  final itemOptions = <String>[].obs;

  // ── Form controllers ──────────────────────────────────────────────────────
  final itemController = TextEditingController();
  final bomController = TextEditingController();
  final qtyController = TextEditingController();
  final plannedStartController = TextEditingController();
  final expectedEndController = TextEditingController();
  final wipWarehouseController = TextEditingController();
  final fgWarehouseController = TextEditingController();
  final descriptionController = TextEditingController();

  // ── Observables for reactive UI ───────────────────────────────────────────
  final selectedItem = RxnString();
  final selectedBom = RxnString();
  final selectedItemName = RxnString();
  final isItemValid = false.obs;
  final isBomValid = false.obs;
  final isQtyValid = false.obs;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
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

  // ── Computed: submit, execute & job card guards ───────────────────────────
  bool get canSubmit =>
      mode != 'new' &&
      workOrder.value?.docstatus == 0 &&
      !isSaving.value &&
      !isSubmitting.value;

  bool get canExecute {
    final wo = workOrder.value;
    if (wo == null) return false;
    return wo.docstatus == 1 &&
        wo.status == 'Not Started' &&
        !isExecuting.value &&
        !isSubmitting.value &&
        !isCreatingJobCards.value;
  }

  /// True when the WO is "In Process" and not yet fully produced.
  /// Mirrors ERP's "Finish" button visibility: docstatus=1, status="In Process",
  /// and produced_qty < qty.
  bool get canFinish {
    final wo = workOrder.value;
    return wo?.docstatus == 1 &&
        wo?.status == 'In Process' &&
        canFinishWithJobCards &&      // ← NEW: all JCs must be Completed
        !isExecuting.value;
  }

  // "Create Job Cards" is only unlocked after a submitted
  // Material Transfer for Manufacture Stock Entry exists for this WO.
  // ERP requires transfer_material_against = "Job Card" WOs to have
  // material transferred (via a linked SE) before Job Cards can be created.
  bool get canCreateJobCards {
    final wo = workOrder.value;
    if (wo == null || wo.docstatus != 1) return false;
    if (isCreatingJobCards.value) return false;
    return operations.any(
      (op) => !op.isCompleted && op.pendingQty(wo.qty) > 0,
    );
  }

  // ── Reset helpers ─────────────────────────────────────────────────────────

  /// Clears every field that depends on the selected item.
  /// Call this whenever the item is changed or the X button is tapped.
  void _clearItemSelection() {
    itemController.clear();
    selectedItem.value = null;
    selectedItemName.value = null;
    _clearBomSelection();
    bomOptions.clear();
    isItemValid.value = false;
  }

  /// Clears every field that depends on the selected BOM.
  /// Call this whenever the BOM changes so stale ops are removed
  /// immediately — before the async _applyBom() round-trip completes.
  void _clearBomSelection() {
    bomController.clear();
    selectedBom.value = null;
    isBomValid.value = false;
    bomOperations.clear();
  }

  // ── BarcodeScanMixin implementation ───────────────────────────────────────
  @override
  Future<void> onScanResult(ScanResult result) async {
    if (!result.isSuccess || result.itemData == null) {
      Get.snackbar('Scan failed', result.message ?? 'Unknown error',
          snackPosition: SnackPosition.BOTTOM);
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
        Get.snackbar('Item not found',
            'No enabled stock item matched the scanned barcode. Tap the Item field to search manually.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      if (matches.length > 1) {
        Get.snackbar('Multiple matches found',
            'More than one item matched the scanned barcode. Tap the Item field to choose manually.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      await _applyScannedItemSelection(matches.first);
    } catch (e) {
      Get.snackbar('Scan failed',
          'Unable to process scanned barcode. Tap the Item field to search manually.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<List<Item>> _findMatchingItemsByBarcode(String barcode) async {
    final res = await _apiProvider.getDocumentList('Item',
        filters: {'disabled': 0, 'is_stock_item': 1});
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
    _clearBomSelection();
    await _autoLoadBom(item.itemCode ?? '');
    update();
  }

  // ── Init new ──────────────────────────────────────────────────────────────
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

      // Always fetch full BOM when a bomNo is prefilled so that
      // bomOperations is populated for the WO creation payload.
      if (bomNo.isNotEmpty) {
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

  // ── Fetch document ────────────────────────────────────────────────────────
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

  // Checks whether at least one submitted "Material Transfer for Manufacture"
  // Stock Entry exists for this Work Order.
  // Uses material_transferred_for_manufacturing from the WO itself —
  // ERP sets this > 0 only after a linked SE is submitted — so no
  // extra API call is needed.
  void _checkMaterialTransferSubmitted() {
    final wo = workOrder.value;
    if (wo == null) {
      hasMaterialTransferSubmitted.value = false;
      return;
    }
    // material_transferred_for_manufacturing is updated by ERP's
    // update_work_order_qty() on SE submit. If it is > 0, at least one
    // Material Transfer SE has been submitted for this WO.
    hasMaterialTransferSubmitted.value =
        (wo.materialTransferredForManufacturing ?? 0) > 0;
  }

  // ── Reload ────────────────────────────────────────────────────────────────
  /// Re-fetches the current Work Order document from the server and refreshes
  /// all form fields, operations, and linked Job Cards.
  /// No-op in 'new' mode (document has not been saved yet).
  Future<void> reload() async {
    if (mode == 'new') return;
    if (isLoading.value || isSaving.value) return;
    await _fetchDocument();
    GlobalSnackbar.success(message: 'Work Order reloaded');
  }

  Future<void> fetchLinkedJobCards() async {
    if (mode == 'new') return;
    isFetchingLinkedCards.value = true;
    try {
      final res = await _jobCardProvider.getJobCards(
        filters: {'work_order': ['=', name]},
        limit: 100,
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        linkedJobCards.value =
            (res.data['data'] as List).map((j) => JobCard.fromJson(j)).toList();
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
    wipWarehouseController.text = wo.wipWarehouse ?? '';
    fgWarehouseController.text = wo.fgWarehouse ?? '';
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

  // ── Item search ───────────────────────────────────────────────────────────
  Future<void> searchItems(String query) async {
    if (query.length < 2) {
      itemOptions.clear();
      return;
    }
    isFetchingItems.value = true;
    try {
      final res = await _apiProvider.getDocumentList(
        'Item',
        filters: {'name': ['like', '%$query%'], 'is_sales_item': 0},
        fields: ['name', 'item_name'],
        limit: 20,
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        itemOptions.value =
            (res.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (_) {} finally {
      isFetchingItems.value = false;
    }
  }

  // Responsibility 1: update observable state
  void _applyItemSelection(String itemCode) {
    selectedItem.value  = itemCode;
    itemController.text = itemCode;
    itemOptions.clear();
    _clearBomSelection();
    bomOptions.clear();
  }

  // Responsibility 2: fetch item display name
  Future<void> _fetchItemName(String itemCode) async {
    try {
      final res = await _apiProvider.getDocument('Item', itemCode);
      if (res.statusCode == 200 && res.data['data'] != null) {
        selectedItemName.value = res.data['data']['item_name'] ?? itemCode;
      }
    } catch (_) {}
  }

  // Coordinator: called by UI tap
  Future<void> onItemSelected(String itemCode) async {
    _applyItemSelection(itemCode);
    await _fetchItemName(itemCode);
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

  /// Applies a selected BOM: populates warehouses from BOM defaults and
  /// caches the BOM operations list for inclusion in the WO creation payload.
  Future<void> _applyBom(String bomName) async {
    try {
      final res = await _provider.getBom(bomName);
      if (res.statusCode == 200 && res.data['data'] != null) {
        final bom = BOM.fromJson(
            Map<String, dynamic>.from(res.data['data'] as Map));
        bomController.text = bomName;
        selectedBom.value  = bomName;
        if (wipWarehouseController.text.isEmpty) {
          wipWarehouseController.text = bom.defaultSourceWarehouse ?? '';
        }
        if (fgWarehouseController.text.isEmpty) {
          fgWarehouseController.text = bom.defaultTargetWarehouse ?? '';
        }
        // Cache BOM operations — sent to ERP during WO creation so the
        // operations child table is pre-filled without a second round-trip.
        bomOperations.assignAll(bom.operations);
        markDirty();
        _validateForm();
      }
    } catch (_) {}
  }

  void onBomSelected(String bomName) async {
    // Clear stale ops immediately — before the async round-trip —
    // so the preview widget collapses at once on BOM switch.
    _clearBomSelection();
    bomOptions.clear();
    await _applyBom(bomName);
  }

  // ── Date + time picker ────────────────────────────────────────────────────
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
    final initialTime = TimeOfDay(hour: initial.hour, minute: initial.minute);
    final pickedTime =
        await showTimePicker(context: Get.context!, initialTime: initialTime);
    final combined = DateTime(
      pickedDate.year, pickedDate.month, pickedDate.day,
      pickedTime?.hour ?? 0, pickedTime?.minute ?? 0,
    );
    ctrl.text = DateFormat('yyyy-MM-dd HH:mm:ss').format(combined);
    markDirty();
  }

  // ── Warehouse picker ──────────────────────────────────────────────────────
  Future<void> showWarehousePicker(TextEditingController ctrl) async {
    if (!canEdit) return;
    final selected = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Warehouse',
        title: 'Select Warehouse',
        columns: [
          DocTypePickerColumn(
              fieldname: 'name', label: 'Warehouse', isPrimary: true),
        ],
        filters: const [
          ['Warehouse', 'is_group', '=', 0]
        ],
        allowRefresh: true,
      ),
    );
    if (selected != null) {
      ctrl.text = selected['name'] as String;
      markDirty();
    }
  }

  // ── BOM picker ────────────────────────────────────────────────────────────
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
          DocTypePickerColumn(fieldname: 'name', label: 'BOM', isPrimary: true),
          DocTypePickerColumn(
              fieldname: 'item', label: 'Item', isSecondary: true),
        ],
        filters: [
          ['BOM', 'item', '=', selectedItemCode],
          ['BOM', 'is_active', '=', 1],
        ],
        allowRefresh: true,
      ),
    );
    if (selected != null) {
      onBomSelected(selected['name'] as String);
    }
    // If user dismisses the picker without selecting, existing
    // bomOperations are preserved — no clear needed here.
  }

  // ── Adjust qty ────────────────────────────────────────────────────────────
  void adjustQty(int delta) {
    if (!canEdit) return;
    final current = double.tryParse(qtyController.text) ?? 0;
    final newVal = (current + delta).clamp(1, double.infinity);
    qtyController.text =
        newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
    markDirty();
  }

  // ── Execute Work Order ────────────────────────────────────────────────────
  //
  // Sequence enforced by ERP:
  //   1. Ensure a Job Card exists (create via make_job_card if needed).
  //   2. Create Stock Entry with job_card field linked.
  //   3. Submit the Stock Entry.
  //
  // Without step 1+2, update_work_order_qty() skips
  // material_transferred_for_manufacturing (transfer_material_against="Job Card"
  // guard) and the WO status never transitions to "In Process".

  // ── Dependency ────────────────────────────────────────────────────────
  final WorkOrderExecutionService _executionService =
  Get.find<WorkOrderExecutionService>();

  /// Tap handler for "Execute Work Order" button.
  /// Validates the WO state, resolves the items payload, then navigates
  /// to the Stock Entry form with all WO data prefilled.
  /// No network calls are made here — the SE form handles its own save.
  Future<void> executeWorkOrder() async {
    if (!canExecute || isExecuting.value) return;

    final wo = workOrder.value!;

    // Items that still need material transfer (pending qty > 0).
    final pendingItems = wo.requiredItems
        .where((i) => i.pendingTransferQty > 0)
        .toList();

    if (pendingItems.isEmpty) {
      GlobalSnackbar.info(
        message: 'All materials already transferred for Work Order ${wo.name}.',
      );
      return;
    }

    _navigateToTransferEntry(wo, pendingItems);
  }

  /// Navigates to [AppRoutes.STOCK_ENTRY_FORM] with the Work Order's
  /// pending required items prefilled. The SE form's
  /// [StockEntrySource.workOrder] branch handles the rest.
  void _navigateToTransferEntry(
      WorkOrder wo,
      List<WorkOrderItem> items,
      ) {
    final targetWarehouse = wo.wipWarehouse ?? '';

    final itemsPayload = items
        .map((i) => i.toStockEntryItemPayload(targetWarehouse: targetWarehouse))
        .toList();

    Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {
      'name':             '',
      'mode':             'new',
      'stockEntryType':   'Material Transfer for Manufacture',
      'workOrderName':    wo.name,
      'fromWarehouse':    items.first.sourceWarehouse ?? '',
      'toWarehouse':      targetWarehouse,
      'items':            itemsPayload,
      // ── Required for ERP WO status transition ──────────────────────
      'fromBom':          true,             // sets from_bom = 1
      'bomNo':            wo.bomNo,         // links to BOM for qty validation
      'fgCompletedQty':   wo.qty,           // the WO's planned production qty
    });
  }

  // ── Finish Work Order ─────────────────────────────────────────────────────

  /// Tap handler for the "Finish" button.
  /// Navigates to the Stock Entry form prefilled to create
  /// a Stock Entry: Manufacture document for this Work Order.
  Future<void> finishWorkOrder() async {
    if (!canFinish || isExecuting.value) return;
    final wo = workOrder.value!;
    _navigateToManufactureEntry(wo);
  }

  /// Navigates to [AppRoutes.STOCK_ENTRY_FORM] prefilled for
  /// Stock Entry: Manufacture.
  ///
  /// ERP Manufacture SE moves the finished item from the WIP
  /// warehouse into the FG warehouse. The key fields are:
  ///   - stock_entry_type = 'Manufacture'
  ///   - work_order       = WO name
  ///   - from_bom         = 1
  ///   - bom_no           = WO's BOM
  ///   - fg_completed_qty = remaining qty to produce (qty - produced_qty)
  ///
  /// The SE form's [StockEntrySource.workOrder] branch populates the
  /// items table automatically using ERP's get_items_se() API,
  /// so no items payload is needed here.
  void _navigateToManufactureEntry(WorkOrder wo) {
    final remainingQty = wo.qty - wo.producedQty;

    Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {
      'name':           '',
      'mode':           'new',
      'stockEntryType': 'Manufacture',
      'workOrderName':  wo.name,
      'fromWarehouse':  wo.wipWarehouse ?? '',
      'toWarehouse':    wo.fgWarehouse  ?? '',
      'fromBom':        true,
      'bomNo':          wo.bomNo,
      'fgCompletedQty': remainingQty,
      // items is intentionally omitted — the SE form fetches BOM
      // components automatically for Manufacture type entries.
    });
  }

  // ── Payload builders ──────────────────────────────────────────────────────

  Map<String, dynamic> _buildBasePayload() => {
    'production_item':    selectedItem.value,
    'bom_no':             selectedBom.value,
    'qty':                double.tryParse(qtyController.text) ?? 0,
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

  Map<String, dynamic> _buildCreatePayload() {
    final data = _buildBasePayload();
    if (bomOperations.isNotEmpty) {
      final parentBom = selectedBom.value ?? '';
      data['operations'] = bomOperations.map((o) {
        final row = o.toWorkOrderOperationPayload();
        // Ensure the bom link is set — ERP requires it so the column
        // is visible in the Operations table after WO creation.
        if ((row['bom'] == null || (row['bom'] as String).isEmpty) &&
            parentBom.isNotEmpty) {
          row['bom'] = parentBom;
        }
        return row;
      }).toList();
    }
    return data;
  }

  Map<String, dynamic> _buildUpdatePayload() => {
    ..._buildBasePayload(),
    'modified': workOrder.value?.modified,
  };

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> save() async {
    if (isSaving.value || !canSave) return;
    isSaving.value = true;
    saveResult.value = SaveResult.idle;
    try {
      if (mode == 'new') {
        await _createWorkOrder();
      } else {
        await _updateWorkOrder();
      }
      saveResult.value = SaveResult.success;
    } on DioException catch (e) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Save failed'));
    } catch (e) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> _createWorkOrder() async {
    final res = await _provider.createWorkOrder(_buildCreatePayload());
    if (res.statusCode == 200 && res.data['data'] != null) {
      name = res.data['data']['name'];
      mode = 'view';
      await _fetchDocument();
      GlobalSnackbar.success(message: 'Work Order $name created');
      isDirty.value = false;
    } else {
      GlobalSnackbar.error(message: 'Failed to create Work Order');
    }
  }

  Future<void> _updateWorkOrder() async {
    final res = await _provider.updateWorkOrder(name, _buildUpdatePayload());
    if (res.statusCode == 200) {
      await _fetchDocument();
      GlobalSnackbar.success(message: 'Work Order updated');
      isDirty.value = false;
    } else {
      GlobalSnackbar.error(message: 'Failed to update Work Order');
    }
  }

  // ── Computed: job card presence guard ────────────────────────────────────
  /// True when at least one linked Job Card has been created for this WO.
  /// Used by the UI to gate "Execute Work Order" visibility.
  bool get hasLinkedJobCards => linkedJobCards.isNotEmpty;

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> submitDocument() async {
    if (!canSubmit) return;
    final confirmed = await GlobalDialog.confirm(
      title: 'Submit Work Order',
      message:
      'Submitting will lock this Work Order for editing. '
          'You can create Job Cards from the form after submitting. Continue?',
      confirmText: 'Submit',
    );
    if (confirmed != true) return;
    isSubmitting.value = true;
    try {
      final res = await _provider.submitWorkOrder(name);
      if (res.statusCode == 200) {
        await _fetchDocument();   // also calls fetchLinkedJobCards() internally
        GlobalSnackbar.success(message: 'Work Order $name submitted');
        unawaited(_checkAutoCreatedJobCards());
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

  // ── JC auto-creation feedback ─────────────────────────────────────────────

  /// Polls for auto-created Job Cards ~2 s after WO submit and shows a
  /// SnackBar with an action to navigate to the JC list, or an info message
  /// when none were created so the user knows to tap "Create Job Cards".
  Future<void> _checkAutoCreatedJobCards() async {
    await Future.delayed(const Duration(seconds: 2));
    try {
      final res = await _jobCardProvider.getJobCards(
        filters: {'work_order': ['=', name]},
        limit: 10,
      );
      if (res.statusCode != 200) return;
      final list = (res.data['data'] as List?) ?? [];
      final count = list.length;

      if (count > 0) {
        linkedJobCards.assignAll(list.map((j) => JobCard.fromJson(j)));
      }

      final ctx = Get.context;
      if (ctx == null) return;

      if (count > 0) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(
            '$count Job Card${count == 1 ? '' : 's'} created automatically',
          ),
          backgroundColor: const Color(0xFF388E3C),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => Get.toNamed(
              AppRoutes.JOB_CARD,
              arguments: {
                'filters': {'work_order': ['=', name]},
                'pageTitle': 'Job Cards – $name',
              },
            ),
          ),
        ));
      } else {
        GlobalSnackbar.info(
          message: 'No Job Cards were auto-created. '
              'Use "Create Job Cards" to set them up.',
        );
      }
    } catch (_) {
      // Non-fatal — WO was submitted successfully.
    }
  }

  // ── Create Job Cards (public) ─────────────────────────────────────────────
  Future<void> createJobCards(
      List<WorkOrderOperation> ops,
      Map<String, double> qtys,
      ) async {
    if (ops.isEmpty || isCreatingJobCards.value) return;
    isCreatingJobCards.value = true;

    int totalCreated = 0;
    final jobCardCreationStatus = ''.obs;
    // Compute the total number of JCs that will be created across all ops
    final int totalToCreate = ops.fold(0, (sum, op) {
      final qty = qtys[op.name] ?? op.pendingQty(workOrder.value!.qty);
      return sum + op.splitIntoBatches(qty).length;
    });

    try {
      for (final op in ops) {
        final totalQty = qtys[op.name] ?? op.pendingQty(workOrder.value!.qty);
        final batches  = op.splitIntoBatches(totalQty); // e.g. [60, 60]
        jobCardCreationStatus.value =
        'Creating JC ${totalCreated + 1} of $totalToCreate...';

        for (final batchQty in batches) {
          final payload = op.toJobCardPayload(qty: batchQty);
          final res = await _provider.makeJobCard(
            workOrderName: name,
            operations: [payload],   // one operation, one batch slice
          );
          if (res.statusCode == 200) {
            totalCreated++;
          } else {
            GlobalSnackbar.warning(
              message: 'Batch ${batches.indexOf(batchQty) + 1}/${batches.length} '
                  'for ${op.operation} failed.',
            );
          }
        }
      }

      if (totalCreated > 0) {
        await fetchLinkedJobCards();
        GlobalSnackbar.success(
          message: '$totalCreated Job Card${totalCreated == 1 ? '' : 's'} created',
        );
      }
    } on DioException catch (e) {
      GlobalSnackbar.warning(
          message: _extractErrorMessage(e, 'Job Card creation failed'));
    } catch (_) {
      GlobalSnackbar.warning(
          message: 'Job Card creation failed — please try again.');
    } finally {
      isCreatingJobCards.value = false;
    }
  }

  // ── Confirm discard ───────────────────────────────────────────────────────
  Future<void> confirmDiscard() async {
    final confirmed = await GlobalDialog.confirm(
      title: 'Discard Changes',
      message: 'You have unsaved changes. Discard and go back?',
      confirmText: 'Discard',
    );
    if (confirmed == true) Get.back();
  }

  // ── Error extraction helper ───────────────────────────────────────────────
  String _extractErrorMessage(DioException e, String fallback) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        final exc = data['exception'] as String? ?? '';
        if (exc.isNotEmpty) {
          final colonIdx = exc.indexOf(':');
          if (colonIdx != -1 && colonIdx < exc.length - 1) {
            return exc.substring(colonIdx + 1).trim();
          }
          return exc.trim();
        }
        final msg = data['message'] as String? ?? '';
        if (msg.isNotEmpty) return msg.trim();
      }
    } catch (_) {}
    return fallback;
  }

  // ── Set workstation on an operation row ──────────────────────────────────
  Future<void> showWorkstationPicker(WorkOrderOperation op) async {
    final selected = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Workstation',
        title: 'Set Workstation — ${op.operation}',
        columns: [
          DocTypePickerColumn(
              fieldname: 'name', label: 'Workstation', isPrimary: true),
          DocTypePickerColumn(
              fieldname: 'workstation_type',
              label: 'Type',
              isSecondary: true),
        ],
        allowRefresh: true,
      ),
    );
    if (selected == null) return;

    final newWorkstation = selected['name'] as String;

    // Optimistically update the local list so the UI reacts immediately.
    final idx = operations.indexWhere((o) => o.name == op.name);
    if (idx == -1) return;
    operations[idx] = operations[idx].copyWith(workstation: newWorkstation);
    operations.refresh();

    // Persist to ERP: patch just the child row.
    try {
      final res = await _provider.updateWorkOrderOperationWorkstation(
        workOrderName: name,
        operationRowName: op.name,
        workstation: newWorkstation,
      );
      if (res.statusCode != 200) {
        GlobalSnackbar.error(message: 'Failed to save workstation');
        // Roll back optimistic update.
        operations[idx] = op;
        operations.refresh();
      } else {
        GlobalSnackbar.success(message: 'Workstation set to $newWorkstation');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Save failed'));
      operations[idx] = op;
      operations.refresh();
    }
  }

  // ── Set source warehouse on an operation row ────────────────────────────
  Future<void> showSourceWarehousePicker(WorkOrderOperation op) async {
    if (!canEdit) return;                          // Draft-only guard

    final selected = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Warehouse',
        title: 'Source Warehouse — ${op.operation}',
        columns: [
          DocTypePickerColumn(
              fieldname: 'name', label: 'Warehouse', isPrimary: true),
          DocTypePickerColumn(
              fieldname: 'warehouse_type',
              label: 'Type',
              isSecondary: true),
        ],
        allowRefresh: true,
      ),
    );
    if (selected == null) return;

    final newWarehouse = selected['name'] as String;
    final idx = operations.indexWhere((o) => o.name == op.name);
    if (idx == -1) return;

    // Optimistic update
    operations[idx] = operations[idx].copyWith(sourceWarehouse: newWarehouse);
    operations.refresh();

    try {
      final res = await _provider.updateOperationSourceWarehouse(
        operationRowName: op.name,
        sourceWarehouse: newWarehouse,
      );
      if (res.statusCode != 200) {
        GlobalSnackbar.error(message: 'Failed to save source warehouse');
        operations[idx] = op;
        operations.refresh();
      } else {
        GlobalSnackbar.success(message: 'Source warehouse set');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Save failed'));
      operations[idx] = op;
      operations.refresh();
    }
  }

  Future<void> showWorkstationTypePicker(WorkOrderOperation op) async {
    if (!canEdit) return;
    final selected = await showDocTypePickerBottomSheet(
      Get.context!,
      config: DocTypePickerConfig(
        doctype: 'Workstation Type',
        title: 'Set Workstation Type — ${op.operation}',
        columns: [
          DocTypePickerColumn(fieldname: 'name', label: 'Type', isPrimary: true),
        ],
        allowRefresh: true,
      ),
    );
    if (selected == null) return;
    final newType = selected['name'] as String;
    final idx = operations.indexWhere((o) => o.name == op.name);
    if (idx == -1) return;
    operations[idx] = operations[idx].copyWith(workstationType: newType);
    operations.refresh();
    try {
      final res = await _provider.updateOperationWorkstationType(
        operationRowName: op.name,
        workstationType: newType,
      );
      if (res.statusCode != 200) {
        GlobalSnackbar.error(message: 'Failed to save workstation type');
        operations[idx] = op; operations.refresh();
      } else {
        GlobalSnackbar.success(message: 'Workstation Type set to $newType');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Save failed'));
      operations[idx] = op; operations.refresh();
    }
  }

  Future<void> pickOperationPlannedStartTime(WorkOrderOperation op) async {
    if (!canEdit) return;
    final initial = _parseDatetime(op.plannedStartTime) ?? DateTime.now();
    final picked = await _pickDatetime(initial);
    if (picked == null) return;
    final formatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(picked);
    final idx = operations.indexWhere((o) => o.name == op.name);
    if (idx == -1) return;
    operations[idx] = operations[idx].copyWith(plannedStartTime: formatted);
    operations.refresh();
    try {
      final res = await _provider.updateOperationPlannedStartTime(
        operationRowName: op.name,
        plannedStartTime: formatted,
      );
      if (res.statusCode != 200) {
        GlobalSnackbar.error(message: 'Failed to save planned start time');
        operations[idx] = op; operations.refresh();
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Save failed'));
      operations[idx] = op; operations.refresh();
    }
  }

  /// Reuse the existing showDatePicker + showTimePicker pattern from pickDate().
  Future<DateTime?> _pickDatetime(DateTime initial) async {
    final date = await showDatePicker(
      context: Get.context!,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null) return null;
    final time = await showTimePicker(
      context: Get.context!,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    return DateTime(date.year, date.month, date.day,
        time?.hour ?? 0, time?.minute ?? 0);
  }

  DateTime? _parseDatetime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return raw.contains('T')
          ? DateTime.parse(raw)
          : DateFormat('yyyy-MM-dd HH:mm:ss').parse(raw);
    } catch (_) { return null; }
  }

  Future<void> pickOperationPlannedEndTime(WorkOrderOperation op) async {
    if (!canEdit) return;
    final initial = _parseDatetime(op.plannedEndTime) ?? DateTime.now();
    final picked = await _pickDatetime(initial);
    if (picked == null) return;
    final formatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(picked);
    final idx = operations.indexWhere((o) => o.name == op.name);
    if (idx == -1) return;
    operations[idx] = operations[idx].copyWith(plannedEndTime: formatted);
    operations.refresh();
    try {
      final res = await _provider.updateOperationPlannedEndTime(
        operationRowName: op.name,
        plannedEndTime: formatted,
      );
      if (res.statusCode != 200) {
        GlobalSnackbar.error(message: 'Failed to save planned end time');
        operations[idx] = op; operations.refresh();
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(message: _extractErrorMessage(e, 'Save failed'));
      operations[idx] = op; operations.refresh();
    }
  }
}
