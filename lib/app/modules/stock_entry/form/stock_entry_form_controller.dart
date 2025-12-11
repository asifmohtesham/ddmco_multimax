import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

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

  var isDirty = false.obs;

  var stockEntry = Rx<StockEntry?>(null);

  // --- POS Grouping State ---
  var posUpload = Rx<PosUpload?>(null);
  var expandedInvoice = ''.obs;

  // Form Fields
  var selectedFromWarehouse = RxnString();
  var selectedToWarehouse = RxnString();
  final customReferenceNoController = TextEditingController();

  var stockEntryTypes = <String>[].obs;
  var isFetchingTypes = false.obs;
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

  // --- Row-Level Warehouse State (Derived from Rack) ---
  var derivedSourceWarehouse = RxnString();
  var derivedTargetWarehouse = RxnString();

  // --- Context State ---
  var isItemSheetOpen = false.obs;
  var bsMaxQty = 0.0.obs; // Tracks available stock limit

  var bsIsBatchReadOnly = false.obs;
  var bsIsBatchValid = false.obs;
  var isValidatingBatch = false.obs;

  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var isValidatingSourceRack = false.obs;
  var isValidatingTargetRack = false.obs;

  var rackError = RxnString();

  var isSheetValid = false.obs;

  var currentItemCode = '';
  var currentVariantOf = '';
  var currentItemName = '';
  var currentUom = '';

  var currentItemNameKey = RxnString();
  var selectedSerial = RxnString();

  final sourceRackFocusNode = FocusNode();
  final targetRackFocusNode = FocusNode();

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    fetchStockEntryTypes();

    ever(selectedFromWarehouse, (_) => _markDirty());
    ever(selectedToWarehouse, (_) => _markDirty());
    ever(selectedStockEntryType, (_) => _markDirty());

    customReferenceNoController.addListener(() {
      _onReferenceNoChanged();
      _markDirty();
    });

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

  // ... (POS Grouping, Fetch Data, Init Logic preserved) ...

  void toggleInvoiceExpand(String key) {
    if (expandedInvoice.value == key) {
      expandedInvoice.value = '';
    } else {
      expandedInvoice.value = key;
    }
  }

  Map<String, List<StockEntryItem>> get groupedItems {
    if (stockEntry.value == null || stockEntry.value!.items.isEmpty) {
      return {};
    }
    return groupBy(stockEntry.value!.items, (StockEntryItem item) {
      return item.customInvoiceSerialNumber ?? '0';
    });
  }

  Future<void> fetchStockEntryTypes() async {
    isFetchingTypes.value = true;
    try {
      final response = await _provider.getStockEntryTypes();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        stockEntryTypes.value = data.map((e) => e['name'].toString()).toList();
        if (stockEntryTypes.isNotEmpty && !stockEntryTypes.contains(selectedStockEntryType.value)) {
          selectedStockEntryType.value = stockEntryTypes.first;
        }
      }
    } catch (e) {
      print('Error fetching stock entry types: $e');
      if (stockEntryTypes.isEmpty) {
        stockEntryTypes.addAll(['Material Issue', 'Material Receipt', 'Material Transfer', 'Material Transfer for Manufacture']);
      }
    } finally {
      isFetchingTypes.value = false;
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
        GlobalSnackbar.error(message: 'Failed to fetch stock entry');
      }
    } catch (e) {
      GlobalSnackbar.error(message: e.toString());
    } finally {
      isLoading.value = false;
      isDirty.value = false;
    }
  }

  void _onReferenceNoChanged() {
    final ref = customReferenceNoController.text;
    if (ref.isNotEmpty) {
      _fetchPosUploadDetails(ref);
    } else {
      posUploadSerialOptions.clear();
      posUpload.value = null;
    }
  }

  Future<void> _fetchPosUploadDetails(String posId) async {
    try {
      final response = await _posProvider.getPosUpload(posId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final pos = PosUpload.fromJson(response.data['data']);
        posUpload.value = pos;
        final count = pos.items.length;
        posUploadSerialOptions.value = List.generate(count, (index) => (index + 1).toString());
      }
    } catch (e) {
      print('Error fetching POS Upload: $e');
    }
  }

  // --- Validation & Stock Logic ---

  void validateSheet() {
    rackError.value = null;

    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) {
      isSheetValid.value = false;
      return;
    }

    // New: Check against max allowed stock
    if (bsMaxQty.value > 0 && qty > bsMaxQty.value) {
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

    if (requiresSource && requiresTarget) {
      final source = bsSourceRackController.text.trim();
      final target = bsTargetRackController.text.trim();
      if (source.isNotEmpty && target.isNotEmpty && source == target) {
        isSheetValid.value = false;
        rackError.value = "Source and Target Racks cannot be the same";
        return;
      }
    }

    isSheetValid.value = true;
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta);
    // Clamp between 0 and max available stock (if defined)
    final double upperLimit = bsMaxQty.value > 0 ? bsMaxQty.value : 999999.0;

    if (newVal >= 0 && newVal <= upperLimit) {
      bsQtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
      validateSheet();
    }
  }

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;

    if (selectedStockEntryType.value == 'Material Transfer') {
      if (selectedFromWarehouse.value == null || selectedToWarehouse.value == null) {
        GlobalSnackbar.error(message: 'Source and Target Warehouses are required');
        return;
      }
      if (selectedFromWarehouse.value == selectedToWarehouse.value) {
        GlobalSnackbar.error(message: 'Source and Target Warehouses cannot be the same');
        return;
      }
    }

    isSaving.value = true;

    final Map<String, dynamic> data = {
      'stock_entry_type': selectedStockEntryType.value,
      'posting_date': stockEntry.value?.postingDate,
      'posting_time': stockEntry.value?.postingTime,
      'from_warehouse': selectedFromWarehouse.value,
      'to_warehouse': selectedToWarehouse.value,
      'custom_reference_no': customReferenceNoController.text,
    };

    final itemsJson = stockEntry.value?.items.map((i) {
      final json = i.toJson();
      if (json['name'] != null && json['name'].toString().startsWith('local_')) {
        json.remove('name');
      }
      if (json['basic_rate'] == 0.0) {
        json.remove('basic_rate');
      }
      return json;
    }).toList() ?? [];

    data['items'] = itemsJson;

    try {
      if (mode == 'new') {
        final response = await _provider.createStockEntry(data);
        if (response.statusCode == 200) {
          final createdDoc = response.data['data'];
          name = createdDoc['name'];
          mode = 'edit';
          await fetchStockEntry();
          GlobalSnackbar.success(message: 'Stock Entry created: $name');
        } else {
          GlobalSnackbar.error(message: 'Failed to create: ${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updateStockEntry(name, data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Stock Entry updated');
          await fetchStockEntry();
        } else {
          GlobalSnackbar.error(message: 'Failed to update: ${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } on DioException catch (e) {
      String errorMessage = 'Save failed';
      if (e.response != null && e.response!.data != null) {
        if (e.response!.data is Map && e.response!.data['exception'] != null) {
          errorMessage = e.response!.data['exception'].toString().split(':').last.trim();
        } else if (e.response!.data is Map && e.response!.data['_server_messages'] != null) {
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

  void _handleSheetRackScan(String code) {
    final type = selectedStockEntryType.value;

    if (type == 'Material Transfer' || type == 'Material Transfer for Manufacture') {
      if (bsSourceRackController.text.isEmpty) {
        bsSourceRackController.text = code;
        validateRack(code, true);
      } else {
        bsTargetRackController.text = code;
        validateRack(code, false);
      }
    } else if (type == 'Material Issue') {
      bsSourceRackController.text = code;
      validateRack(code, true);
    } else if (type == 'Material Receipt') {
      bsTargetRackController.text = code;
      validateRack(code, false);
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    if (isItemSheetOpen.value) {
      // Rack Detection Heuristic: contains hyphens and has multiple parts (e.g. WH-ZONE-RACK)
      if (barcode.contains('-') && barcode.split('-').length >= 3) {
        _handleSheetRackScan(barcode);
      } else {
        bsBatchController.text = barcode;
        validateBatch(barcode);
      }
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
        GlobalSnackbar.error(message: 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan failed: $e');
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

    derivedSourceWarehouse.value = null;
    derivedTargetWarehouse.value = null;
    bsMaxQty.value = 0.0; // Reset max qty

    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    isValidatingBatch.value = false;

    isSourceRackValid.value = false;
    isTargetRackValid.value = false;
    isSheetValid.value = false;
    rackError.value = null;

    selectedSerial.value = null;
    currentItemNameKey.value = null;

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
      rackError.value = null;
    });
  }

  // --- UPDATED STOCK CALCULATION LOGIC ---

  Future<void> _updateAvailableStock() async {
    // Only check if it's a source transaction (Issue or Transfer)
    final type = selectedStockEntryType.value;
    final isSourceOp = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

    if (!isSourceOp) {
      bsMaxQty.value = 999999.0; // No limit for receipt
      return;
    }

    // Determine constraints
    String? warehouse = derivedSourceWarehouse.value ?? selectedFromWarehouse.value;
    String batch = bsBatchController.text.trim();
    String rack = bsSourceRackController.text.trim();

    // If we don't have basic warehouse info, we can't check efficiently yet, or assume global stock?
    // Usually Stock Balance report requires at least Item Code.

    try {
      final filters = {
        'item_code': currentItemCode,
        'from_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'to_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      };

      // We use the generic Stock Balance report
      final response = await _apiProvider.getReport('Stock Balance', filters: filters);

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];

        // Client-side filtering to find the specific stock
        double totalBalance = 0.0;

        for (var row in result) {
          // Filter by Warehouse
          if (warehouse != null && warehouse.isNotEmpty && row['warehouse'] != warehouse) continue;

          // Filter by Batch (if entered)
          if (batch.isNotEmpty && row['batch_no'] != null && row['batch_no'] != batch) continue;

          // Filter by Rack (if entered and row has rack data)
          if (rack.isNotEmpty && row['rack'] != null && row['rack'] != rack) continue;

          // Add to balance
          totalBalance += (row['bal_qty'] as num?)?.toDouble() ?? 0.0;
        }

        bsMaxQty.value = totalBalance;

        // If rack was specific and balance is 0, warn user
        if (rack.isNotEmpty && totalBalance <= 0) {
          GlobalSnackbar.error(message: 'Insufficient stock in Rack: $rack');
          isSourceRackValid.value = false; // Invalidate rack
        }
      }
    } catch (e) {
      print('Failed to fetch stock balance: $e');
    }
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

        // Update stock limit based on this batch
        await _updateAvailableStock();

        GlobalSnackbar.success(message: 'Batch validated');
        // _focusNextField();
      } else {
        bsIsBatchValid.value = false;
        GlobalSnackbar.error(message: 'Batch not found for this item');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to validate batch: $e');
      bsIsBatchValid.value = false;
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  Future<void> validateRack(String rack, bool isSource) async {
    if (rack.isEmpty) return;

    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
        if (isSource) {
          derivedSourceWarehouse.value = wh;
        } else {
          derivedTargetWarehouse.value = wh;
        }
      }
    }

    if (isSource) isValidatingSourceRack.value = true;
    else isValidatingTargetRack.value = true;

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        if (isSource) {
          isSourceRackValid.value = true;
          // Validate Stock in this Rack immediately
          await _updateAvailableStock();
        } else {
          isTargetRackValid.value = true;
        }
      } else {
        if (isSource) isSourceRackValid.value = false;
        else isTargetRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
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

  void editItem(StockEntryItem item) {
    currentItemCode = item.itemCode;
    currentVariantOf = item.customVariantOf ?? '';
    currentItemName = item.itemName ?? '';
    currentItemNameKey.value = item.name;

    bsQtyController.text = item.qty.toString();
    bsBatchController.text = item.batchNo ?? '';
    bsSourceRackController.text = item.rack ?? '';
    bsTargetRackController.text = item.toRack ?? '';
    selectedSerial.value = item.customInvoiceSerialNumber;

    derivedSourceWarehouse.value = item.sWarehouse;
    derivedTargetWarehouse.value = item.tWarehouse;

    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;

    if (item.rack != null && item.rack!.isNotEmpty) isSourceRackValid.value = true;
    if (item.toRack != null && item.toRack!.isNotEmpty) isTargetRackValid.value = true;

    // Check stock for the item being edited to set constraints
    _updateAvailableStock();

    validateSheet();

    isItemSheetOpen.value = true;
    rackError.value = null;

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
      currentItemNameKey.value = null;
      rackError.value = null;
    });
  }

  void deleteItem(String uniqueName) {
    final currentItems = stockEntry.value?.items.toList() ?? [];
    currentItems.removeWhere((i) => i.name == uniqueName);

    stockEntry.update((val) {
      val?.items.assignAll(currentItems);
    });

    isDirty.value = true;
    GlobalSnackbar.success(message: 'Item removed');
  }

  void addItem() {
    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;

    final batch = bsBatchController.text;
    final String uniqueId = currentItemNameKey.value ?? 'local_${DateTime.now().millisecondsSinceEpoch}';

    final sWh = derivedSourceWarehouse.value ?? selectedFromWarehouse.value;
    final tWh = derivedTargetWarehouse.value ?? selectedToWarehouse.value;

    final newItem = StockEntryItem(
      name: uniqueId,
      itemCode: currentItemCode,
      qty: qty,
      basicRate: 0.0,
      itemGroup: null,
      customVariantOf: currentVariantOf,
      batchNo: batch,
      itemName: currentItemName,
      rack: bsSourceRackController.text,
      toRack: bsTargetRackController.text,
      sWarehouse: sWh,
      tWarehouse: tWh,
      customInvoiceSerialNumber: selectedSerial.value,
    );

    final currentItems = stockEntry.value?.items.toList() ?? [];
    final existingIndex = currentItems.indexWhere((i) => i.name == uniqueId);

    if (existingIndex != -1) {
      final oldItem = currentItems[existingIndex];
      currentItems[existingIndex] = StockEntryItem(
        name: oldItem.name,
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
    } else {
      currentItems.add(newItem);
    }

    stockEntry.update((val) {
      val?.items.assignAll(currentItems);
    });

    Get.back();

    if (mode == 'new') {
      saveStockEntry();
    } else {
      isDirty.value = true;
      GlobalSnackbar.success(message: existingIndex != -1 ? 'Item updated' : 'Item added');
    }
  }
}