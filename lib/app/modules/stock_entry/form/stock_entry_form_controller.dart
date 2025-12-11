import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class StockEntryFormController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final PosUploadProvider _posProvider = Get.find<PosUploadProvider>();

  // ... (Existing variables: name, mode, isLoading, etc.) ...
  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  final String? argStockEntryType = Get.arguments['stockEntryType'];
  final String? argCustomReferenceNo = Get.arguments['customReferenceNo'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;
  var stockEntry = Rx<StockEntry?>(null);

  var posUpload = Rx<PosUpload?>(null);
  var expandedInvoice = ''.obs;

  var selectedFromWarehouse = RxnString();
  var selectedToWarehouse = RxnString();
  final customReferenceNoController = TextEditingController();

  var stockEntryTypes = <String>[].obs;
  var isFetchingTypes = false.obs;
  var selectedStockEntryType = 'Material Transfer'.obs;

  final TextEditingController barcodeController = TextEditingController();

  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var posUploadSerialOptions = <String>[].obs;

  // POS Selection vars
  var isFetchingPosUploads = false.obs;
  var posUploadsForSelection = <PosUpload>[].obs;
  List<PosUpload> _allFetchedPosUploads = [];

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  final bsBatchController = TextEditingController();
  final bsSourceRackController = TextEditingController();
  final bsTargetRackController = TextEditingController();
  var derivedSourceWarehouse = RxnString();
  var derivedTargetWarehouse = RxnString();
  var isItemSheetOpen = false.obs;
  var bsMaxQty = 0.0.obs;
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

  // --- Dirty Check State for Sheet ---
  String _initialQty = '';
  String _initialBatch = '';
  String _initialSourceRack = '';
  String _initialTargetRack = '';

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

    // Listen to all inputs to trigger validation and dirty check
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

  // ... (Existing methods: onClose, toggleInvoiceExpand, groupedItems, fetches, openCreateDialog, _showPosSelectionBottomSheet...) ...

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

  void _markDirty() {
    if (!isLoading.value && !isDirty.value) {
      isDirty.value = true;
    }
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

  // ... (Omitted fetchWarehouses, _initNewStockEntry, fetchStockEntry, _onReferenceNoChanged, _fetchPosUploadDetails, fetchPendingPosUploads, filterPosUploads, openCreateDialog, _showPosSelectionBottomSheet for brevity as they haven't changed) ...

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

  Future<void> fetchPendingPosUploads() async {
    isFetchingPosUploads.value = true;
    try {
      final kxFuture = _posProvider.getPosUploads(
          limit: 50,
          filters: {
            'status': ['in', ['Pending', 'In Progress']],
            'name': ['like', 'KX%']
          },
          orderBy: 'modified desc'
      );
      final mxFuture = _posProvider.getPosUploads(
          limit: 50,
          filters: {
            'status': ['in', ['Pending', 'In Progress']],
            'name': ['like', 'MX%']
          },
          orderBy: 'modified desc'
      );
      final results = await Future.wait([kxFuture, mxFuture]);
      final List<PosUpload> mergedList = [];
      for (var response in results) {
        if (response.statusCode == 200 && response.data['data'] != null) {
          final List<dynamic> data = response.data['data'];
          mergedList.addAll(data.map((json) => PosUpload.fromJson(json)));
        }
      }
      final uniqueMap = {for (var item in mergedList) item.name: item};
      final sortedList = uniqueMap.values.toList()
        ..sort((a, b) => b.modified.compareTo(a.modified));
      _allFetchedPosUploads = sortedList;
      posUploadsForSelection.value = _allFetchedPosUploads;
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch POS Uploads: $e');
    } finally {
      isFetchingPosUploads.value = false;
    }
  }

  void filterPosUploads(String query) {
    if (query.isEmpty) {
      posUploadsForSelection.value = _allFetchedPosUploads;
    } else {
      final q = query.toLowerCase();
      posUploadsForSelection.value = _allFetchedPosUploads.where((upload) {
        return upload.name.toLowerCase().contains(q) ||
            upload.customer.toLowerCase().contains(q);
      }).toList();
    }
  }

  void openCreateDialog() {
    // ... (Implementation same as previous)
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create Stock Entry', style: Get.textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.outbond, color: Colors.white),
                ),
                title: const Text('Material Issue'),
                subtitle: const Text('From POS Upload (KX/MX only)'),
                onTap: () {
                  Get.back();
                  _showPosSelectionBottomSheet();
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.transform, color: Colors.white),
                ),
                title: const Text('Material Transfer'),
                subtitle: const Text('Internal Transfer'),
                onTap: () {
                  Get.back();
                  Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {
                    'name': '',
                    'mode': 'new',
                    'stockEntryType': 'Material Transfer',
                    'customReferenceNo': ''
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPosSelectionBottomSheet() {
    // ... (Implementation same as previous)
    fetchPendingPosUploads();
    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select POS Upload', style: Theme.of(context).textTheme.titleLarge),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Get.back()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: filterPosUploads,
                    decoration: InputDecoration(
                      labelText: 'Search (KX/MX Only)',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Obx(() {
                      if (isFetchingPosUploads.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (posUploadsForSelection.isEmpty) {
                        return const Center(child: Text('No matching POS Uploads found.'));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: posUploadsForSelection.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final pos = posUploadsForSelection[index];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                            child: InkWell(
                              onTap: () {
                                Get.back();
                                Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {
                                  'name': '',
                                  'mode': 'new',
                                  'stockEntryType': 'Material Issue',
                                  'customReferenceNo': pos.name
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(pos.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.orange.shade200)
                                          ),
                                          child: Text(pos.status, style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(pos.customer, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 8),
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${pos.totalQty?.toStringAsFixed(0) ?? 0} Items',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        Text(pos.date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    );
  }

  // --- Validation & Stock Logic ---

  void validateSheet() {
    rackError.value = null;

    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) {
      isSheetValid.value = false;
      return;
    }

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

    // --- DIRTY CHECK (Added) ---
    if (currentItemNameKey.value != null) {
      // Editing existing item: Only valid if something changed
      bool isChanged = false;
      if (bsQtyController.text != _initialQty) isChanged = true;
      if (bsBatchController.text != _initialBatch) isChanged = true;
      if (bsSourceRackController.text != _initialSourceRack) isChanged = true;
      if (bsTargetRackController.text != _initialTargetRack) isChanged = true;

      if (!isChanged) {
        isSheetValid.value = false;
        return;
      }
    }
    // ---------------------------

    isSheetValid.value = true;
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta);
    final double upperLimit = bsMaxQty.value > 0 ? bsMaxQty.value : 999999.0;

    if (newVal >= 0 && newVal <= upperLimit) {
      bsQtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
      validateSheet();
    }
  }

  // ... (saveStockEntry, _handleSheetRackScan, scanBarcode remain same) ...

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
    bsMaxQty.value = 0.0;

    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    isValidatingBatch.value = false;

    isSourceRackValid.value = false;
    isTargetRackValid.value = false;
    isSheetValid.value = false;
    rackError.value = null;

    selectedSerial.value = null;
    currentItemNameKey.value = null;

    // Reset initial values for new item
    _initialQty = '';
    _initialBatch = '';
    _initialSourceRack = '';
    _initialTargetRack = '';

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

  // ... (Stock calculation & validation helper methods) ...

  Future<void> _updateAvailableStock() async {
    final type = selectedStockEntryType.value;
    final isSourceOp = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
    if (!isSourceOp) {
      bsMaxQty.value = 999999.0;
      return;
    }
    String? warehouse = derivedSourceWarehouse.value ?? selectedFromWarehouse.value;
    String batch = bsBatchController.text.trim();
    String rack = bsSourceRackController.text.trim();

    try {
      final filters = {
        'item_code': currentItemCode,
        'from_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'to_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      };
      final response = await _apiProvider.getReport('Stock Balance', filters: filters);
      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        double totalBalance = 0.0;
        for (var row in result) {
          if (warehouse != null && warehouse.isNotEmpty && row['warehouse'] != warehouse) continue;
          if (batch.isNotEmpty && row['batch_no'] != null && row['batch_no'] != batch) continue;
          if (rack.isNotEmpty && row['rack'] != null && row['rack'] != rack) continue;
          totalBalance += (row['bal_qty'] as num?)?.toDouble() ?? 0.0;
        }
        bsMaxQty.value = totalBalance;
        if (rack.isNotEmpty && totalBalance <= 0) {
          GlobalSnackbar.error(message: 'Insufficient stock in Rack: $rack');
          isSourceRackValid.value = false;
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
        await _updateAvailableStock();
        GlobalSnackbar.success(message: 'Batch validated');
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

    // Format Qty consistent with logic (e.g. remove trailing .0 for display)
    String qtyStr = item.qty.toString();
    if (item.qty % 1 == 0) qtyStr = item.qty.toInt().toString();

    bsQtyController.text = qtyStr;
    bsBatchController.text = item.batchNo ?? '';
    bsSourceRackController.text = item.rack ?? '';
    bsTargetRackController.text = item.toRack ?? '';
    selectedSerial.value = item.customInvoiceSerialNumber;

    // --- Capture Initial State ---
    _initialQty = qtyStr;
    _initialBatch = item.batchNo ?? '';
    _initialSourceRack = item.rack ?? '';
    _initialTargetRack = item.toRack ?? '';
    // -----------------------------

    derivedSourceWarehouse.value = item.sWarehouse;
    derivedTargetWarehouse.value = item.tWarehouse;

    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;

    if (item.rack != null && item.rack!.isNotEmpty) isSourceRackValid.value = true;
    if (item.toRack != null && item.toRack!.isNotEmpty) isTargetRackValid.value = true;

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

  void addItem() async {
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
      await saveStockEntry();
      GlobalSnackbar.success(message: existingIndex != -1 ? 'Item updated' : 'Item added');
    }
  }
}