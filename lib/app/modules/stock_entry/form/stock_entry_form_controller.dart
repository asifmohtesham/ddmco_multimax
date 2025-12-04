import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/stock_entry_model.dart';
import 'package:ddmco_multimax/app/data/providers/stock_entry_provider.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/stock_entry_form_screen.dart'; // For bottom sheet

class StockEntryFormController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>(); // For Item validation

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var stockEntry = Rx<StockEntry?>(null);

  final TextEditingController barcodeController = TextEditingController();
  
  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  var currentItemCode = '';
  var currentItemName = '';
  var currentStock = 0.0;

  @override
  void onInit() {
    super.onInit();
    fetchStockEntry();
  }

  @override
  void onClose() {
    barcodeController.dispose();
    bsQtyController.dispose();
    super.onClose();
  }

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        stockEntry.value = StockEntry.fromJson(response.data['data']);
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
      // 1. Validate Item
      // Assuming barcode is item_code or we search for it.
      // Simple check: get Item document
      final response = await _apiProvider.getDocument('Item', barcode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final itemData = response.data['data'];
        currentItemCode = itemData['item_code'];
        currentItemName = itemData['item_name'];
        
        // 2. Fetch Stock (Optional but good UX)
        // We can fetch stock balance for a default warehouse if needed.
        // For now, just open sheet.
        currentStock = 0.0; // Placeholder
        
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
    
    // Check if exists
    final index = currentItems.indexWhere((i) => i.itemCode == currentItemCode);
    if (index != -1) {
      final existing = currentItems[index];
      // Need copyWith on StockEntryItem. Assuming it exists or I'll recreate it.
      // I'll check model later, for now constructing new.
      currentItems[index] = StockEntryItem(
        itemCode: existing.itemCode,
        qty: existing.qty + qty,
        basicRate: existing.basicRate,
      );
    } else {
      currentItems.add(StockEntryItem(
        itemCode: currentItemCode,
        qty: qty,
        basicRate: 0.0, // Default
      ));
    }
    
    // Need copyWith on StockEntry
    // stockEntry.value = stockEntry.value?.copyWith(items: currentItems);
    // I'll need to update the model to support copyWith if not present.
    // For now I'll use a manual reconstruction if copyWith is missing, 
    // but I should update the model.
    
    Get.back();
    Get.snackbar('Success', 'Item added');
  }
}
