import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
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

  // Loading State for Add Button
  var isAddingBatch = false.obs;

  // Context for Validation (Renamed to avoid conflict with Controller variables)
  var sabbContextItemCode = RxnString();
  var sabbContextWarehouse = RxnString();

  // Store balances: { 'BATCH-001': 50.0 }
  var batchBalances = <String, double>{}.obs;

  // --- Row Edit State Management ---
  final Map<String, TextEditingController> batchQtyControllers = {};
  final Map<String, RxBool> batchEditStatus = {};

  // Shared Text Controller for the "Add Batch" input
  final bsBatchController = TextEditingController();
  final bsQtyController = TextEditingController(text: '1.0');

  // [NEW] Dedicated controller for the input field to prevent showing the Total Sum
  final TextEditingController sabbInputQtyController = TextEditingController();

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
    sabbInputQtyController.dispose();
    bsQtyController.dispose();
    for (var c in batchQtyControllers.values) c.dispose();
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

    // Clear Row Controllers
    for (var c in batchQtyControllers.values) c.dispose();
    batchQtyControllers.clear();
    batchEditStatus.clear();

    // Reset Inputs
    bsBatchController.clear();
    bsQtyController.text = '1.0';
    isAddingBatch.value = false;

    if (useFields == 0 && bundleId != null && bundleId.isNotEmpty) {
      await _fetchBundleDetails(bundleId);
    } else if (useFields == 1) {
      bsBatchController.text = legacyBatch ?? '';
    }
  }

  // --- Actions ---

  /// Validates batch existence and fetches stock balance before adding
  Future<void> validateAndAddBatch(String batchNo, [double? qty = 1.0]) async {
    if (batchNo.isEmpty) return;

    isAddingBatch.value = true; // Start Loading

    if (sabbContextItemCode.value == null || sabbContextItemCode.value!.isEmpty) {
      GlobalSnackbar.error(message: 'Initialisation Error: Item Code is missing.');
      return;
    }

    try {
      // 1. Validate Batch Existence
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

      final batchData = batchesData.first;
      final pkgQty = (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
      sabbInputQtyController.text = pkgQty > 0 ? pkgQty.toString() : '1.0';

      // Determine Quantity
      double finalQty = qty ?? 1.0;
      if (qty == null) {
        final pkgQty = (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
        if (pkgQty > 0) finalQty = pkgQty;
      }

      // 2. Fetch Balance
      if (sabbContextWarehouse.value != null && sabbContextWarehouse.value!.isNotEmpty) {
        try {
          // We use the same API call used in the Delivery Note controller
          final balanceResponse = await _sabbApiProvider.getBatchWiseBalance(
              sabbContextItemCode.value!,
              batchNo,
              warehouse: sabbContextWarehouse.value
          );

          if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
            // Robust parsing: Handle if message is List or Map
            var msg = balanceResponse.data['message'];
            List result = [];

            if (msg is Map && msg.containsKey('result')) {
              result = msg['result'] as List? ?? [];
            } else if (msg is List) {
              result = msg;
            }

            if (result.isNotEmpty) {
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

      // 3. Add Entry using calculated finalQty (Fixes Null check operator error)
      addSabbEntry(batchNo, finalQty);
      addBatchFromInput();

      // Reset Qty to '' after successful add
      // bsQtyController.text = '';

    } catch (e) {
      print(e);
      GlobalSnackbar.error(message: 'Error validating batch: $e');
    } finally {
      isAddingBatch.value = false; // Stop Loading
    }
  }

  // [NEW] 2. Add to Bundle & Clear Inputs
  void addBatchFromInput() {
    final batch = bsBatchController.text;
    final qty = double.tryParse(sabbInputQtyController.text) ?? 0.0;

    if (batch.isEmpty || qty <= 0) {
      GlobalSnackbar.error(message: "Invalid Batch or Qty");
      return;
    }

    addSabbEntry(batch, qty);

    // [REQUIREMENT 3] Clear Qty field after adding
    sabbInputQtyController.clear();
    bsBatchController.clear();
  }

  // Helper to setup controller for a batch row
  void initialiseBatchControl(String batchNo, double initialQty) {
    if (batchQtyControllers.containsKey(batchNo)) return;

    final controller = TextEditingController(text: initialQty.toStringAsFixed(2)); // or appropriate format
    final isDirty = false.obs;

    controller.addListener(() {
      final currentText = controller.text;
      // Snapshot Comparison: Compare current text vs the 'Committed' entry in sabbEntries
      final entry = sabbEntries.firstWhereOrNull((e) => e.batchNo == batchNo);
      if (entry != null) {
        final committedQty = entry.qty.abs();
        final currentQty = double.tryParse(currentText) ?? 0.0;
        // Mark dirty only if value differs significantly
        isDirty.value = (currentQty - committedQty).abs() > 0.001;
      }
    });

    batchQtyControllers[batchNo] = controller;
    batchEditStatus[batchNo] = isDirty;
  }

  // Update addSabbEntry to init controller
  void addSabbEntry(String batch, double qty) {
    if (batch.isEmpty || qty <= 0) return;

    final index = sabbEntries.indexWhere((e) => e.batchNo == batch);
    if (index != -1) {
      // Logic for merging duplicates if necessary, or just skip
      // For now, assuming we just update the existing model and controller
      final existing = sabbEntries[index];
      final newQty = existing.qty + qty;
      sabbEntries[index] = SerialAndBatchEntry(
          batchNo: existing.batchNo, qty: newQty, serialNo: existing.serialNo
      );
      // Update Controller to match new total
      batchQtyControllers[batch]!.text = newQty.toString();
    } else {
      sabbEntries.add(SerialAndBatchEntry(batchNo: batch, qty: qty));
      initialiseBatchControl(batch, qty);
    }
    bsBatchController.clear();
  }

  // New Method: Commit changes from TextField to Model
  void commitBatchQty(String batchNo) {
    final controller = batchQtyControllers[batchNo];
    if (controller == null) return;

    final newQty = double.tryParse(controller.text) ?? 0.0;
    if (newQty <= 0) return; // Or handle delete?

    final index = sabbEntries.indexWhere((e) => e.batchNo == batchNo);
    if (index != -1) {
      final old = sabbEntries[index];

      // Update Model (The "Server Snapshot")
      sabbEntries[index] = SerialAndBatchEntry(
          batchNo: old.batchNo,
          qty: newQty,
          serialNo: old.serialNo
      );

      // Reset dirty status (UI hides check button)
      batchEditStatus[batchNo]?.value = false;
    }
  }

  void updateSabbEntry(int index, double newQty) {
    if (index < 0 || index >= sabbEntries.length) return;

    final validQty = newQty.abs();
    final old = sabbEntries[index];

    // Check if the quantity has actually changed (using a small epsilon for double comparison)
    if ((old.qty - validQty).abs() < 0.001) return;

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
    if (sabbContextItemCode.value == null || sabbContextItemCode.value!.isEmpty) return [];

    try {
      final response = await _sabbApiProvider.getItemBatchesWithStock(
          sabbContextItemCode.value!,
          warehouse: sabbContextWarehouse.value
      );

      if (response.statusCode == 200 && response.data['message'] != null) {
        // Robust Parsing
        var msg = response.data['message'];
        List result = [];
        if (msg is Map && msg.containsKey('result')) {
          result = msg['result'] as List? ?? [];
        } else if (msg is List) {
          result = msg;
        }

        return result
          .whereType<Map<String, dynamic>>()
          .where((row) {
            final String batch = row['batch'] ?? row['batch_no'] ?? '';
            final double balance = (row['balance_qty'] ?? row['bal_qty'] ?? 0.0) as double;
            return balance > 0 && batch.toLowerCase().contains(query.toLowerCase());
          })
          .map((row) {
            final String batchName = row['batch'] ?? row['batch_no'] ?? '';
            return Batch(
              creation: '',
              modified: '',
              item: '${row['item']}',
              name: batchName,
              manufacturingDate: '${row['manufacturing_date'] ?? 'NA'}\nBalance: ${NumberFormat('#,##0').format(row['balance_qty'] ?? 0)}',
            );
          }).toList();
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
          initialiseBatchControl(entry.batchNo, entry.qty);
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