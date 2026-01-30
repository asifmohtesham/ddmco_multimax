import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/serial_and_batch_bundle_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

mixin SerialBatchBundleMixin on GetxController {
  final ApiProvider _sabbApiProvider = Get.find<ApiProvider>();
  final StorageService _sabbStorageService = Get.find<StorageService>();

  // --- State ---
  var useSerialBatchFields = 0.obs; // 0 = SABB, 1 = Legacy
  var sabbEntries = <SerialAndBatchEntry>[].obs;
  var bundleTotalQty = 0.0.obs;
  var currentBundleId = RxnString();

  // Shared Text Controller for the "Add Batch" input
  final bsBatchController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    // Auto-calculate total
    ever(sabbEntries, (_) {
      double total = 0;
      for (var e in sabbEntries) total += e.qty;
      bundleTotalQty.value = total;
    });
  }

  @override
  void onClose() {
    bsBatchController.dispose();
    super.onClose();
  }

  // --- Lifecycle Methods ---

  /// Call this when opening the Item Sheet to reset state
  void initSabbState({
    required int useFields,
    required String? bundleId,
    required String? legacyBatch,
  }) {
    useSerialBatchFields.value = useFields;
    currentBundleId.value = bundleId;
    sabbEntries.clear();
    bundleTotalQty.value = 0.0;
    bsBatchController.clear();

    if (useFields == 0 && bundleId != null && bundleId.isNotEmpty) {
      _fetchBundleDetails(bundleId);
    } else if (useFields == 1) {
      bsBatchController.text = legacyBatch ?? '';
    }
  }

  // --- Actions ---

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

  // --- API Logic ---

  Future<void> _fetchBundleDetails(String bundleId) async {
    try {
      final response = await _sabbApiProvider.getDocument('Serial and Batch Bundle', bundleId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final bundle = SerialAndBatchBundle.fromJson(response.data['data']);
        sabbEntries.assignAll(bundle.entries);
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

    final bundle = SerialAndBatchBundle(
      name: currentBundleId.value ?? '',
      itemCode: itemCode,
      warehouse: warehouse,
      typeOfTransaction: isOutward ? 'Outward' : 'Inward',
      totalQty: bundleTotalQty.value,
      entries: sabbEntries.toList(),
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
          return response.data['data']['name'];
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