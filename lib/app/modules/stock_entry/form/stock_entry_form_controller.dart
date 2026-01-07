import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

// Models
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';

// Providers
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';

// Services
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

// Widgets & Sheets
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';
import 'controllers/stock_entry_item_form_controller.dart';

enum StockEntrySource { manual, materialRequest, posUpload }

class StockEntryFormController extends GetxController {
  // --- Dependencies ---
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final PosUploadProvider _posProvider = Get.find<PosUploadProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();

  // --- Arguments & State ---
  String name = Get.arguments?['name'] ?? '';
  String mode = Get.arguments?['mode'] ?? 'view';

  // --- UI Controllers ---
  final ScrollController scrollController = ScrollController();
  final TextEditingController barcodeController = TextEditingController();
  final TextEditingController customReferenceNoController = TextEditingController();

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;
  var isScanning = false.obs;

  var stockEntry = Rxn<StockEntry>();

  // Header Fields
  var selectedStockEntryType = 'Material Transfer'.obs;
  var selectedFromWarehouse = RxnString();
  var selectedToWarehouse = RxnString();

  // Reference Data
  var warehouses = <String>[].obs;
  var stockEntryTypes = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var isFetchingTypes = false.obs;

  // Context Data
  var entrySource = StockEntrySource.manual;
  var mrReferenceItems = <Map<String, dynamic>>[];
  var posUpload = Rxn<PosUpload>();
  var posUploadSerialOptions = <String>[].obs;

  // UI State
  var isItemSheetOpen = false.obs;
  var recentlyAddedItemName = ''.obs;
  var expandedInvoice = ''.obs;
  final Map<String, GlobalKey> itemKeys = {};

  Worker? _scanWorker;

  // --- Computed Props ---
  Map<String, List<StockEntryItem>> get groupedItems {
    if (stockEntry.value == null) return {};
    // Group items by their serial number (invoice index) for POS view
    return groupBy(stockEntry.value!.items, (item) => item.customInvoiceSerialNumber ?? 'Other');
  }

  @override
  void onInit() {
    super.onInit();
    _initWorkers();
    _loadInitialData();
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    customReferenceNoController.dispose();
    scrollController.dispose();
    barcodeController.dispose();
    super.onClose();
  }

