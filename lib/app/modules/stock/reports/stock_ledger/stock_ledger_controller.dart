import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class StockLedgerController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final StorageService _storageService = Get.find<StorageService>();

  final isLoading = false.obs;
  final reportData = <Map<String, dynamic>>[].obs;

  final fromDateController = TextEditingController();
  final toDateController = TextEditingController();
  final itemCodeController = TextEditingController();
  final warehouseController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    final now = DateTime.now();
    toDateController.text = DateFormat('yyyy-MM-dd').format(now);
    fromDateController.text = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
  }

  Future<void> runReport() async {
    isLoading.value = true;
    try {
      final response = await _apiProvider.getStockLedger(
        company: _storageService.getCompany(),
        fromDate: fromDateController.text,
        toDate: toDateController.text,
        itemCode: itemCodeController.text,
        warehouse: warehouseController.text,
        segregateSerialBatchBundle: 'true',
      );

      if (response.statusCode == 200) {
        final result = response.data['message']['result'];
        if (result != null) {
          // Filter out header rows if they exist mixed with data, typically result is List<Map>
          reportData.value = List<Map<String, dynamic>>.from(result.where((e) => e is Map).where((e) => e['item_code'] != null));
        } else {
          reportData.clear();
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load ledger: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }
}