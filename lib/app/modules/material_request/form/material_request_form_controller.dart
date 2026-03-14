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
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';

class MaterialRequestFormController extends GetxController
    with OptimisticLockingMixin {
  final MaterialRequestProvider _provider =
      Get.find<MaterialRequestProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();

  String name = Get.arguments['name'] ?? '';
  String mode = Get.arguments['mode'] ?? 'view';

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;
  var isScanning = false.obs;

  var materialRequest = Rx<MaterialRequest?>(null);

  // ── Header form fields ───────────────────────────────────────────────────
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

  // ── Warehouse data ───────────────────────────────────────────────────────
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── Item Sheet State ─────────────────────────────────────────────────────
  //
  // Mirrors DeliveryNoteFormController exactly:
  //   itemFormKey    — required by GlobalItemFormSheet for Form.validate()
  //   isFormDirty    — true when any sheet field differs from its initial
  //                    snapshot; gates the "Update" button in edit mode
  //   _initialQty    — snapshot of qty when the sheet opened
  //   _initialWh     — snapshot of warehouse when the sheet opened
  //   bsItemVariantOf — variant_of of the item; shown as itemSubtext in header
  //   bsMaxQty        — available qty hint (0 = no stock concept for MR)
  //   isAddingItem    — loading spinner on save button

  final itemFormKey = GlobalKey<FormState>();

  final bsQtyController = TextEditingController();
  final bsWarehouseController = TextEditingController();
  final bsDateController = TextEditingController(); // schedule date pre-fill

  var bsMaxQty = 0.0.obs;
  var bsItemVariantOf = RxnString();

  var isFormDirty = false.obs;
  var isSheetValid = false.obs;
  var isAddingItem = false.obs;

  // Snapshots for dirty detection
  String _initialQty = '';
  String _initialWh = '';

  var currentItemCode = '';
  var currentItemName = '';
  var currentItemNameKey = RxnString();
  var isItemSheetOpen = false.obs;

  final TextEditingController barcodeController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  @override
  void onInit() {
    super.onInit();
    bsQtyController.addListener(validateSheet);
    bsWarehouseController.addListener(validateSheet);
    fetchWarehouses();

    if (mode == 'new') {
      _initNewRequest();
    } else {
      fetchMaterialRequest();
    }
  }

  @override
  Future<void> reloadDocument() async {
    await fetchMaterialRequest();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  @override
  void onClose() {
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

  // ── Warehouse ─────────────────────────────────────────────────────────────

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

  // ── Document init ─────────────────────────────────────────────────────────

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

  // ── Dirty / Navigation ────────────────────────────────────────────────────

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value) {
      isDirty.value = true;
    }
  }

  // ── Header field interactions ─────────────────────────────────────────────

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

  // ── Warehouse picker ──────────────────────────────────────────────────────

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
                          // validateSheet is called via bsWarehouseController listener
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

  // ── Item Sheet ────────────────────────────────────────────────────────────

  void openItemSheet({
    MaterialRequestItem? item,
    String? newCode,
    String? newName,
    String? variantOf,
  }) {
    // ── Reset sheet state ───────────────────────────────────────────────────
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
      // ── Edit mode ─────────────────────────────────────────────────────────
      currentItemCode = item.itemCode;
      currentItemName = item.itemName ?? item.itemCode;
      currentItemNameKey.value = item.name;
      bsItemVariantOf.value = variantOf ?? item.variantOf;

      final qtyStr = item.qty % 1 == 0
          ? item.qty.toInt().toString()
          : item.qty.toString();
      bsQtyController.text = qtyStr;
      bsWarehouseController.text = item.warehouse ?? '';

      // Snapshots for dirty detection
      _initialQty = qtyStr;
      _initialWh = item.warehouse ?? '';

      validateSheet();
    } else if (newCode != null && newCode.isNotEmpty) {
      // ── Add mode (barcode) ─────────────────────────────────────────────────
      currentItemCode = newCode;
      currentItemName = newName ?? newCode;
      currentItemNameKey.value = null;
      bsItemVariantOf.value = variantOf;
      bsWarehouseController.text = setWarehouseController.text;
      _initialQty = '';
      _initialWh = setWarehouseController.text;
    } else {
      // ── Add mode (manual) ──────────────────────────────────────────────────
      currentItemCode = '';
      currentItemName = '';
      currentItemNameKey.value = null;
      bsItemVariantOf.value = null;
      bsWarehouseController.text = setWarehouseController.text;
      _initialQty = '';
      _initialWh = setWarehouseController.text;
    }

    isItemSheetOpen.value = true;
    Get.bottomSheet(
      MaterialRequestItemFormSheet(controller: this),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  // ── Sheet validation ──────────────────────────────────────────────────────
  //
  // Mirrors DeliveryNoteFormController.validateSheet:
  //   1. Basic validity  — qty > 0
  //   2. Dirty detection — compares current values against _initial snapshots
  //   3. Edit-mode gate  — Update button disabled if !isFormDirty

  void validateSheet() {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    bool valid = qty > 0 && currentItemCode.isNotEmpty;

    // Dirty detection
    bool dirty = false;
    if (bsQtyController.text != _initialQty) dirty = true;
    if (bsWarehouseController.text != _initialWh) dirty = true;
    isFormDirty.value = dirty;

    // In edit mode the button is only enabled when the form is actually dirty
    if (currentItemNameKey.value != null && !dirty) valid = false;

    isSheetValid.value = valid;
  }

  /// Increment / decrement qty by [delta] (pass 1 or -1).
  ///
  /// Mirrors DeliveryNoteFormController / StockEntryFormController exactly:
  ///   - Never goes below 0
  ///   - Integer display when no fractional part
  ///   - Calls validateSheet() → isFormDirty is updated automatically
  ///     so increment/decrement on an existing item marks the sheet dirty
  ///     and enables the Update button immediately.
  void adjustSheetQty(int delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = current + delta;
    if (newVal < 0) return;
    bsQtyController.text =
        newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
    // validateSheet is triggered automatically via the bsQtyController listener
    // registered in onInit(), but call explicitly here as belt-and-suspenders.
    validateSheet();
  }

  // ── Save / Delete item ────────────────────────────────────────────────────

  Future<void> saveItem() async {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0 || currentItemCode.isEmpty) return;

    isAddingItem.value = true;
    try {
      final currentItems = materialRequest.value?.items.toList() ?? [];

      if (currentItemNameKey.value != null) {
        // Update existing
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
        // Add new
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

      // Mark document dirty BEFORE Navigator.pop so PopScope evaluates
      // the correct state immediately.
      _markDirty();

      // Sheet close is handled by GlobalItemFormSheet._popSheet
      // (Navigator.of(context).pop) — no Get.back() here.
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

  // ── Barcode scan ──────────────────────────────────────────────────────────

  Future<void> scanBarcode(String code) async {
    if (code.isEmpty) return;
    if (checkStaleAndBlock()) return;

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(code);
      if (result.isSuccess && result.itemData != null) {
        openItemSheet(
          newCode: result.itemData!.itemCode,
          newName: result.itemData!.itemName,
        );
      } else {
        GlobalSnackbar.error(message: 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan Error: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // ── Save document ─────────────────────────────────────────────────────────

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
