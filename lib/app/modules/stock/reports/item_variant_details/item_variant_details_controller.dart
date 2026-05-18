import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class ItemVariantDetailsController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter state ───────────────────────────────────────────────────────────
  final itemCodeController = TextEditingController();
  late final Map<String, TextEditingController> filterControllers;

  // ── Report state ───────────────────────────────────────────────────────────
  final isLoading     = false.obs;
  final reportData    = <Map<String, dynamic>>[].obs;
  final reportColumns = <Map<String, dynamic>>[].obs;
  final activeFilters = <String, String>{}.obs;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    filterControllers = {'item_code': itemCodeController};
  }

  @override
  void onClose() {
    itemCodeController.dispose();
    super.onClose();
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    activeFilters.remove(key);
    if (key == 'item_code') {
      reportData.clear();
      reportColumns.clear();
    }
  }

  void clearFilters() {
    for (final c in filterControllers.values) {
      c.clear();
    }
    activeFilters.clear();
    reportData.clear();
    reportColumns.clear();
  }

  Future<void> runReport() async {
    final itemCode = itemCodeController.text.trim();

    if (itemCode.isEmpty) {
      GlobalSnackbar.warning(
        title:   'Filter Required',
        message: 'Please select an Item to run the report.',
      );
      return;
    }

    _rebuildActiveFilters();
    isLoading.value = true;
    reportData.clear();
    reportColumns.clear();

    try {
      final result = await _api.getItemVariantDetails(itemCode);
      reportColumns.assignAll(result.columns);
      reportData.assignAll(result.rows);
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to fetch Item Variant Details: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static const _labels = {'item_code': 'Item'};

  void _rebuildActiveFilters() {
    activeFilters.clear();
    filterControllers.forEach((key, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) activeFilters[key] = '${_labels[key] ?? key}: $v';
    });
  }
}
