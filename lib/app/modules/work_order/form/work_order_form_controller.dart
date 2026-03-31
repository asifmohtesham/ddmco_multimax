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

  // ── Route args ────────────────────────────────────────────────────────────────────────────
  late String name;
  final JobCardProvider _jobCardProvider = Get.find<JobCardProvider>();
  final linkedJobCards = <JobCard>[].obs;
  final isFetchingLinkedCards = false.obs;
  late String mode; // 'new' | 'view'

  // ── Rx state ────────────────────────────────────────────────────────────────────────────
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

  // ── Dropdown / picker data ───────────────────────────────────────────────────────────────
  final bomOptions = <String>[].obs;
  final itemOptions = <String>[].obs;

  // ── Form controllers ───────────────────────────────────────────────────────────────────
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

  // ── Lifecycle ────────────────────────────────────────────────────────────────────────────
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

  // ── Computed: submit, execute & job card guards ──────────────────────────────
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

  bool get canCreateJobCards {
    final wo = workOrder.value;
    if (wo == null || wo.docstatus != 1) return false;
    if (isCreatingJobCards.value) return false;
    return operations.any(
      (op) => !op.isCompleted && op.pendingQty(wo.qty) > 0,
    );
  }

  // ── BarcodeScanMixin implementation ─────────────────────────────────────────────
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
    selectedBom.value = null;
    bomController.text = '';
    await _autoLoadBom(item.itemCode ?? '');
    update();
  }

  // ── Init new ─────────────────────────────────────────────────────────────────────────────
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

  // ── Fetch document ───────────────────────────────────────────────────────────────────────
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

  // ── Item search ────────────────────────────────────────────────────────────────────────
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

  // ── Date + time picker ──────────────────────────────────────────────────────────────────
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

  // ── Warehouse picker ───────────────────────────────────────────────────────────────────
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

  // ── BOM picker ──────────────────────────────────────────────────────────────────────
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
  }

  // ── Adjust qty ──────────────────────────────────────────────────────────────────────
  void adjustQty(int delta) {
    if (!canEdit) return;
    final current = double.tryParse(qtyController.text) ?? 0;
    final newVal = (current + delta).clamp(1, double.infinity);
    qtyController.text =
        newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
    markDirty();
  }

  // ── Save ─────────────────────────────────────────────────────────────────────────────
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

  // ── Submit ────────────────────────────────────────────────────────────────────────
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

  // ── Execute: Material Transfer for Manufacture ──────────────────────────────
  /// Flow:
  ///   1. Fetch pre-filled SE doc from ERPNext via make_stock_entry.
  ///   2. Show _MaterialTransferConfirmSheet: operator reviews items and
  ///      enters Batch No (picker) + Rack (text) for every item row.
  ///   3. Sheet returns the mutated seDoc with batch_no + custom_rack
  ///      injected into each items[] row, or null if cancelled.
  ///   4. POST the enriched seDoc to save it (gets name e.g. STE-00001).
  ///   5. PATCH docstatus=1 to submit it; ERPNext on_submit hook
  ///      updates WO status automatically.
  Future<void> executeWorkOrder() async {
    if (!canExecute) return;

    final wo = workOrder.value!;
    isExecuting.value = true;

    // Step 1: fetch the pre-filled SE doc.
    Map<String, dynamic> seDoc;
    try {
      final res = await _provider.getMaterialTransferForManufacture(
        name,
        qty: wo.qty,
      );
      if (res.statusCode != 200 || res.data['message'] == null) {
        GlobalSnackbar.error(
          message:
              'Could not build Material Transfer — check BOM and warehouses.',
        );
        isExecuting.value = false;
        return;
      }
      seDoc = Map<String, dynamic>.from(res.data['message'] as Map);
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message:
              _extractErrorMessage(e, 'Failed to build Material Transfer'));
      isExecuting.value = false;
      return;
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
      isExecuting.value = false;
      return;
    }

    // Step 2: show confirm sheet; get back the enriched seDoc or null.
    final enrichedDoc =
        await _showMaterialTransferConfirmSheet(seDoc: seDoc);
    if (enrichedDoc == null) {
      isExecuting.value = false;
      return;
    }

    // Step 3a: save (POST) the enriched SE.
    String seName;
    try {
      final saveRes = await _provider.saveStockEntry(enrichedDoc);
      if (saveRes.statusCode != 200 || saveRes.data['data'] == null) {
        GlobalSnackbar.error(
            message: 'Failed to save Material Transfer Stock Entry');
        isExecuting.value = false;
        return;
      }
      seName = saveRes.data['data']['name'] as String;
    } on DioException catch (e) {
      GlobalSnackbar.error(
          message: _extractErrorMessage(e, 'Failed to save Stock Entry'));
      isExecuting.value = false;
      return;
    } catch (e) {
      GlobalSnackbar.error(message: 'Error saving Stock Entry: $e');
      isExecuting.value = false;
      return;
    }

    // Step 3b: submit the saved SE.
    try {
      final submitRes = await _provider.submitStockEntry(seName);
      if (submitRes.statusCode == 200) {
        await _fetchDocument();
        GlobalSnackbar.success(
          message: 'Material Transfer $seName submitted. '
              'Work Order $name is now In Process.',
        );
      } else {
        GlobalSnackbar.error(
          message: 'Stock Entry $seName saved but could not be submitted. '
              'Submit it manually from the Stock Entry list.',
        );
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(
        message: _extractErrorMessage(
          e,
          'Stock Entry $seName saved but submit failed — submit manually.',
        ),
      );
    } catch (e) {
      GlobalSnackbar.error(message: 'Error submitting Stock Entry: $e');
    } finally {
      isExecuting.value = false;
    }
  }

  // ── Material Transfer confirm sheet ────────────────────────────────────────────
  /// Opens the confirm sheet and returns the **mutated** seDoc with
  /// batch_no and custom_rack set on every item row, or null if cancelled.
  Future<Map<String, dynamic>?> _showMaterialTransferConfirmSheet({
    required Map<String, dynamic> seDoc,
  }) {
    final completer = Completer<Map<String, dynamic>?>();
    showModalBottomSheet<void>(
      context: Get.context!,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(Get.context!).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MaterialTransferConfirmSheet(
        seDoc: seDoc,
        onConfirm: (enrichedDoc) {
          Navigator.of(Get.context!).pop();
          completer.complete(enrichedDoc);
        },
        onCancel: () {
          Navigator.of(Get.context!).pop();
          completer.complete(null);
        },
      ),
    ).then((_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  // ── Create Job Cards (public) ───────────────────────────────────────────────────
  Future<void> createJobCards(
    List<WorkOrderOperation> ops,
    Map<String, double> qtys,
  ) async {
    if (ops.isEmpty || isCreatingJobCards.value) return;
    isCreatingJobCards.value = true;
    try {
      final payload = ops.map((op) {
        final qty = qtys[op.name] ?? op.pendingQty(workOrder.value!.qty);
        return op.toJobCardPayload(qty: qty);
      }).toList();
      final res = await _provider.makeJobCard(name, payload);
      if (res.statusCode == 200) {
        await fetchLinkedJobCards();
        GlobalSnackbar.success(
          message:
              '${ops.length} Job Card${ops.length == 1 ? '' : 's'} created successfully',
        );
      } else {
        GlobalSnackbar.warning(
            message: 'Job Card creation failed. Please try again.');
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

  // ── Auto-create Job Cards (internal) ─────────────────────────────────────────────
  Future<void> _autoCreateJobCards() async {
    final wo = workOrder.value;
    if (wo == null) return;
    final eligibleOps = operations
        .where((op) => !op.isCompleted && op.pendingQty(wo.qty) > 0)
        .toList();
    if (eligibleOps.isEmpty) return;
    isCreatingJobCards.value = true;
    try {
      final payload = eligibleOps
          .map((op) => op.toJobCardPayload(qty: op.pendingQty(wo.qty)))
          .toList();
      final res = await _provider.makeJobCard(name, payload);
      if (res.statusCode == 200) {
        await fetchLinkedJobCards();
        GlobalSnackbar.success(
            message: '${eligibleOps.length} Job Card(s) created successfully');
      } else {
        GlobalSnackbar.warning(
          message: 'Work Order submitted but Job Card creation failed. '
              'Create them manually from the Job Cards section.',
        );
      }
    } on DioException catch (e) {
      GlobalSnackbar.warning(
          message: _extractErrorMessage(
              e, 'Job Card creation failed — create manually'));
    } catch (_) {
      GlobalSnackbar.warning(
          message: 'Job Card creation failed — create them manually.');
    } finally {
      isCreatingJobCards.value = false;
    }
  }

  // ── Confirm discard ────────────────────────────────────────────────────────────────────
  Future<void> confirmDiscard() async {
    final confirmed = await GlobalDialog.confirm(
      title: 'Discard Changes',
      message: 'You have unsaved changes. Discard and go back?',
      confirmText: 'Discard',
    );
    if (confirmed == true) Get.back();
  }

  // ── Error extraction helper ─────────────────────────────────────────────────────────
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
}

// ─────────────────────────────────────────────────────────────────────────────
// _MaterialTransferConfirmSheet
// ─────────────────────────────────────────────────────────────────────────────
/// StatefulWidget bottom sheet for reviewing the Material Transfer for
/// Manufacture Stock Entry before submission.
///
/// Each SE item row exposes two required fields:
///   - Batch No: tappable chip → opens a DocTypePickerBottomSheet filtered
///     to the item_code, showing batch_id + expiry_date. Required.
///   - Rack (custom_rack): free-text TextField. Required.
///
/// The "Confirm Transfer" button is disabled until every item has both
/// fields filled. On confirm, [onConfirm] is called with the mutated
/// seDoc (batch_no + custom_rack merged into each items[] row).
class _MaterialTransferConfirmSheet extends StatefulWidget {
  final Map<String, dynamic> seDoc;

  /// Called with the enriched seDoc when the operator confirms.
  final void Function(Map<String, dynamic> enrichedDoc) onConfirm;
  final VoidCallback onCancel;

  const _MaterialTransferConfirmSheet({
    required this.seDoc,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_MaterialTransferConfirmSheet> createState() =>
      _MaterialTransferConfirmSheetState();
}

class _MaterialTransferConfirmSheetState
    extends State<_MaterialTransferConfirmSheet> {
  // Per-item controllers keyed by list index.
  late final List<TextEditingController> _batchControllers;
  late final List<TextEditingController> _rackControllers;
  late final List<Map<String, dynamic>> _items;

  bool _showValidationError = false;

  @override
  void initState() {
    super.initState();
    _items =
        (widget.seDoc['items'] as List? ?? []).cast<Map<String, dynamic>>();
    _batchControllers =
        List.generate(_items.length, (_) => TextEditingController());
    _rackControllers =
        List.generate(_items.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _batchControllers) c.dispose();
    for (final c in _rackControllers) c.dispose();
    super.dispose();
  }

  bool get _allFilled {
    for (int i = 0; i < _items.length; i++) {
      if (_batchControllers[i].text.trim().isEmpty) return false;
      if (_rackControllers[i].text.trim().isEmpty) return false;
    }
    return _items.isNotEmpty;
  }

  Future<void> _pickBatch(int index) async {
    final itemCode = _items[index]['item_code'] as String? ?? '';
    final selected = await showDocTypePickerBottomSheet(
      context,
      config: DocTypePickerConfig(
        doctype: 'Batch',
        title: 'Select Batch — $itemCode',
        columns: [
          DocTypePickerColumn(
              fieldname: 'name', label: 'Batch ID', isPrimary: true),
          DocTypePickerColumn(
              fieldname: 'expiry_date',
              label: 'Expiry Date',
              isSecondary: true),
        ],
        filters: [
          ['Batch', 'item', '=', itemCode],
          ['Batch', 'disabled', '=', 0],
        ],
        allowRefresh: true,
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _batchControllers[index].text = selected['name'] as String;
        if (_showValidationError && _allFilled) {
          _showValidationError = false;
        }
      });
    }
  }

  void _handleConfirm() {
    if (!_allFilled) {
      setState(() => _showValidationError = true);
      return;
    }
    // Merge batch_no + custom_rack into each item row and return.
    final enrichedDoc =
        Map<String, dynamic>.from(widget.seDoc);
    final enrichedItems = _items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = Map<String, dynamic>.from(entry.value);
      item['batch_no'] = _batchControllers[i].text.trim();
      item['custom_rack'] = _rackControllers[i].text.trim();
      return item;
    }).toList();
    enrichedDoc['items'] = enrichedItems;
    widget.onConfirm(enrichedDoc);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          // ── Drag handle ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── Header ───────────────────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded,
                    size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Material Transfer for Manufacture',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Enter Batch No and Rack for every item before confirming.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Validation banner ───────────────────────────────────────────────
          if (_showValidationError)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Text(
                    'All items require Batch No and Rack',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // ── Items list ───────────────────────────────────────────────────────────
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No items found in the Stock Entry.\n'
                        'Ensure the BOM has raw materials defined.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = _items[i];
                      final qty = item['qty'];
                      final qtyStr = qty is double
                          ? (qty % 1 == 0
                              ? qty.toInt().toString()
                              : qty.toString())
                          : '$qty';
                      final uom = item['uom'] as String? ?? '';
                      final fromWh =
                          item['s_warehouse'] as String? ?? '—';
                      final toWh = item['t_warehouse'] as String? ?? '—';

                      final batchMissing = _showValidationError &&
                          _batchControllers[i].text.trim().isEmpty;
                      final rackMissing = _showValidationError &&
                          _rackControllers[i].text.trim().isEmpty;

                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Item name + qty header
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['item_name'] as String? ??
                                        item['item_code'] as String? ??
                                        'Unknown item',
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  '$qtyStr $uom',
                                  style:
                                      theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // Item code
                            Text(
                              item['item_code'] as String? ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55),
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Warehouse route
                            Row(
                              children: [
                                Icon(Icons.warehouse_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '$fromWh  →  $toWh',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.55),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Batch No (picker)
                            GestureDetector(
                              onTap: () => _pickBatch(i),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Batch No *',
                                  isDense: true,
                                  suffixIcon: const Icon(
                                      Icons.arrow_drop_down,
                                      size: 20),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: batchMissing
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.outline,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: theme.colorScheme.primary,
                                        width: 2),
                                  ),
                                  errorText: batchMissing
                                      ? 'Required'
                                      : null,
                                ),
                                child: Text(
                                  _batchControllers[i].text.isNotEmpty
                                      ? _batchControllers[i].text
                                      : 'Tap to select batch',
                                  style: _batchControllers[i]
                                          .text
                                          .isNotEmpty
                                      ? theme.textTheme.bodyMedium
                                      : theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurface
                                                  .withOpacity(0.4)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Rack (free text)
                            TextField(
                              controller: _rackControllers[i],
                              decoration: InputDecoration(
                                labelText: 'Rack *',
                                isDense: true,
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: rackMissing
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.outline,
                                  ),
                                ),
                                errorText:
                                    rackMissing ? 'Required' : null,
                              ),
                              onChanged: (_) {
                                if (_showValidationError && _allFilled) {
                                  setState(
                                      () => _showValidationError = false);
                                } else {
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // ── Action buttons ───────────────────────────────────────────────────
          const Divider(height: 1),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon:
                      const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Confirm Transfer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _items.isEmpty ? null : _handleConfirm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
