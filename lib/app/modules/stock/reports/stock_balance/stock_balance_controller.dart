import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class StockBalanceController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final StorageService _storageService = Get.find<StorageService>();

  final isLoading = false.obs;
  final reportData = <Map<String, dynamic>>[].obs;

  // Filters
  final itemCodeController = TextEditingController();
  final dateController = TextEditingController();

  // Warehouse Dropdown Logic
  final warehouseList = <String>[].obs;
  final selectedWarehouse = Rxn<String>();
  final isWarehousesLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    loadWarehouses();
  }

  Future<void> loadWarehouses() async {
    isWarehousesLoading.value = true;
    try {
      final list = await _apiProvider.getList('Warehouse');
      warehouseList.assignAll(list);
    } catch (e) {
      print('Error loading warehouses: $e');
    } finally {
      isWarehousesLoading.value = false;
    }
  }

  Future<void> runReport() async {
    final company = _storageService.getCompany();

    if (selectedWarehouse.value == null) {
      GlobalSnackbar.error(message: 'Warehouse is required');
      return;
    }

    isLoading.value = true;
    reportData.clear();

    try {
      final response = await _apiProvider.getStockBalance(
        itemCode: itemCodeController.text,
        warehouse: selectedWarehouse.value,
      ); // Note: Stock Balance API might need adjustment to accept date if supported, usually it's "as of date" or today

      if (response.statusCode == 200) {
        final data = response.data;
        // Robust Parsing
        if (data['message'] != null && data['message']['result'] != null) {
          final result = data['message']['result'];
          if (result is List) {
            reportData.value = List<Map<String, dynamic>>.from(
                result.where((e) => e is Map).where((e) => e is Map && e['item_code'] != null)
            );
          }
        }

        if (reportData.isEmpty) {
          GlobalSnackbar.info(message: 'No data found for company: $company');
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load report: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void clearFilters() {
    itemCodeController.clear();
    selectedWarehouse.value = null;
    reportData.clear();
  }
}