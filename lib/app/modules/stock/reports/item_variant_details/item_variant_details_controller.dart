import 'dart:async';

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

  // ── Item detail cache ─────────────────────────────────────────────────────
  /// variant_name → {item_name, item_group, image?}
  final itemDetails = <String, Map<String, dynamic>>{}.obs;

  // ── Stock balance cache ────────────────────────────────────────────────────
  /// item_code → [{warehouse, actual_qty}] once fetched; absent = not yet loaded
  final stockBalances = <String, List<Map<String, dynamic>>>{}.obs;
  final loadingStock  = <String, bool>{}.obs;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    filterControllers = {'item_code': itemCodeController};
    itemCodeController.addListener(_rebuildActiveFilters);
  }

  @override
  void onClose() {
    itemCodeController.removeListener(_rebuildActiveFilters);
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
      itemDetails.clear();
      stockBalances.clear();
      loadingStock.clear();
    }
  }

  void clearFilters() {
    for (final c in filterControllers.values) {
      c.clear();
    }
    activeFilters.clear();
    reportData.clear();
    reportColumns.clear();
    itemDetails.clear();
    stockBalances.clear();
    loadingStock.clear();
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

    isLoading.value = true;
    reportData.clear();
    reportColumns.clear();
    itemDetails.clear();
    stockBalances.clear();
    loadingStock.clear();

    try {
      final result = await _api.getItemVariantDetails(itemCode);
      reportColumns.assignAll(result.columns);
      reportData.assignAll(result.rows);
      unawaited(_fetchDetails());
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to fetch Item Variant Details: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Toggle inline stock balance for [itemCode].
  /// First call fetches and expands; second call collapses.
  Future<void> fetchStockBalance(String itemCode) async {
    if (loadingStock[itemCode] == true) return;
    if (stockBalances.containsKey(itemCode)) {
      stockBalances.remove(itemCode);
      return;
    }
    loadingStock[itemCode] = true;
    try {
      final rows = await _api.getStockBalanceWithDimension(itemCode: itemCode);
      stockBalances[itemCode] = rows;
    } catch (_) {
      stockBalances[itemCode] = [];
    } finally {
      loadingStock[itemCode] = false;
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

  Future<void> _fetchDetails() async {
    final codes = reportData
        .map((r) => r['variant_name']?.toString() ?? r['item']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toList();
    if (codes.isEmpty) return;
    final details = await _api.getItemDetails(codes);
    itemDetails.assignAll(details);
  }
}
