import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/modules/material_request/form/widgets/material_request_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:intl/intl.dart';

class MaterialRequestFormController extends GetxController {
  final MaterialRequestProvider _provider = Get.find<MaterialRequestProvider>();
  final ScanService _scanService = Get.find<ScanService>();

  String name = Get.arguments['name'] ?? '';
  String mode = Get.arguments['mode'] ?? 'view';

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;
  var isScanning = false.obs;

  var materialRequest = Rx<MaterialRequest?>(null);

  // Form Fields
  final selectedType = 'Material Transfer'.obs;
  final scheduleDateController = TextEditingController();
  final transactionDateController = TextEditingController();
  final setWarehouseController = TextEditingController();

  final List<String> requestTypes = [
    'Purchase',
    'Material Transfer',
    'Material Issue',
    'Manufacture',
    'Customer Provided'
  ];

  // Item Form State
  final bsQtyController = TextEditingController();
  final bsDateController = TextEditingController();

  // Item Sheet State
  var currentItemCode = '';
  var currentItemName = '';
  var currentUom = '';
  var currentItemNameKey = RxnString();
  var isItemSheetOpen = false.obs;
  var isSheetValid = false.obs;

  final TextEditingController barcodeController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  @override
  void onInit() {
    super.onInit();
    bsQtyController.addListener(validateSheet);

    if (mode == 'new') {
      _initNewRequest();
    } else {
      fetchMaterialRequest();
    }
  }

  @override
  void onClose() {
    scheduleDateController.dispose();
    transactionDateController.dispose();
    setWarehouseController.dispose();
    bsQtyController.dispose();
    bsDateController.dispose();
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  void _initNewRequest() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    selectedType.value = 'Material Transfer';
    transactionDateController.text = dateStr;
    scheduleDateController.text = dateStr;
    setWarehouseController.clear();

    materialRequest.value = MaterialRequest(
      name: 'New Material Request',
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

  // --- Dirty Check & Navigation ---

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back(); // Pop the screen
      },
    );
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value) {
      isDirty.value = true;
    }
  }

  // --- Form Interactions ---

  void onTypeChanged(String? val) {
    if (val != null && val != selectedType.value) {
      selectedType.value = val;
      _markDirty();
    }
  }

  void onWarehouseChanged(String val) {
    _markDirty();
  }

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

  // --- Item Management ---

  void openItemSheet({MaterialRequestItem? item, String? newCode, String? newName}) {
    bsQtyController.clear();
    bsDateController.text = scheduleDateController.text;
    isSheetValid.value = false;

    if (item != null) {
      currentItemCode = item.itemCode;
      currentItemName = item.itemName ?? item.itemCode;
      currentItemNameKey.value = item.name;
      bsQtyController.text = item.qty.toString();
      validateSheet();
    } else if (newCode != null && newCode.isNotEmpty) {
      currentItemCode = newCode;
      currentItemName = newName ?? newCode;
      currentItemNameKey.value = null;
    } else {
      currentItemCode = '';
      currentItemName = '';
      currentItemNameKey.value = null;
    }

    isItemSheetOpen.value = true;
    Get.bottomSheet(
      MaterialRequestItemFormSheet(controller: this),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  void validateSheet() {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    isSheetValid.value = qty > 0 && currentItemCode.isNotEmpty;
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta);
    if (newVal >= 0) {
      bsQtyController.text = newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
      validateSheet();
    }
  }

  Future<void> saveItem() async {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;
    if (currentItemCode.isEmpty) return;

    final currentItems = materialRequest.value?.items.toList() ?? [];

    if (currentItemNameKey.value != null) {
      final index = currentItems.indexWhere((i) => i.name == currentItemNameKey.value);
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
            warehouse: existing.warehouse,
            uom: existing.uom,
            description: existing.description
        );
      }
    } else {
      currentItems.add(MaterialRequestItem(
        name: 'local_${DateTime.now().millisecondsSinceEpoch}',
        itemCode: currentItemCode,
        itemName: currentItemName,
        qty: qty,
        description: currentItemName,
        // Default warehouse if header has one could be logic here, but backend usually handles it or UI prompts
      ));
    }

    materialRequest.update((val) {
      val?.items.assignAll(currentItems);
    });

    Get.back(); // Close sheet
    _markDirty();
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
        }
    );
  }

  Future<void> scanBarcode(String code) async {
    if (code.isEmpty) return;
    isScanning.value = true;
    try {
      final result = await _scanService.processScan(code);
      if (result.isSuccess && result.itemData != null) {
        openItemSheet(
            newCode: result.itemData!.itemCode,
            newName: result.itemData!.itemName
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

  Future<void> saveMaterialRequest() async {
    if (isSaving.value) return;
    isSaving.value = true;

    final data = {
      'material_request_type': selectedType.value,
      'transaction_date': transactionDateController.text,
      'schedule_date': scheduleDateController.text,
      'set_warehouse': setWarehouseController.text,
      'items': materialRequest.value?.items.map((i) {
        final Map<String, dynamic> map = {
          'item_code': i.itemCode,
          'qty': i.qty,
          'schedule_date': scheduleDateController.text,
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
        }
      } else {
        final response = await _provider.updateMaterialRequest(name, data);
        if (response.statusCode == 200) {
          await fetchMaterialRequest();
          GlobalSnackbar.success(message: 'Material Request Updated');
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to save: $e');
    } finally {
      isSaving.value = false;
    }
  }
}