  // --- Initialization ---
  void _initWorkers() {
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) _handleGlobalScan(code);
    });

    ever(selectedFromWarehouse, (_) => _markDirty());
    ever(selectedToWarehouse, (_) => _markDirty());
    ever(selectedStockEntryType, (_) => _markDirty());

    customReferenceNoController.addListener(() {
      _markDirty();
      _checkPosUploadReference();
    });
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      fetchWarehouses(),
      _fetchStockEntryTypes(),
    ]);

    if (mode == 'new') {
      await _initNewStockEntry();
    } else {
      await _fetchExistingStockEntry();
    }
  }

  Future<void> _initNewStockEntry() async {
    isLoading.value = true;
    final type = Get.arguments?['stockEntryType'] ?? 'Material Transfer';
    final ref = Get.arguments?['customReferenceNo'] ?? '';

    selectedStockEntryType.value = type;
    customReferenceNoController.text = ref;

    _determineSource(type, ref);

    if (entrySource == StockEntrySource.materialRequest) {
      await _initMaterialRequestFlow(ref);
    } else if (entrySource == StockEntrySource.posUpload) {
      await _fetchPosUploadDetails(ref);
    }

    stockEntry.value = StockEntry(
      name: 'New Stock Entry',
      purpose: type,
      totalAmount: 0.0,
      postingDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      modified: '',
      creation: DateTime.now().toString(),
      status: 'Draft',
      docstatus: 0,
      stockEntryType: type,
      currency: 'AED',
      items: [],
      customReferenceNo: ref,
    );

    isLoading.value = false;
    isDirty.value = true;
  }

  // --- Core Methods ---

  void _determineSource(String type, String ref) {
    if (Get.arguments?['items'] != null) {
      entrySource = StockEntrySource.materialRequest;
    } else if (type == 'Material Issue' && (ref.startsWith('KX') || ref.startsWith('MX'))) {
      entrySource = StockEntrySource.posUpload;
    } else if (ref.isNotEmpty) {
      entrySource = StockEntrySource.materialRequest;
    } else {
      entrySource = StockEntrySource.manual;
    }
  }

  Future<void> _initMaterialRequestFlow(String ref) async {
    // Logic to fetch MR items if passed in args or via API
    if (Get.arguments?['items'] is List && Get.arguments?['items'].isNotEmpty) {
      final rawItems = Get.arguments['items'] as List;
      mrReferenceItems = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      try {
        final response = await _apiProvider.getDocument('Material Request', ref);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'];
          final items = data['items'] as List? ?? [];
          mrReferenceItems = items.map((i) => {
            'item_code': i['item_code'],
            'qty': i['qty'],
            'material_request': ref,
            'material_request_item': i['name']
          }).toList();
        }
      } catch (e) {
        GlobalSnackbar.error(message: 'Error fetching MR: $e');
      }
    }
  }

  void _checkPosUploadReference() {
    if (entrySource == StockEntrySource.manual &&
        selectedStockEntryType.value == 'Material Issue') {
      final ref = customReferenceNoController.text;
      if (ref.startsWith('KX') || ref.startsWith('MX')) {
        _fetchPosUploadDetails(ref);
      }
    }
  }

  Future<void> _fetchPosUploadDetails(String posId) async {
    try {
      final response = await _posProvider.getPosUpload(posId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final pos = PosUpload.fromJson(response.data['data']);
        posUpload.value = pos;
        posUploadSerialOptions.value = List.generate(pos.items.length, (index) => (index + 1).toString());
        entrySource = StockEntrySource.posUpload;
      }
    } catch (e) {
      print('Error fetching POS Upload: $e');
    }
  }

  // --- Scanning & UI Actions ---

  void _handleGlobalScan(String code) {
    if (isItemSheetOpen.value) {
      if (Get.isRegistered<StockEntryItemFormController>()) {
        Get.find<StockEntryItemFormController>().handleScan(code);
      }
    } else {
      _processNewItemScan(code);
    }
  }

  // Exposed for BarcodeInputWidget
  void scanBarcode(String code) => _handleGlobalScan(code);

  Future<void> _processNewItemScan(String barcode) async {
    if (isScanning.value) return;
    isScanning.value = true;

    try {
      final result = await _scanService.processScan(barcode);
      if (!result.isSuccess || result.itemData == null) {
        GlobalSnackbar.error(message: result.message ?? 'Scan failed');
        return;
      }

      if (!_validateItemContext(result.itemData!.itemCode)) return;

      _openItemSheet(
          itemCode: result.itemData!.itemCode,
          scannedBatch: result.batchNo,
          itemData: result.itemData
      );
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  bool _validateItemContext(String itemCode) {
    if (entrySource == StockEntrySource.materialRequest && mrReferenceItems.isNotEmpty) {
      final found = mrReferenceItems.any((item) =>
      item['item_code'].toString().trim().toLowerCase() == itemCode.trim().toLowerCase()
      );
      if (!found) {
        GlobalSnackbar.error(message: 'Item $itemCode not found in Material Request');
        return false;
      }
    }
    return true;
  }

  // --- Item Management ---

  void editItem(StockEntryItem item) => _openItemSheet(existingItem: item);

  void onAddItemTap() => _openItemSheet();

  void _openItemSheet({
    String? itemCode,
    String? scannedBatch,
    StockEntryItem? existingItem,
    dynamic itemData
  }) {
    final itemController = Get.put(StockEntryItemFormController());

    itemController.initialise(
        parentController: this,
        existingItem: existingItem,
        initialItemCode: itemCode,
        initialBatch: scannedBatch,
        scannedItemData: itemData
    );

    isItemSheetOpen.value = true;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => StockEntryItemFormSheet(
          controller: itemController,
          scrollController: scroll,
        ),
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
      Get.delete<StockEntryItemFormController>();
    });
  }

  void upsertItem(StockEntryItem newItem) {
    final currentItems = stockEntry.value?.items.toList() ?? [];
    final index = currentItems.indexWhere((i) => i.name == newItem.name);

    if (index != -1) {
      currentItems[index] = newItem;
    } else {
      currentItems.add(newItem);
    }

    stockEntry.update((val) => val?.items.assignAll(currentItems));
    _triggerHighlight(newItem.name ?? '');
    _autoSaveIfNew();
  }

  void deleteItem(String uniqueName) {
    final item = stockEntry.value?.items.firstWhereOrNull((i) => i.name == uniqueName);
    if (item == null) return;

    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message: 'Are you sure you want to remove ${item.itemCode}?',
      onConfirm: () {
        stockEntry.update((val) {
          val?.items.removeWhere((i) => i.name == uniqueName);
        });
        isDirty.value = true;
      },
    );
  }

  // --- Persistence & Logic ---

  Future<void> confirmDiscard() async {
    if (!isDirty.value) {
      Get.back();
      return;
    }
    GlobalDialog.showConfirmation(
      title: 'Discard Changes?',
      message: 'You have unsaved changes. Are you sure you want to leave?',
      onConfirm: () => Get.back(result: true),
    );
  }

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;
    isSaving.value = true;

    try {
      if (!_validateHeader()) return;
      final processedItems = await _processItemsForSave(stockEntry.value?.items ?? []);
      final payload = _buildSavePayload(processedItems);

      if (mode == 'new') {
        await _createEntry(payload);
      } else {
        await _updateEntry(payload);
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  bool _validateHeader() {
    if (selectedStockEntryType.value == 'Material Transfer' &&
        (selectedFromWarehouse.value == null || selectedToWarehouse.value == null)) {
      GlobalSnackbar.error(message: 'Source and Target Warehouses are required');
      return false;
    }
    return true;
  }

  Future<List<StockEntryItem>> _processItemsForSave(List<StockEntryItem> items) async {
    var updatedList = <StockEntryItem>[];
    for (var item in items) {
      // Logic: If useSerialBatchFields is 0 (false), we MUST ensure an SABB exists if there are entries
      if ((item.useSerialBatchFields == null || item.useSerialBatchFields == 0) && item.localBundle != null) {
        try {
          // Process Bundle (Create or Update based on existence of name)
          final bundleId = await _processSerialBatchBundle(item);
          updatedList.add(item.copyWith(serialAndBatchBundle: bundleId));
        } catch(e) { rethrow; }
      } else {
        updatedList.add(item);
      }
    }
    return updatedList;
  }

  Future<String?> _processSerialBatchBundle(StockEntryItem item) async {
    if (item.localBundle == null) return item.serialAndBatchBundle;

    final type = selectedStockEntryType.value;
    final isOutward = ['Material Issue', 'Material Transfer'].contains(type);
    final warehouse = isOutward ? selectedFromWarehouse.value : selectedToWarehouse.value;
    final bundleData = item.localBundle!;

    // Construct Payload
    final payload = {
      'type_of_transaction': isOutward ? 'Outward' : 'Inward',
      'item_code': item.itemCode,
      'warehouse': warehouse ?? bundleData.warehouse,
      'has_batch_no': 1,
      'voucher_type': 'Stock Entry',
      // 'voucher_no': name, // Optional: link to parent if needed
      'entries': bundleData.entries.map((b) => b.toJson()).toList(),
    };

    // --- LOGIC CHANGE: Update if name exists, else Create ---
    if (bundleData.name != null && bundleData.name!.isNotEmpty) {
      // UPDATE Existing Bundle
      try {
        final response = await _apiProvider.updateDocument('Serial and Batch Bundle', bundleData.name!, payload);
        if (response.statusCode == 200) {
          return response.data['data']['name'];
        } else {
          // Fallback: If update fails (e.g., submitted), try creating new?
          // For now, throw error to warn user.
          throw Exception('Failed to update Bundle ${bundleData.name}: ${response.data}');
        }
      } catch (e) {
        print('Error updating SABB: $e');
        rethrow;
      }
    } else {
      // CREATE New Bundle
      final response = await _apiProvider.createDocument('Serial and Batch Bundle', payload);
      return response.statusCode == 200 ? response.data['data']['name'] : null;
    }
  }

  Map<String, dynamic> _buildSavePayload(List<StockEntryItem> items) {
    return {
      'stock_entry_type': selectedStockEntryType.value,
      'posting_date': stockEntry.value?.postingDate,
      'posting_time': stockEntry.value?.postingTime,
      'from_warehouse': selectedFromWarehouse.value,
      'to_warehouse': selectedToWarehouse.value,
      'custom_reference_no': customReferenceNoController.text,
      'items': items.map((i) => i.toApiJson(mrReferenceItems: mrReferenceItems)).toList(),
    };
  }

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  // --- Private Helpers ---

  Future<void> _fetchExistingStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if(response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        stockEntry.value = entry;
        _populateFieldsFromEntry(entry);
      }
    } catch(e) {
      GlobalSnackbar.error(message: 'Error fetching entry: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _populateFieldsFromEntry(StockEntry entry) {
    selectedStockEntryType.value = entry.stockEntryType ?? 'Material Transfer';
    selectedFromWarehouse.value = entry.fromWarehouse;
    selectedToWarehouse.value = entry.toWarehouse;
    customReferenceNoController.text = entry.customReferenceNo ?? '';
    isDirty.value = false;
    if (entry.stockEntryType == 'Material Issue' && entry.customReferenceNo != null) {
      if (entry.customReferenceNo!.startsWith('KX') || entry.customReferenceNo!.startsWith('MX')) {
        _fetchPosUploadDetails(entry.customReferenceNo!);
      }
    }
  }

  Future<void> _fetchStockEntryTypes() async {
    isFetchingTypes.value = true;
    try {
      final response = await _provider.getStockEntryTypes();
      if (response.statusCode == 200 && response.data['data'] != null) {
        stockEntryTypes.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      stockEntryTypes.assignAll(['Material Issue', 'Material Receipt', 'Material Transfer']);
    } finally {
      isFetchingTypes.value = false;
    }
  }

  Future<String?> _createSerialBatchBundle(StockEntryItem item) async {
    if (item.localBundle == null) return item.serialAndBatchBundle;

    final type = selectedStockEntryType.value;
    final isOutward = ['Material Issue', 'Material Transfer'].contains(type);
    final warehouse = isOutward ? selectedFromWarehouse.value : selectedToWarehouse.value;

    // Construct Payload using the SABB Model
    final bundleData = item.localBundle!;
    final payload = {
      'type_of_transaction': isOutward ? 'Outward' : 'Inward',
      'item_code': item.itemCode,
      'warehouse': warehouse ?? bundleData.warehouse,
      'has_batch_no': 1,
      'voucher_type': 'Stock Entry',
      // 'voucher_no': name, // Can be linked later
      'entries': bundleData.entries.map((b) => b.toJson()).toList(),
    };

    final response = await _apiProvider.createDocument('Serial and Batch Bundle', payload);
    return response.statusCode == 200 ? response.data['data']['name'] : null;
  }

  Future<void> _createEntry(Map<String, dynamic> data) async {
    final response = await _provider.createStockEntry(data);
    if (response.statusCode == 200) {
      final createdDoc = response.data['data'];
      name = createdDoc['name'];
      mode = 'edit';
      await _fetchExistingStockEntry();
      GlobalSnackbar.success(message: 'Stock Entry created');
    }
  }

  Future<void> _updateEntry(Map<String, dynamic> data) async {
    final response = await _provider.updateStockEntry(name, data);
    if (response.statusCode == 200) {
      GlobalSnackbar.success(message: 'Stock Entry updated');
      await _fetchExistingStockEntry();
    }
  }

  void _markDirty() => isDirty.value = true;
  void _triggerHighlight(String id) {
    recentlyAddedItemName.value = id;
    Future.delayed(const Duration(seconds: 2), () => recentlyAddedItemName.value = '');
  }
  void _autoSaveIfNew() {
    if (mode == 'new') saveStockEntry();
    else isDirty.value = true;
  }
  void toggleInvoiceExpand(String key) => expandedInvoice.value = expandedInvoice.value == key ? '' : key;
}

extension StockEntryItemHelpers on StockEntryItem {
  StockEntryItem copyWith({String? serialAndBatchBundle}) {
    return StockEntryItem(
        name: name, itemCode: itemCode, qty: qty, basicRate: basicRate,
        itemGroup: itemGroup, customVariantOf: customVariantOf,
        batchNo: batchNo, useSerialBatchFields: useSerialBatchFields,
        itemName: itemName, rack: rack, toRack: toRack, sWarehouse: sWarehouse,
        tWarehouse: tWarehouse, customInvoiceSerialNumber: customInvoiceSerialNumber,
        serialAndBatchBundle: serialAndBatchBundle ?? this.serialAndBatchBundle,
        localBundle: localBundle, materialRequest: materialRequest,
        materialRequestItem: materialRequestItem, owner: owner, creation: creation,
        modified: modified, modifiedBy: modifiedBy
    );
  }

  Map<String, dynamic> toApiJson({List<Map<String, dynamic>>? mrReferenceItems}) {
    var json = toJson();
    if (json['name']?.toString().startsWith('local_') == true) json.remove('name');
    if (json['basic_rate'] == 0.0) json.remove('basic_rate');

    // Cleanup internal keys
    json.remove('localBundle');

    if (json['material_request'] == null && mrReferenceItems != null) {
      final ref = mrReferenceItems.firstWhereOrNull((r) =>
      r['item_code'].toString().trim().toLowerCase() == itemCode.trim().toLowerCase());
      if (ref != null) {
        json['material_request'] = ref['material_request'];
        json['material_request_item'] = ref['material_request_item'];
      }
    }
    json.removeWhere((key, value) => value == null);
    return json;
  }
}