import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';
import 'package:intl/intl.dart';

class StockEntryFormController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final PosUploadProvider _posProvider = Get.find<PosUploadProvider>();

  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  final String? argStockEntryType = Get.arguments['stockEntryType'];
  final String? argCustomReferenceNo = Get.arguments['customReferenceNo'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isSaving = false.obs;

  // --- Dirty Check State ---
  var isDirty = false.obs;

  var stockEntry = Rx<StockEntry?>(null);

  // Form Fields
  var selectedFromWarehouse = RxnString();
  var selectedToWarehouse = RxnString();
  final customReferenceNoController = TextEditingController();
  var selectedStockEntryType = 'Material Transfer'.obs;

  final TextEditingController barcodeController = TextEditingController();

  // Data Sources
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var posUploadSerialOptions = <String>[].obs;

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  final bsBatchController = TextEditingController();
  final bsSourceRackController = TextEditingController();
  final bsTargetRackController = TextEditingController();

  // --- Context State ---
  var isItemSheetOpen = false.obs;
  var editingItemIndex = RxnInt(); // Track which item is being edited (null = new)

  var bsIsBatchReadOnly = false.obs;
  var bsIsBatchValid = false.obs;
  var isValidatingBatch = false.obs;

  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var isValidatingSourceRack = false.obs;
  var isValidatingTargetRack = false.obs;

  // UX State
  var isSheetValid = false.obs;

  var currentItemCode = '';
  var currentVariantOf = '';
  var currentItemName = '';
  var currentUom = '';

  String? currentItemNameKey;
  var selectedSerial = RxnString();

  final List<String> stockEntryTypes = [
    'Material Issue',
    'Material Receipt',
    'Material Transfer',
    'Material Transfer for Manufacture'
  ];

  final sourceRackFocusNode = FocusNode();
  final targetRackFocusNode = FocusNode();

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();

    // Listeners for Dirty Check
    ever(selectedFromWarehouse, (_) => _markDirty());
    ever(selectedToWarehouse, (_) => _markDirty());
    ever(selectedStockEntryType, (_) => _markDirty());

    customReferenceNoController.addListener(() {
      _onReferenceNoChanged();
      _markDirty();
    });

    // Listen to changes for validation
    bsQtyController.addListener(validateSheet);
    bsBatchController.addListener(validateSheet);
    bsSourceRackController.addListener(validateSheet);
    bsTargetRackController.addListener(validateSheet);

    if (mode == 'new') {
      _initNewStockEntry();
    } else {
      fetchStockEntry();
    }
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value) {
      isDirty.value = true;
    }
  }

  @override
  void onClose() {
    barcodeController.dispose();
    bsQtyController.dispose();
    bsBatchController.dispose();
    bsSourceRackController.dispose();
    bsTargetRackController.dispose();
    sourceRackFocusNode.dispose();
    targetRackFocusNode.dispose();
    customReferenceNoController.dispose();
    super.onClose();
  }

  // --- Validation Logic ---

  void validateSheet() {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) {
      isSheetValid.value = false;
      return;
    }

    if (bsBatchController.text.isNotEmpty && !bsIsBatchValid.value) {
      isSheetValid.value = false;
      return;
    }

    final type = selectedStockEntryType.value;
    final requiresSource = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
    final requiresTarget = type == 'Material Receipt' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

    if (requiresSource) {
      if (bsSourceRackController.text.isEmpty || !isSourceRackValid.value) {
        isSheetValid.value = false;
        return;
      }
    }

    if (requiresTarget) {
      if (bsTargetRackController.text.isEmpty || !isTargetRackValid.value) {
        isSheetValid.value = false;
        return;
      }
    }

    isSheetValid.value = true;
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta).clamp(0.0, 999999.0);
    bsQtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
    validateSheet();
  }

  // --- Existing Methods ---

  void _onReferenceNoChanged() {
    final ref = customReferenceNoController.text;
    if (ref.isNotEmpty) {
      _fetchPosUploadDetails(ref);
    } else {
      posUploadSerialOptions.clear();
    }
  }

  Future<void> _fetchPosUploadDetails(String posId) async {
    try {
      final response = await _posProvider.getPosUpload(posId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final pos = PosUpload.fromJson(response.data['data']);
        final count = pos.items.length;
        posUploadSerialOptions.value = List.generate(count, (index) => (index + 1).toString());
      }
    } catch (e) {
      print('Error fetching POS Upload: $e');
    }
  }

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  void _initNewStockEntry() {
    isLoading.value = true;
    final now = DateTime.now();

    final initialType = argStockEntryType ?? 'Material Transfer';
    final initialRef = argCustomReferenceNo ?? '';

    stockEntry.value = StockEntry(
      name: 'New Stock Entry',
      purpose: initialType,
      totalAmount: 0.0,
      customTotalQty: 0.0,
      postingDate: DateFormat('yyyy-MM-dd').format(now),
      postingTime: DateFormat('HH:mm:ss').format(now),
      modified: '',
      creation: now.toString(),
      status: 'Draft',
      docstatus: 0,
      items: [],
      stockEntryType: initialType,
      fromWarehouse: '',
      toWarehouse: '',
      customReferenceNo: initialRef,
    );

    selectedStockEntryType.value = initialType;
    customReferenceNoController.text = initialRef;

    if (initialRef.isNotEmpty) {
      _fetchPosUploadDetails(initialRef);
    }

    isLoading.value = false;
    isDirty.value = false;
  }

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        stockEntry.value = entry;

        selectedFromWarehouse.value = entry.fromWarehouse;
        selectedToWarehouse.value = entry.toWarehouse;
        customReferenceNoController.text = entry.customReferenceNo ?? '';
        selectedStockEntryType.value = entry.stockEntryType ?? 'Material Transfer';

        if (entry.customReferenceNo != null && entry.customReferenceNo!.isNotEmpty) {
          _fetchPosUploadDetails(entry.customReferenceNo!);
        }
      } else {
        Get.snackbar('Error', 'Failed to fetch stock entry');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
      isDirty.value = false;
    }
  }

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;
    isSaving.value = true;

    final Map<String, dynamic> data = {
      'stock_entry_type': selectedStockEntryType.value,
      'posting_date': stockEntry.value?.postingDate,
      'posting_time': stockEntry.value?.postingTime,
      'from_warehouse': selectedFromWarehouse.value,
      'to_warehouse': selectedToWarehouse.value,
      'custom_reference_no': customReferenceNoController.text,
    };

    final itemsJson = stockEntry.value?.items.map((i) => i.toJson()).toList() ?? [];
    data['items'] = itemsJson;

    try {
      if (mode == 'new') {
        final response = await _provider.createStockEntry(data);
        if (response.statusCode == 200) {
          final createdDoc = response.data['data'];
          name = createdDoc['name'];
          mode = 'edit';

          await fetchStockEntry();
          Get.snackbar('Success', 'Stock Entry created: $name');
        } else {
          Get.snackbar('Error', 'Failed to create: ${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updateStockEntry(name, data);
        if (response.statusCode == 200) {
          Get.snackbar('Success', 'Stock Entry updated');
          await fetchStockEntry();
        } else {
          Get.snackbar('Error', 'Failed to update: ${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } catch (e) {
      Get.snackbar('Error', 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    if (isItemSheetOpen.value) {
      bsBatchController.text = barcode;
      validateBatch(barcode);
      return;
    }

    isScanning.value = true;

    String itemCode;
    String? batchNo;

    if (barcode.contains('-')) {
      final parts = barcode.split('-');
      final ean = parts.first;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = parts.join('-');
    } else {
      final ean = barcode;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = null;
    }

    try {
      final response = await _apiProvider.getDocument('Item', itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final itemData = response.data['data'];
        currentItemCode = itemData['item_code'];
        currentVariantOf = itemData['variant_of'];
        currentItemName = itemData['item_name'];
        currentUom = itemData['stock_uom'] ?? 'Nos';

        _openQtySheet(scannedBatch: batchNo);
      } else {
        Get.snackbar('Error', 'Item not found');
      }
    } catch (e) {
      Get.snackbar('Error', 'Scan failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  void _openQtySheet({String? scannedBatch}) {
    bsQtyController.clear();
    bsBatchController.clear();
    bsSourceRackController.clear();
    bsTargetRackController.clear();

    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    isValidatingBatch.value = false;

    isSourceRackValid.value = false;
    isTargetRackValid.value = false;

    isSheetValid.value = false;

    selectedSerial.value = null;
    currentItemNameKey = null;
    editingItemIndex.value = null;

    if (scannedBatch != null) {
      bsBatchController.text = scannedBatch;
      validateBatch(scannedBatch);
    }

    isItemSheetOpen.value = true;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StockEntryItemFormSheet(scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) return;

    isValidatingBatch.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Batch', filters: {
        'item': currentItemCode,
        'name': batch
      });

      if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true;
        Get.snackbar('Success', 'Batch validated', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 1));
        _focusNextField();
      } else {
        bsIsBatchValid.value = false;
        Get.snackbar('Error', 'Batch not found for this item');
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to validate batch: $e');
      bsIsBatchValid.value = false;
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  Future<void> validateRack(String rack, bool isSource) async {
    if (rack.isEmpty) return;

    if (isSource) isValidatingSourceRack.value = true;
    else isValidatingTargetRack.value = true;

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        if (isSource) isSourceRackValid.value = true;
        else isTargetRackValid.value = true;
      } else {
        if (isSource) isSourceRackValid.value = false;
        else isTargetRackValid.value = false;
        Get.snackbar('Error', 'Rack not found');
      }
    } catch (e) {
      if (isSource) isSourceRackValid.value = false;
      else isTargetRackValid.value = false;
    } finally {
      if (isSource) isValidatingSourceRack.value = false;
      else isValidatingTargetRack.value = false;
      validateSheet();
    }
  }

  void _focusNextField() {
    final type = selectedStockEntryType.value;
    final isMaterialIssue = type == 'Material Issue';
    final isMaterialReceipt = type == 'Material Receipt';
    final isMaterialTransfer = type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

    if (isMaterialIssue || isMaterialTransfer) {
      sourceRackFocusNode.requestFocus();
    } else if (isMaterialReceipt) {
      targetRackFocusNode.requestFocus();
    }
  }

  void editItem(StockEntryItem item, int index) {
    currentItemCode = item.itemCode;
    currentVariantOf = item.customVariantOf ?? '';
    currentItemName = item.itemName ?? '';
    currentItemNameKey = item.name;
    editingItemIndex.value = index;

    bsQtyController.text = item.qty.toString();
    bsBatchController.text = item.batchNo ?? '';
    bsSourceRackController.text = item.rack ?? '';
    bsTargetRackController.text = item.toRack ?? '';
    selectedSerial.value = item.customInvoiceSerialNumber;

    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;

    if (item.rack != null && item.rack!.isNotEmpty) isSourceRackValid.value = true;
    if (item.toRack != null && item.toRack!.isNotEmpty) isTargetRackValid.value = true;

    validateSheet();

    isItemSheetOpen.value = true;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StockEntryItemFormSheet(scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
      editingItemIndex.value = null;
    });
  }

  void deleteItem(int index) {
    if (index >= 0 && index < (stockEntry.value?.items.length ?? 0)) {
      final currentItems = stockEntry.value!.items.toList();
      currentItems.removeAt(index);

      stockEntry.update((val) {
        val?.items.assignAll(currentItems);
      });

      isDirty.value = true;
      Get.snackbar('Success', 'Item removed');
    }
  }

  void addItem() {
    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;

    final batch = bsBatchController.text;

    final newItem = StockEntryItem(
      itemCode: currentItemCode,
      qty: qty,
      basicRate: 0.0,
      itemGroup: null,
      customVariantOf: currentVariantOf,
      batchNo: batch,
      itemName: currentItemName,
      rack: bsSourceRackController.text,
      toRack: bsTargetRackController.text,
      sWarehouse: selectedFromWarehouse.value,
      tWarehouse: selectedToWarehouse.value,
      customInvoiceSerialNumber: selectedSerial.value,
    );

    final currentItems = stockEntry.value?.items.toList() ?? [];

    if (editingItemIndex.value != null) {
      // UPDATE EXISTING
      if (editingItemIndex.value! < currentItems.length) {
        final oldItem = currentItems[editingItemIndex.value!];

        currentItems[editingItemIndex.value!] = StockEntryItem(
          itemCode: newItem.itemCode,
          qty: newItem.qty,
          basicRate: oldItem.basicRate,
          itemGroup: oldItem.itemGroup,
          customVariantOf: newItem.customVariantOf,
          batchNo: newItem.batchNo,
          itemName: newItem.itemName,
          rack: newItem.rack,
          toRack: newItem.toRack,
          sWarehouse: newItem.sWarehouse,
          tWarehouse: newItem.tWarehouse,
          customInvoiceSerialNumber: newItem.customInvoiceSerialNumber,
        );
      }
    } else {
      // ADD NEW
      currentItems.add(newItem);
    }

    stockEntry.update((val) {
      val?.items.assignAll(currentItems);
    });

    Get.back();

    // Auto-Save if New Document
    if (mode == 'new') {
      saveStockEntry();
    } else {
      isDirty.value = true; // Mark dirty if editing existing doc
      Get.snackbar('Success', editingItemIndex.value != null ? 'Item updated' : 'Item added');
    }
  }
}