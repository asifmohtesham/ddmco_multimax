import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/models/serial_and_batch_bundle_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

mixin SerialBatchBundleMixin on GetxController {
  final ApiProvider _sabbApiProvider = Get.find<ApiProvider>();
  final StorageService _sabbStorageService = Get.find<StorageService>();
  final BatchProvider _sabbBatchProvider = Get.isRegistered<BatchProvider>()
      ? Get.find<BatchProvider>()
      : Get.put(BatchProvider());

  // --- State ---
  var useSerialBatchFields = 0.obs; // 0 = SABB, 1 = Legacy
  var sabbEntries = <SerialAndBatchEntry>[].obs;
  var bundleTotalQty = 0.0.obs;
  var currentBundleId = RxnString();

  // Context for Validation (Renamed to avoid conflict with Controller variables)
  var sabbContextItemCode = RxnString();
  var sabbContextWarehouse = RxnString();

  // Store balances: { 'BATCH-001': 50.0 }
  var batchBalances = <String, double>{}.obs;

  // Shared Text Controller for the "Add Batch" input
  final bsBatchController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    // Auto-calculate total
    ever(sabbEntries, (_) {
      double total = 0;
      for (var e in sabbEntries) total += e.qty.abs();
      bundleTotalQty.value = total;
    });
  }

  @override
  void onClose() {
    bsBatchController.dispose();
    super.onClose();
  }

  // --- Lifecycle Methods ---

  /// Call this when opening the Item Sheet to reset state.
  /// Returns a Future so the controller can await the fetch before checking Dirty state.
  Future<void> initSabbState({
    required int useFields,
    required String? bundleId,
    required String? legacyBatch,
    required itemCode,
    required warehouse,
  }) async {
    sabbContextItemCode.value = itemCode;
    sabbContextWarehouse.value = warehouse;
    useSerialBatchFields.value = useFields;
    currentBundleId.value = bundleId;
    sabbEntries.clear();
    bundleTotalQty.value = 0.0;
    bsBatchController.clear();

    if (useFields == 0 && bundleId != null && bundleId.isNotEmpty) {
      await _fetchBundleDetails(bundleId);
    } else if (useFields == 1) {
      bsBatchController.text = legacyBatch ?? '';
    }
  }

  // --- Actions ---

  /// Validates batch existence and fetches stock balance before adding
  Future<void> validateAndAddBatch(String batchNo, [double qty = 1.0]) async {
    if (batchNo.isEmpty) return;

    // 1. Guard against missing Context (Fixes "null" item error)
    if (sabbContextItemCode.value == null || sabbContextItemCode.value!.isEmpty) {
      GlobalSnackbar.error(message: 'Initialisation Error: Item Code is missing.');
      print('Error: sabbContextItemCode is null. Ensure initSabbState is called with a valid itemCode.');
      return;
    }

    try {
      // 2. Validate Batch Existence (Check if Batch exists for this Item)
      // We search specifically for this batch to ensure it's valid for the item
      final batchesResponse = await _sabbBatchProvider.getBatches(
        filters: {
          'name': batchNo,
          'item': sabbContextItemCode.value,
          'disabled': 0,
        },
        limit: 1,
      );

      final batchesData = batchesResponse.data['data'] as List;
      if (batchesData.isEmpty) {
        GlobalSnackbar.error(message: 'Invalid Batch "$batchNo" for item ${sabbContextItemCode.value}');
        return;
      }

      // 3. Fetch Balance using the correct API (Fixes "Field not permitted: batch_no" error)
      if (sabbContextWarehouse.value != null && sabbContextWarehouse.value!.isNotEmpty) {
        try {
          // We use the same API call used in the Delivery Note controller
          final balanceResponse = await _sabbApiProvider.getBatchWiseBalance(
              sabbContextItemCode.value!,
              batchNo,
              warehouse: sabbContextWarehouse.value
          );

          if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
            final result = balanceResponse.data['message']['result'];

            // The result is typically a List of Maps (e.g. one per Rack or aggregated)
            if (result is List && result.isNotEmpty) {
              // Sum up balance if multiple rows (e.g. different racks), or take the first
              // Usually 'balance_qty' or 'bal_qty' keys are used
              double totalBal = 0.0;
              for(var row in result) {
                totalBal += (row['balance_qty'] ?? row['bal_qty'] ?? 0.0) as double;
              }
              batchBalances[batchNo] = totalBal;
            } else {
              // If empty list, balance is 0
              batchBalances[batchNo] = 0.0;
            }
          }
        } catch (e) {
          print('Failed to fetch batch balance: $e');
          // Don't block adding the batch just because balance fetch failed,
          // just assume 0 or show warning.
          batchBalances[batchNo] = 0.0;
        }
      }

      // 4. Add Entry to List
      addSabbEntry(batchNo, qty);

    } catch (e) {
      print(e);
      GlobalSnackbar.error(message: 'Error validating batch: $e');
    }
  }

  void addSabbEntry(String batch, double qty) {
    if (batch.isEmpty || qty <= 0) return;

    final index = sabbEntries.indexWhere((e) => e.batchNo == batch);
    if (index != -1) {
      final existing = sabbEntries[index];
      sabbEntries[index] = SerialAndBatchEntry(
          batchNo: existing.batchNo,
          qty: existing.qty + qty,
          serialNo: existing.serialNo
      );
    } else {
      sabbEntries.add(SerialAndBatchEntry(batchNo: batch, qty: qty));
    }
    bsBatchController.clear();
  }

  void updateSabbEntry(int index, double newQty) {
    if (index < 0 || index >= sabbEntries.length) return;
    final validQty = newQty.abs();
    final old = sabbEntries[index];
    sabbEntries[index] = SerialAndBatchEntry(
        batchNo: old.batchNo,
        qty: validQty,
        serialNo: old.serialNo
    );
  }

  void removeSabbEntry(int index) {
    sabbEntries.removeAt(index);
  }

  // --- Autocomplete Logic ---

  Future<List<Batch>> searchBatches(String query) async {
    if (sabbContextItemCode.value == null) return [];

    try {
      final response = await _sabbBatchProvider.getBatches(
        filters: {
          'name': ['like', '%$query%'],
          'item': sabbContextItemCode.value,
          'disabled': 0,
          // Optional: Filter by expiry if needed
        },
        limit: 10,
      );

      if (response.statusCode == 200) {
        return (response.data['data'] as List)
            .map((e) => Batch.fromJson(e))
            .toList();
      }
    } catch (e) {
      print("Batch search error: $e");
    }
    return [];
  }

  // --- API Logic ---

  Future<void> _fetchBundleDetails(String bundleId) async {
    try {
      final response = await _sabbApiProvider.getDocument('Serial and Batch Bundle', bundleId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final bundle = SerialAndBatchBundle.fromJson(response.data['data']);

        // Populate entries
        final cleanEntries = bundle.entries.map((e) => SerialAndBatchEntry(
            batchNo: e.batchNo,
            qty: e.qty.abs(),
            serialNo: e.serialNo
        )).toList();

        sabbEntries.assignAll(cleanEntries);

        // Fetch balances for existing entries to show in UI
        for (var entry in cleanEntries) {
          // Fire and forget balance fetch for UI update
          if (!batchBalances.containsKey(entry.batchNo)) {
            validateAndAddBatch(entry.batchNo, 0); // Hacky reuse to fetch balance, but won't add 0 qty
          }
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to fetch bundle details');
    }
  }

  /// Saves or Updates the Bundle. Returns the Bundle ID (name).
  /// [voucherNo] can be null if the parent document is not yet saved.
  Future<String?> saveOrUpdateSerialBatchBundle({
    required String itemCode,
    required String warehouse,
    required bool isOutward,
    required String voucherType,
    String? voucherNo,
  }) async {
    if (sabbEntries.isEmpty) return null;

    // REPLICATION LOGIC:
    // If transaction is Outward, ERPNext expects negative quantities in storage.
    // If Inward, it expects positive.
    final apiEntries = sabbEntries.map((e) => SerialAndBatchEntry(
        batchNo: e.batchNo,
        qty: isOutward ? -e.qty.abs() : e.qty.abs(),
        serialNo: e.serialNo
    )).toList();

    // Ensure the Bundle Total matches the sign of the entries
    final apiTotal = isOutward ? -bundleTotalQty.value.abs() : bundleTotalQty.value.abs();

    final bundle = SerialAndBatchBundle(
      name: currentBundleId.value ?? '',
      itemCode: itemCode,
      warehouse: warehouse,
      typeOfTransaction: isOutward ? 'Outward' : 'Inward',
      totalQty: apiTotal,
      entries: apiEntries,
      voucherType: voucherType,
      voucherNo: voucherNo,
      company: _sabbStorageService.getCompany(),
    );

    try {
      if (currentBundleId.value != null && currentBundleId.value!.isNotEmpty) {
        // Update existing
        await _sabbApiProvider.updateDocument('Serial and Batch Bundle', currentBundleId.value!, bundle.toJson());
        return currentBundleId.value;
      } else {
        // Create new
        final response = await _sabbApiProvider.createDocument('Serial and Batch Bundle', bundle.toJson());
        if (response.statusCode == 200 && response.data['data'] != null) {
          final newId = response.data['data']['name'];
          currentBundleId.value = newId;
          return newId;
        }
      }
      return null;
    } catch (e) {
      print('SABB Operation Failed: $e');
      rethrow;
    }
  }

  /// Deletes a bundle (e.g., when removing an item row)
  Future<void> deleteSerialBatchBundle(String bundleId) async {
    try {
      await _sabbApiProvider.deleteDocument('Serial and Batch Bundle', bundleId);
    } catch (e) {
      print('Failed to delete bundle: $e');
    }
  }
}