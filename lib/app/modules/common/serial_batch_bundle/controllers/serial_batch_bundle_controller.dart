import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/models/serial_batch_bundle_model.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class SerialBatchBundleArguments {
  final String itemCode;
  final String warehouse;
  final String? existingBundleId;
  final String typeOfTransaction; // 'Inward' or 'Outward'
  final String voucherType;
  final double? requiredQty; // Optional target qty

  SerialBatchBundleArguments({
    required this.itemCode,
    required this.warehouse,
    this.existingBundleId,
    this.typeOfTransaction = 'Outward',
    this.voucherType = 'Stock Entry',
    this.requiredQty,
  });
}

class SerialBatchBundleController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  late SerialBatchBundleArguments args;

  // State
  var isLoading = false.obs;
  var isSubmitting = false.obs;
  var currentEntries = <SerialAndBatchEntry>[].obs;
  var totalQty = 0.0.obs;

  // Validation
  var batchError = RxnString();
  var isValidatingBatch = false.obs;

  // Snapshot for dirty checking
  SerialAndBatchBundle? _originalBundle;

  // Text Controller for manual entry
  final batchInputController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    if (Get.arguments is SerialBatchBundleArguments) {
      args = Get.arguments;
      _loadInitialData();
    } else {
      GlobalSnackbar.error(title: 'Error', message: 'Invalid arguments for Bundle Controller');
      Get.back();
    }
  }

  @override
  void onClose() {
    batchInputController.dispose();
    super.onClose();
  }

  Future<void> _loadInitialData() async {
    if (args.existingBundleId != null && args.existingBundleId!.isNotEmpty) {
      await _fetchBundleDetails(args.existingBundleId!);
    }
  }

  Future<void> _fetchBundleDetails(String bundleId) async {
    isLoading.value = true;
    try {
      final response = await _apiProvider.getDocument('Serial and Batch Bundle', bundleId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        _originalBundle = SerialAndBatchBundle.fromJson(response.data['data']);
        currentEntries.assignAll(_originalBundle!.entries.map((e) =>
            SerialAndBatchEntry.fromJson(e.toJson())).toList()
        );
        _recalcTotal();
      }
    } catch (e) {
      GlobalSnackbar.error(title: 'Error', message: 'Could not load bundle: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // --- Batch Logic ---

  Future<List<Map<String, dynamic>>> searchBatches(String query) async {
    if (args.itemCode.isEmpty) return [];
    try {
      // Logic from StockEntryItemFormController
      final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 365 * 2)));
      final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final response = await _apiProvider.getBatchWiseBalance(
          itemCode: args.itemCode,
          batchNo: null,
          warehouse: args.warehouse,
          fromDate: fromDate,
          toDate: toDate
      );

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        return result.where((e) {
          if (e is! Map) return false;
          final batch = (e['batch_no'] ?? '').toString().toLowerCase();
          final balance = (e['balance_qty'] ?? 0.0);
          final search = query.toLowerCase();
          return balance > 0 && batch.contains(search);
        }).map((e) => {
          'batch': e['batch'],
          'qty': e['balance_qty']
        }).toList();
      }
    } catch (e) {
      print('Batch search error: $e');
    }
    return [];
  }

  Future<void> validateAndAddBatch(String batch) async {
    if (batch.isEmpty) return;
    batchError.value = null;
    isValidatingBatch.value = true;

    try {
      // 1. If Inward, we might not need to check balance (unless strict),
      //    but for Outward we generally do.
      if (args.typeOfTransaction == 'Outward') {
        final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 365 * 2)));
        final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

        final response = await _apiProvider.getBatchWiseBalance(
            itemCode: args.itemCode,
            batchNo: batch,
            warehouse: args.warehouse,
            fromDate: fromDate,
            toDate: toDate
        );

        if (response.statusCode == 200 && response.data['message']?['result'] != null) {
          final List<dynamic> result = response.data['message']['result'];
          final match = result.firstWhereOrNull((e) =>
          e is Map && e['batch'] == batch && (e['balance_qty'] ?? 0) > 0
          );

          if (match != null) {
            _addEntry(batch, 1.0);
            batchInputController.clear();
          } else {
            batchError.value = 'Batch not available in ${args.warehouse}';
          }
        } else {
          batchError.value = 'Invalid Batch';
        }
      } else {
        // Inward - Simply add (or validate existence of batch definition if needed)
        _addEntry(batch, 1.0);
        batchInputController.clear();
      }
    } catch (e) {
      batchError.value = 'Validation Error: $e';
    } finally {
      isValidatingBatch.value = false;
    }
  }

  void _addEntry(String batch, double qty) {
    final existing = currentEntries.firstWhereOrNull((b) => b.batchNo == batch);
    if (existing != null) {
      existing.qty += qty;
      currentEntries.refresh();
    } else {
      currentEntries.add(SerialAndBatchEntry(batchNo: batch, qty: qty));
    }
    _recalcTotal();
  }

  void updateEntryQty(int index, double newQty) {
    if (newQty == 0) {
      removeEntry(index);
      return;
    }
    currentEntries[index].qty = newQty;
    currentEntries.refresh();
    _recalcTotal();
  }

  void removeEntry(int index) {
    currentEntries.removeAt(index);
    _recalcTotal();
  }

  void _recalcTotal() {
    totalQty.value = currentEntries.fold(0.0, (sum, b) => sum + b.qty.abs());
  }

  // --- Submission ---

  Future<void> submit() async {
    if (isSubmitting.value) return;

    // Optional: Validate required quantity
    if (args.requiredQty != null && totalQty.value != args.requiredQty) {
      // Warning? Or strictly block?
      // For flexibility, we might just warn or let backend validation handle it.
    }

    isSubmitting.value = true;
    try {
      final bundleData = {
        'item_code': args.itemCode,
        'warehouse': args.warehouse,
        'type_of_transaction': args.typeOfTransaction,
        'voucher_type': args.voucherType,
        'total_qty': totalQty.value,
        'entries': currentEntries.map((e) => e.toJson()).toList(),
        'docstatus': 0,
      };

      String bundleId;

      if (_originalBundle != null && _originalBundle!.name != null) {
        // Update existing
        bundleId = _originalBundle!.name!;
        await _apiProvider.updateDocument('Serial and Batch Bundle', bundleId, bundleData);
      } else {
        // Create new
        final response = await _apiProvider.createDocument('Serial and Batch Bundle', bundleData);
        if (response.statusCode == 200 && response.data['data'] != null) {
          bundleId = response.data['data']['name'];
        } else {
          throw Exception('Failed to create bundle');
        }
      }

      // Return the Result to the Parent Controller
      Get.back(result: {
        'bundleId': bundleId,
        'totalQty': totalQty.value,
        'entries': currentEntries // Optional, for local UI update
      });

    } catch (e) {
      GlobalSnackbar.error(title: 'Error', message: 'Failed to save bundle: $e');
    } finally {
      isSubmitting.value = false;
    }
  }
}