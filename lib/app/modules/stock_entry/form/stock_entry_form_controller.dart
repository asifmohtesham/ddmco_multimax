import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/stock_entry_model.dart';
import 'package:ddmco_multimax/app/data/providers/stock_entry_provider.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/stock_entry_form_screen.dart'; // For bottom sheet
import 'package:intl/intl.dart';

class StockEntryFormController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isScanning = false.obs;
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

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  var currentItemCode = '';
  var currentItemName = '';
  var currentStock = 0.0;

  final List<String> stockEntryTypes = [
    'Material Issue',
    'Material Receipt',
    'Material Transfer',
    'Material Transfer for Manufacture'
  ];

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    if (mode == 'new') {
      _initNewStockEntry();
    } else {
      fetchStockEntry();
    }
  }

  @override
  void onClose() {
    barcodeController.dispose();
    bsQtyController.dispose();
    customReferenceNoController.dispose();
    super.onClose();
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
    stockEntry.value = StockEntry(
      name: 'New Stock Entry',
      purpose: 'Material Transfer',
      totalAmount: 0.0,
      postingDate: DateFormat('yyyy-MM-dd').format(now),
      postingTime: DateFormat('HH:mm:ss').format(now),
      modified: '',
      creation: now.toString(),
      status: 'Draft',
      docstatus: 0,
      items: [],
      stockEntryType: 'Material Transfer',
      fromWarehouse: '',
      toWarehouse: '',
      customReferenceNo: '',
    );
    selectedStockEntryType.value = 'Material Transfer';
    isLoading.value = false;
  }

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        stockEntry.value = entry;
        
        // Populate form state
        selectedFromWarehouse.value = entry.fromWarehouse;
        selectedToWarehouse.value = entry.toWarehouse;
        customReferenceNoController.text = entry.customReferenceNo ?? '';
        selectedStockEntryType.value = entry.stockEntryType ?? 'Material Transfer';
      } else {
        Get.snackbar('Error', 'Failed to fetch stock entry');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    isScanning.value = true;
    
    try {
      final response = await _apiProvider.getDocument('Item', barcode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final itemData = response.data['data'];
        currentItemCode = itemData['item_code'];
        currentItemName = itemData['item_name'];
        currentStock = 0.0; 
        
        _openQtySheet();
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

  void _openQtySheet() {
    bsQtyController.clear();
    Get.bottomSheet(
      const StockEntryItemQtySheet(),
      isScrollControlled: true,
    );
  }

  void addItem() {
    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;

    final currentItems = stockEntry.value?.items.toList() ?? [];
    
    final index = currentItems.indexWhere((i) => i.itemCode == currentItemCode);
    if (index != -1) {
      final existing = currentItems[index];
      currentItems[index] = StockEntryItem(
        itemCode: existing.itemCode,
        qty: existing.qty + qty,
        basicRate: existing.basicRate,
        itemGroup: existing.itemGroup,
        customVariantOf: existing.customVariantOf,
        batchNo: existing.batchNo,
        itemName: existing.itemName,
        rack: existing.rack,
        toRack: existing.toRack,
        sWarehouse: existing.sWarehouse,
        tWarehouse: existing.tWarehouse,
      );
    } else {
      currentItems.add(StockEntryItem(
        itemCode: currentItemCode,
        qty: qty,
        basicRate: 0.0,
      ));
    }
    
    final old = stockEntry.value!;
    stockEntry.value = StockEntry(
      name: old.name,
      purpose: old.purpose,
      totalAmount: old.totalAmount,
      postingDate: old.postingDate,
      modified: old.modified,
      creation: old.creation,
      status: old.status,
      docstatus: old.docstatus,
      owner: old.owner,
      stockEntryType: selectedStockEntryType.value,
      postingTime: old.postingTime,
      fromWarehouse: selectedFromWarehouse.value,
      toWarehouse: selectedToWarehouse.value,
      customTotalQty: old.customTotalQty,
      customReferenceNo: customReferenceNoController.text,
      items: currentItems,
    );
    
    Get.back();
    Get.snackbar('Success', 'Item added');
  }
}
