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

  /// True when the Work Order is submitted (docstatus 1) with status
  /// 'Not Started' and no other async operation is in progress.
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
      filters: {'disabled': 0, 'is_stock_item': 1},
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
            fieldname: 'name',
            label: 'Warehouse',
            isPrimary: true,
          ),
        ],
        filters: const [['Warehouse', 'is_group', '=', 0]],
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
          DocTypePickerColumn(fieldname: 'item', label: 'Item', isSecondary: true),
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
  /// Executes the Work Order by creating and submitting a
  /// Material Transfer for Manufacture Stock Entry.
  ///
  /// Flow:
  ///   1. Call make_stock_entry to fetch a pre-filled SE document from ERPNext
  ///      (items, qtys, warehouses are all populated by the server).
  ///   2. Show _MaterialTransferConfirmSheet so the operator can review the
  ///      raw-material items and adjust the transfer qty before confirming.
  ///   3. On confirm: POST the SE doc to save it (ERPNext generates a name
  ///      like STE-00001), then PATCH docstatus=1 to submit it.
  ///   4. ERPNext's Stock Entry on_submit hook posts the stock ledger entries
  ///      and automatically updates the Work Order status to 'In Process'.
  ///
  /// The Work Order status is NEVER patched manually by the app.
  Future<void> executeWorkOrder() async {
    if (!canExecute) return;

    final wo = workOrder.value!;
    isExecuting.value = true;

    // Step 1: fetch the pre-filled SE doc from ERPNext.
    Map<String, dynamic> seDoc;
    try {
      final res = await _provider.getMaterialTransferForManufacture(
        name,
        qty: wo.qty,
      );
      if (res.statusCode != 200 || res.data['message'] == null) {
        GlobalSnackbar.error(
          message: 'Could not build Material Transfer — check BOM and warehouses.',
        );
        isExecuting.value = false;
        return;
      }
      // make_stock_entry returns the doc under the 'message' key.
      seDoc = Map<String, dynamic>.from(res.data['message'] as Map);
    } on DioException catch (e) {
      GlobalSnackbar.error(
        message: _extractErrorMessage(e, 'Failed to build Material Transfer'),
      );
      isExecuting.value = false;
      return;
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
      isExecuting.value = false;
      return;
    } finally {
      // Keep isExecuting true — we're still mid-flow. Only set false on
      // early-return error paths above or after the SE is submitted below.
    }

    // Step 2: show the confirmation sheet (items list + qty review).
    // isExecuting is still true so the button stays disabled while the
    // sheet is open.
    final confirmed = await _showMaterialTransferConfirmSheet(seDoc: seDoc);
    if (confirmed != true) {
      isExecuting.value = false;
      return;
    }

    // Step 3a: save (POST) the SE document to give it a real name.
    String seName;
    try {
      final saveRes = await _provider.saveStockEntry(seDoc);
      if (saveRes.statusCode != 200 || saveRes.data['data'] == null) {
        GlobalSnackbar.error(message: 'Failed to save Material Transfer Stock Entry');
        isExecuting.value = false;
        return;
      }
      seName = saveRes.data['data']['name'] as String;
    } on DioException catch (e) {
      GlobalSnackbar.error(
        message: _extractErrorMessage(e, 'Failed to save Stock Entry'),
      );
      isExecuting.value = false;
      return;
    } catch (e) {
      GlobalSnackbar.error(message: 'Error saving Stock Entry: $e');
      isExecuting.value = false;
      return;
    }

    // Step 3b: submit (PATCH docstatus=1) the saved SE.
    // ERPNext's on_submit hook updates the WO status automatically.
    try {
      final submitRes = await _provider.submitStockEntry(seName);
      if (submitRes.statusCode == 200) {
        // Refresh the WO so the updated status ('In Process') is reflected.
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

  // ── Material Transfer confirm sheet (private helper) ───────────────────────
  /// Shows a bottom sheet that displays all raw-material items in the
  /// pre-filled Stock Entry so the operator can review before confirming.
  ///
  /// Returns true when the operator taps 'Confirm Transfer', false/null
  /// when they dismiss or cancel.
  Future<bool?> _showMaterialTransferConfirmSheet({
    required Map<String, dynamic> seDoc,
  }) {
    final completer = Completer<bool?>();
    showModalBottomSheet<void>(
      context: Get.context!,
      isScrollControlled: true,
      backgroundColor: Theme.of(Get.context!).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MaterialTransferConfirmSheet(
        seDoc: seDoc,
        onConfirm: () {
          Navigator.of(Get.context!).pop();
          completer.complete(true);
        },
        onCancel: () {
          Navigator.of(Get.context!).pop();
          completer.complete(false);
        },
      ),
    ).then((_) {
      if (!completer.isCompleted) completer.complete(false);
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
          message: '${ops.length} Job Card${ops.length == 1 ? '' : 's'} created successfully',
        );
      } else {
        GlobalSnackbar.warning(message: 'Job Card creation failed. Please try again.');
      }
    } on DioException catch (e) {
      GlobalSnackbar.warning(
        message: _extractErrorMessage(e, 'Job Card creation failed'),
      );
    } catch (_) {
      GlobalSnackbar.warning(message: 'Job Card creation failed — please try again.');
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
          message: '${eligibleOps.length} Job Card(s) created successfully',
        );
      } else {
        GlobalSnackbar.warning(
          message: 'Work Order submitted but Job Card creation failed. '
              'Create them manually from the Job Cards section.',
        );
      }
    } on DioException catch (e) {
      GlobalSnackbar.warning(
        message: _extractErrorMessage(e, 'Job Card creation failed — create manually'),
      );
    } catch (_) {
      GlobalSnackbar.warning(message: 'Job Card creation failed — create them manually.');
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
/// Bottom sheet that shows the raw-material items in the pre-filled
/// Material Transfer for Manufacture Stock Entry so the operator can
/// verify what will be transferred before confirming submission.
///
/// The seDoc is the dict returned by ERPNext's make_stock_entry and contains
/// an 'items' list where each entry has:
///   item_code, item_name, qty, uom, s_warehouse (source), t_warehouse (target)
class _MaterialTransferConfirmSheet extends StatelessWidget {
  final Map<String, dynamic> seDoc;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _MaterialTransferConfirmSheet({
    required this.seDoc,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = (seDoc['items'] as List? ?? []).cast<Map<String, dynamic>>();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Column(
        children: [
          // ── Drag handle ─────────────────────────────────────────────────────
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                        'Review materials to be transferred to WIP warehouse.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Items list ───────────────────────────────────────────────────────────
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No items found in the Stock Entry.\n'
                        'Ensure the BOM has raw materials defined.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final qty = item['qty'];
                      final qtyStr = qty is double
                          ? (qty % 1 == 0
                              ? qty.toInt().toString()
                              : qty.toString())
                          : '$qty';
                      final uom = item['uom'] as String? ?? '';
                      final fromWh = item['s_warehouse'] as String? ?? '—';
                      final toWh = item['t_warehouse'] as String? ?? '—';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['item_name'] as String? ??
                                        item['item_code'] as String? ??
                                        'Unknown item',
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  '$qtyStr $uom',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['item_code'] as String? ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurface.withOpacity(0.55),
                              ),
                            ),
                            const SizedBox(height: 6),
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
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.55),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // ── Action buttons ─────────────────────────────────────────────────────
          const Divider(height: 1),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Confirm Transfer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: items.isEmpty ? null : onConfirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
