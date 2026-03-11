import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class BatchWiseBalanceController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final isLoading = false.obs;
  final reportData = <Map<String, dynamic>>[].obs;

  // Filters
  final itemCodeController = TextEditingController();
  final batchNoController = TextEditingController();
  final warehouseController = TextEditingController();

  // Date Filters
  final fromDateController = TextEditingController();
  final toDateController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    final now = DateTime.now();
    // Default to past 90 days to ensure data is found
    toDateController.text = DateFormat('yyyy-MM-dd').format(now);
    fromDateController.text = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 90)));
  }

  Future<void> runReport() async {
    // Validation: Item Code and Batch No are usually required for this specific report to be useful
    if (itemCodeController.text.isEmpty && batchNoController.text.isEmpty) {
      GlobalSnackbar.error(message: 'Missing Filters\nPlease provide at least an Item Code or Batch No.',);
      return;
    }

    isLoading.value = true;
    reportData.clear();

    try {
      final response = await _apiProvider.getBatchWiseBalance(
        itemCode: itemCodeController.text,
        batchNo: batchNoController.text,
        fromDate: fromDateController.text,
        toDate: toDateController.text,
        warehouse: warehouseController.text,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['message'] != null && data['message']['result'] != null) {
          final result = data['message']['result'];
          if (result is List) {
            reportData.value = List<Map<String, dynamic>>.from(
                result.where((e) => e is Map && (e['item'] != null || e['batch_no'] != null))
            );
          }
        }

        if (reportData.isEmpty) {
          GlobalSnackbar.info(message: 'No history found in this date range.');
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error\nFailed to fetch batch history: $e',);
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

  void clearFilters() {
    itemCodeController.clear();
    batchNoController.clear();
    warehouseController.clear();
    reportData.clear();
  }
}