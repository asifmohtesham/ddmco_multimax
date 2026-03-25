import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/material_request/form/widgets/material_request_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';

class MaterialRequestFormController extends GetxController
    with OptimisticLockingMixin {
  final MaterialRequestProvider _provider =
      Get.find<MaterialRequestProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();

  String name = Get.arguments['name'] ?? '';
  String mode = Get.arguments['mode'] ?? 'view';

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;
  var isScanning = false.obs;

  var materialRequest = Rx<MaterialRequest?>(null);

  // ── Header form fields ──────────────────────────────────────────────────
  final selectedType = 'Material Transfer'.obs;
  final scheduleDateController = TextEditingController();
  final transactionDateController = TextEditingController();
  final setWarehouseController = TextEditingController();

  final List<String> requestTypes = [
    'Purchase',
    'Material Transfer',
    'Material Issue',
    'Manufacture',
    'Customer Provided',
  ];

  // ── Warehouse data ─────────────────────────────────────────────────────────
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── Item Sheet State ─────────────────────────────────────────────────────
  final itemFormKey = GlobalKey<FormState>();

  final bsQtyController = TextEditingController();
  final bsWarehouseController = TextEditingController();
  final bsDateController = TextEditingController();

  var bsMaxQty = 0.0.obs;
  var bsItemVariantOf = RxnString();

  var isFormDirty = false.obs;
  var isSheetValid = false.obs;
  var isAddingItem = false.obs;

  String _initialQty = '';
  String _initialWh = '';

  var currentItemCode = '';
  var currentItemName = '';
  var currentItemNameKey = RxnString();
  var isItemSheetOpen = false.obs;

  final TextEditingController barcodeController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  // ── Persistent scan worker ──────────────────────────────────────────────────
  Worker? _scanWorker;

  bool get isEditable => (materialRequest.value?.docstatus ?? 1) == 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    bsQtyController.addListener(validateSheet);
    bsWarehouseController.addListener(validateSheet);
    fetchWarehouses();

    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
    log('[MR:onInit] _scanWorker registered', name: 'MR');

    if (mode == 'new') {
      _initNewRequest();
    } else {
      fetchMaterialRequest();
    }
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    log('[MR:onClose] _scanWorker disposed', name: 'MR');
    scheduleDateController.dispose();
    transactionDateController.dispose();
    setWarehouseController.dispose();
    bsQtyController.dispose();
    bsDateController.dispose();
    bsWarehouseController.dispose();
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  @override
  Future<void> reloadDocument() async {
    await fetchMaterialRequest();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  // ── Raw scan entry point (DataWedge hardware trigger) ─────────────────────

  void _onRawScan(String code) {
    log('[MR:_onRawScan] code="$code" route=${Get.currentRoute}', name: 'MR');
    if (code.isEmpty) return;
    // Only handle scans when this form is the active route.
    if (Get.currentRoute != AppRoutes.MATERIAL_REQUEST_FORM) return;
    final clean = code.trim();
    barcodeController.text = clean;
    // If the item sheet is open, route directly to scanBarcode so the
    // sheet's field interactions are handled correctly.
    scanBarcode(clean);
  }

  // ── Warehouse ───────────────────────────────────────────────────────────────────

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList(
        'Warehouse',
        filters: {'is_group': 0},
        limit: 100,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  // ── Document init ──────────────────────────────────────────────────────────────

  void _initNewRequest() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    selectedType.value = 'Material Transfer';
    transactionDateController.text = dateStr;
    scheduleDateController.text = dateStr;
    setWarehouseController.clear();

    materialRequest.value = MaterialRequest(
      name: 'New Material Request',
      modified: dateStr,
      transactionDate: dateStr,
      scheduleDate: dateStr,
      status: 'Draft',
      docstatus: 0,
      materialRequestType: 'Material Transfer',
      items: [],
    );
    isLoading.value = false;
    isDirty.value = true;
  }

  Future<void> fetchMaterialRequest() async {
    isLoading.value = true;
    try {
      final response = await _provider.getMaterialRequest(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = MaterialRequest.fromJson(response.data['data']);
        materialRequest.value = entry;

        selectedType.value = entry.materialRequestType;
        transactionDateController.text = entry.transactionDate;
        scheduleDateController.text = entry.scheduleDate;
        setWarehouseController.text = entry.setWarehouse ?? '';

        isDirty.value = false;
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch document');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ── Dirty / Navigation ───────────────────────────────────────────────────────────

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  void _markDirty() {
    // Guard: do not dirty-flag a submitted document.
    if (!isLoading.value && !isDirty.value && isEditable) {
      isDirty.value = true;
    }
  }

  // ── Header field interactions ──────────────────────────────────────────────────

  void onTypeChanged(String? val) {
    if (val != null && val != selectedType.value) {
      selectedType.value = val;
      _markDirty();
    }
  }

  void onWarehouseChanged(String val) => _markDirty();

  void setDate(TextEditingController controller) async {
    if (materialRequest.value?.docstatus != 0) return;

    final DateTime? picked = await showDatePicker(
      context: Get.context!,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
      _markDirty();
    }
  }

  // ── Warehouse picker ────────────────────────────────────────────────────────────

  void showWarehousePicker({bool forItem = false}) {
    final searchCtrl = TextEditingController();
    final filteredList = warehouses.toList().obs;

    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const Text('Select Warehouse',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onChanged: (val) {
                if (val.isEmpty) {
                  filteredList.assignAll(warehouses);
                } else {
                  filteredList.assignAll(warehouses.where((w) =>
                      w.toLowerCase().contains(val.toLowerCase())));
                }
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() {
                if (isFetchingWarehouses.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (filteredList.isEmpty) {
                  return const Center(child: Text('No warehouses found'));
                }
                return ListView.separated(
                  itemCount: filteredList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final wh = filteredList[i];
                    return ListTile(
                      title: Text(wh),
                      onTap: () {
                        if (forItem) {
                          bsWarehouseController.text = wh;
                        } else {
                          setWarehouseController.text = wh;
                          onWarehouseChanged(wh);
                        }
                        Get.back();
                      },
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  // ── Item Sheet ───────────────────────────────────────────────────────────────────

  void openItemSheet({
    MaterialRequestItem? item,
    String? newCode,
    String? newName,
    String? variantOf,
  }) {
    bsQtyController.clear();
    bsDateController.text = scheduleDateController.text;
    bsWarehouseController.clear();
    bsMaxQty.value = 0;
    bsItemVariantOf.value = null;
    isFormDirty.value = false;
    isSheetValid.value = false;
    _initialQty = '';
    _initialWh = '';

    if (item != null) {
      currentItemCode = item.itemCode;
      currentItemName = item.itemName ?? item.itemCode;
      currentItemNameKey.value = item.name;
      bsItemVariantOf.value = variantOf ?? item.variantOf;

      final qtyStr = item.qty % 1 == 0
          ? item.qty.toInt().toString()
          : item.qty.toString();
      bsQtyController.text = qtyStr;
      bsWarehouseController.text = item.warehouse ?? '';

      _initialQty = qtyStr;
      _initialWh = item.warehouse ?? '';

      validateSheet();
    } else if (newCode != null && newCode.isNotEmpty) {
      currentItemCode = newCode;
      currentItemName = newName ?? newCode;
      currentItemNameKey.value = null;
      bsItemVariantOf.value = variantOf;
      bsWarehouseController.text = setWarehouseController.text;
      _initialQty = '';
      _initialWh = setWarehouseController.text;
    } else {
      currentItemCode = '';
      currentItemName = '';
      currentItemNameKey.value = null;
      bsItemVariantOf.value = null;
      bsWarehouseController.text = setWarehouseController.text;
      _initialQty = '';
      _initialWh = setWarehouseController.text;
    }

    isItemSheetOpen.value = true;
    showModalBottomSheet(
      context: Get.context!,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.90;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: MaterialRequestItemFormSheet(controller: this),
            ),
          ),
        );
      },
    ).whenComplete(() {
      isItemSheetOpen.value = false;
      barcodeController.clear();
    });
  }

  // ── Sheet validation ───────────────────────────────────────────────────────────

  void validateSheet() {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    bool valid = qty > 0 && currentItemCode.isNotEmpty;

    bool dirty = false;
    if (bsQtyController.text != _initialQty) dirty = true;
    if (bsWarehouseController.text != _initialWh) dirty = true;
    isFormDirty.value = dirty;

    if (currentItemNameKey.value != null && !dirty) valid = false;

    isSheetValid.value = valid;
  }

  void adjustSheetQty(int delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = current + delta;
    if (newVal < 0) return;
    bsQtyController.text =
        newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
    validateSheet();
  }

  // ── Save / Delete item ─────────────────────────────────────────────────────────────

  Future<void> saveItem() async {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0 || currentItemCode.isEmpty) return;

    isAddingItem.value = true;
    try {
      final currentItems = materialRequest.value?.items.toList() ?? [];

      if (currentItemNameKey.value != null) {
        final index = currentItems
            .indexWhere((i) => i.name == currentItemNameKey.value);
        if (index != -1) {
          final existing = currentItems[index];
          currentItems[index] = MaterialRequestItem(
            name: existing.name,
            itemCode: existing.itemCode,
            itemName: existing.itemName,
            qty: qty,
            receivedQty: existing.receivedQty,
            orderedQty: existing.orderedQty,
            actualQty: existing.actualQty,
            warehouse: bsWarehouseController.text,
            uom: existing.uom,
            description: existing.description,
            variantOf: existing.variantOf,
          );
        }
      } else {
        currentItems.add(MaterialRequestItem(
          name: 'local_${DateTime.now().millisecondsSinceEpoch}',
          itemCode: currentItemCode,
          itemName: currentItemName,
          qty: qty,
          warehouse: bsWarehouseController.text,
          description: currentItemName,
          variantOf: bsItemVariantOf.value,
        ));
      }

      materialRequest.update((val) {
        val?.items.assignAll(currentItems);
      });

      _markDirty();
    } finally {
      isAddingItem.value = false;
    }
  }

  void deleteItem(MaterialRequestItem item) {
    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message: 'Remove ${item.itemCode}?',
      onConfirm: () {
        final currentItems = materialRequest.value?.items.toList() ?? [];
        currentItems.remove(item);
        materialRequest.update((val) => val?.items.assignAll(currentItems));
        _markDirty();
      },
    );
  }

  // ── Barcode scan ─────────────────────────────────────────────────────────────────

  Future<void> scanBarcode(String code) async {
    if (code.isEmpty) return;
    if (checkStaleAndBlock()) return;
    if (!isEditable) {
      GlobalSnackbar.warning(message: 'Document is submitted.');
      return;
    }
    // When the item sheet is open a hardware scan should not re-open a
    // new sheet on top — silently drop it (the sheet has its own barcode
    // field for batch/rack resolution if needed in future).
    if (isItemSheetOpen.value) return;
    if (isScanning.value) return;

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(code);
      if (result.isSuccess && result.itemData != null) {
        openItemSheet(
          newCode: result.itemData!.itemCode,
          newName: result.itemData!.itemName,
          variantOf: result.itemData!.variantOf,
        );
      } else {
        GlobalSnackbar.error(message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan Error: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // ── Save document ───────────────────────────────────────────────────────────────

  Future<void> saveMaterialRequest() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    isSaving.value = true;

    final data = {
      'material_request_type': selectedType.value,
      'transaction_date': transactionDateController.text,
      'schedule_date': scheduleDateController.text,
      'set_warehouse': setWarehouseController.text,
      'modified': materialRequest.value?.modified,
      'items': materialRequest.value?.items.map((i) {
        final Map<String, dynamic> map = {
          'item_code': i.itemCode,
          'qty': i.qty,
          'schedule_date': scheduleDateController.text,
          'warehouse': i.warehouse,
        };
        final itemName = i.name;
        if (itemName != null && !itemName.startsWith('local_')) {
          map['name'] = itemName;
        }
        return map;
      }).toList(),
    };

    try {
      if (mode == 'new') {
        final response = await _provider.createMaterialRequest(data);
        if (response.statusCode == 200) {
          final created = response.data['data'];
          name = created['name'];
          mode = 'edit';
          await fetchMaterialRequest();
          GlobalSnackbar.success(message: 'Material Request Created');
        } else {
          GlobalSnackbar.error(message: 'Failed to create request');
        }
      } else {
        final response = await _provider.updateMaterialRequest(name, data);
        if (response.statusCode == 200) {
          await fetchMaterialRequest();
          GlobalSnackbar.success(message: 'Material Request Updated');
        } else {
          GlobalSnackbar.error(message: 'Failed to update request');
        }
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;

      String errorMessage = 'Save failed';
      if (e.response?.data is Map) {
        if (e.response!.data['exception'] != null) {
          errorMessage = e.response!.data['exception']
              .toString()
              .split(':')
              .last
              .trim();
        } else if (e.response!.data['_server_messages'] != null) {
          errorMessage = 'Validation Error: Check form details';
        }
      }
      GlobalSnackbar.error(message: errorMessage);
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}
