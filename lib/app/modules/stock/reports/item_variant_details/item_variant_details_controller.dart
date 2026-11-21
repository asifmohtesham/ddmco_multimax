import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_logic.dart';

class ItemVariantDetailsController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  static const filterLabels = {
    'item': 'Items',
    'item_group': 'Item Groups',
    'warehouse': 'Warehouses',
  };
  final filterControllers = {
    for (final key in filterLabels.keys) key: TextEditingController(),
  };
  final scrollController = ScrollController();
  final activeFilters = <String, String>{}.obs;

  final isLoading = false.obs;
  final hasRun = false.obs;
  final reportError = RxnString();
  final reportData = <Map<String, dynamic>>[].obs;
  final reportColumns = <Map<String, dynamic>>[].obs;
  final itemDetails = <String, Map<String, dynamic>>{}.obs;
  final stockBalances = <String, List<Map<String, dynamic>>>{}.obs;
  final loadingStock = <String, bool>{}.obs;
  int _reportGeneration = 0;

  List<String> _values(String key) =>
      splitMultiValue(filterControllers[key]!.text);

  String? validateFilters() {
    final hasItems = _values('item').isNotEmpty;
    final hasGroups = _values('item_group').isNotEmpty;
    if (hasItems && hasGroups) return 'Select either Items or Item Groups.';
    if (!hasItems && !hasGroups) {
      return 'Select at least one Item or Item Group.';
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    final preset = args is Map
        ? args['item'] ?? args['item_code'] ?? args['itemCode']
        : args;
    if (preset is String) filterControllers['item']!.text = preset;
    if (preset is List) {
      filterControllers['item']!.text = joinMultiValue(
        preset.whereType<String>(),
      );
    }
    for (final controller in filterControllers.values) {
      controller.addListener(_filtersChanged);
    }
    _rebuildActiveFilters();
  }

  @override
  void onClose() {
    for (final controller in filterControllers.values) {
      controller.dispose();
    }
    scrollController.dispose();
    super.onClose();
  }

  void clearFilter(String key) {
    if (isLoading.value) return;
    filterControllers[key]?.clear();
  }

  void clearFilters() {
    if (isLoading.value) return;
    for (final controller in filterControllers.values) {
      controller.clear();
    }
  }

  void _clearReport() {
    _reportGeneration++;
    hasRun.value = false;
    reportError.value = null;
    reportData.clear();
    reportColumns.clear();
    itemDetails.clear();
    stockBalances.clear();
    loadingStock.clear();
  }

  Future<void> runReport() async {
    if (isLoading.value) return;
    final validation = validateFilters();
    if (validation != null) {
      GlobalSnackbar.warning(title: 'Filters', message: validation);
      return;
    }

    isLoading.value = true;
    _clearReport();
    final generation = _reportGeneration;

    try {
      final result = await _api.getItemVariantDetails(
        items: _values('item'),
        itemGroups: _values('item_group'),
        warehouses: _values('warehouse'),
      );
      if (isClosed) return;
      reportColumns.assignAll(result.columns);
      reportData.assignAll(result.rows);
      unawaited(_fetchDetails(generation));
    } on FormatException catch (error) {
      reportError.value = error.message;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      reportError.value = status == null
          ? 'Could not reach the report server.'
          : 'The server could not run the report (HTTP $status).';
    } catch (_) {
      reportError.value = 'Could not load Item Variant Details.';
    } finally {
      hasRun.value = true;
      isLoading.value = false;
    }
  }

  /// Toggle the separate Stock Balance lookup for one variant.
  Future<void> fetchStockBalance(String itemCode) async {
    if (loadingStock[itemCode] == true) return;
    if (stockBalances.containsKey(itemCode)) {
      stockBalances.remove(itemCode);
      return;
    }
    final generation = _reportGeneration;
    loadingStock[itemCode] = true;
    try {
      final rows = await _api.getStockBalanceWithDimension(itemCode: itemCode);
      if (_isCurrent(generation)) stockBalances[itemCode] = rows;
    } catch (_) {
      if (_isCurrent(generation)) stockBalances[itemCode] = [];
    } finally {
      if (_isCurrent(generation)) loadingStock[itemCode] = false;
    }
  }

  void _filtersChanged() {
    _rebuildActiveFilters();
    if (hasRun.value) _clearReport();
  }

  void _rebuildActiveFilters() {
    activeFilters.assignAll({
      for (final entry in filterLabels.entries)
        if (_values(entry.key).isNotEmpty)
          entry.key: '${entry.value}: ${_values(entry.key).length} selected',
    });
  }

  bool _isCurrent(int generation) =>
      !isClosed && generation == _reportGeneration;

  Future<void> _fetchDetails(int generation) async {
    final codes = variantRowsOf(reportData)
        .map(
          (r) => r['variant_name']?.toString() ?? r['item']?.toString() ?? '',
        )
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();
    // Group selections can return thousands of variants. Bound the list sent
    // in each get_list query to keep the request URL manageable.
    const batchSize = 50;
    for (
      var start = 0;
      start < codes.length && _isCurrent(generation);
      start += batchSize
    ) {
      final details = await _api.getItemDetails(
        codes.sublist(start, math.min(start + batchSize, codes.length)),
      );
      if (_isCurrent(generation)) itemDetails.addAll(details);
    }
  }
}
