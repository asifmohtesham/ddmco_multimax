import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/utils/report_error.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_fields.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_logic.dart';

typedef StickyVariantHeading = ({VariantGroup group, double offset});

class ItemVariantDetailsController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  ItemVariantDetailsController({ReportFieldsController? fields})
    : fields =
          fields ?? ScopedReportFieldsController.forReport(itemVariantFields());

  final ReportFieldsController fields;
  Worker? _fieldsOwner;

  static const filterLabels = {
    'item': 'Items',
    'item_group': 'Item Groups',
    'warehouse': 'Warehouses',
  };
  final filterControllers = {
    for (final key in filterLabels.keys) key: TextEditingController(),
  };
  final stickyHeading = ValueNotifier<StickyVariantHeading?>(null);
  final searchController = TextEditingController();
  final query = ''.obs;
  final inStock = false.obs;
  final results = Rxn<VariantResults>();
  final viewRevision = 0.obs;
  final searchRevision = 0.obs;
  final nameProgress = Rxn<({int done, int total})>();
  final nameSearchIncomplete = false.obs;
  final _itemNames = <String, String>{};
  final _checkedNames = <String>{};
  CancelToken? _nameRequest;
  Timer? _searchTimer;
  Timer? _detailTimer;
  final _requestedDetails = <String>{};
  final _detailRetryAfter = <String, DateTime>{};
  final _nearbyDetails = <String>{};
  final _matchedDetails = <String>{};
  Set<String> _visibleSearchCodes = {};
  final _detailUpdates = <String, Rxn<VariantRow>>{};
  bool _fetchingDetails = false;

  Rxn<VariantRow> detailsFor(String code) =>
      _detailUpdates.putIfAbsent(code, () => Rxn(itemDetails[code]));

  int get warehouseCount => _values('warehouse').length;

  void search(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      final next = value.trim();
      if (next == query.value) return;
      _matchedDetails.clear();
      final data = results.value;
      final expansion = _preSearchExpansion;
      if (next.isEmpty && expansion != null) {
        data?.restoreExpansion(expansion);
        _preSearchExpansion = null;
      } else if (next.isNotEmpty) {
        _preSearchExpansion ??= data?.expansion;
        data?.setAllExpanded(true);
      }
      if (scrollController.hasClients) scrollController.jumpTo(0);
      query.value = next;
      if (next.isNotEmpty) unawaited(loadSearchNames());
    });
  }

  Future<void> retrySearchNames() async {
    if (_nameRequest != null) return;
    _checkedNames.removeWhere((code) => !_itemNames.containsKey(code));
    await loadSearchNames();
  }

  Future<void> loadSearchNames() async {
    final data = results.value;
    if (data == null || query.value.isEmpty || _nameRequest != null) return;
    final codes = {
      for (final row in data.variants)
        if (variantCode(row).isNotEmpty &&
            (row['item_name']?.toString().trim().isEmpty ?? true))
          variantCode(row),
    };
    final pending = codes
        .where(
          (code) =>
              !_checkedNames.contains(code) &&
              (itemDetails[code]?['item_name']?.toString().trim().isEmpty ??
                  true),
        )
        .toList();
    final total = codes.length;
    if (pending.isEmpty) return;

    final generation = _reportGeneration;
    final request = CancelToken();
    _nameRequest = request;
    var done = total - pending.length;
    nameProgress.value = (done: done, total: total);
    const batchSize = 800;
    try {
      for (var start = 0; start < pending.length; start += batchSize) {
        final batch = pending.skip(start).take(batchSize).toList();
        final names = await _api.getItemNames(batch, cancelToken: request);
        if (!_isCurrent(generation)) return;
        _itemNames.addAll(names);
        _checkedNames.addAll(batch);
        done += batch.length;
        nameProgress.value = (done: done, total: total);
        searchRevision.value++;
      }
      nameSearchIncomplete.value = codes.any(
        (code) =>
            !_itemNames.containsKey(code) &&
            (itemDetails[code]?['item_name']?.toString().trim().isEmpty ??
                true),
      );
    } catch (_) {
      if (_isCurrent(generation)) nameSearchIncomplete.value = true;
    } finally {
      if (_isCurrent(generation)) {
        _nameRequest = null;
        nameProgress.value = null;
      }
    }
  }

  void setInStock(bool value) {
    if (scrollController.hasClients) scrollController.jumpTo(0);
    inStock.value = value;
  }

  (VariantResults?, String, bool, int)? _visibleKey;
  List<({VariantGroup group, List<VariantRow> variants})> _visible = [];
  ({bool collapsed, Set<VariantGroup> overrides})? _preSearchExpansion;

  List<({VariantGroup group, List<VariantRow> variants})> visibleGroups(
    VariantResults? data,
    String term,
    bool stockOnly,
  ) {
    final namesRevision = term.isEmpty ? 0 : searchRevision.value;
    final key = (data, term, stockOnly, namesRevision);
    if (key != _visibleKey) {
      _visibleKey = key;
      _visible =
          data?.filter(
            query: term,
            inStock: stockOnly,
            details: itemDetails,
            names: _itemNames,
          ) ??
          [];
      _visibleSearchCodes = {
        if (term.isNotEmpty)
          for (final match in _visible) ...match.variants.map(variantCode),
      };
    }
    viewRevision.value;
    return _visible;
  }

  void toggleGroup(VariantGroup group) {
    results.value?.toggle(group);
    viewRevision.value++;
  }

  void setAllExpanded(bool expanded) {
    if (scrollController.hasClients) scrollController.jumpTo(0);
    results.value?.setAllExpanded(expanded);
    viewRevision.value++;
  }

  final scrollController = ScrollController();
  final activeFilters = <String, String>{}.obs;

  final isLoading = false.obs;
  final hasRun = false.obs;
  final reportError = RxnString();
  final reportData = <Map<String, dynamic>>[].obs;
  final reportColumns = <Map<String, dynamic>>[].obs;
  final itemDetails = <String, Map<String, dynamic>>{};
  final stockBalances = <String, List<Map<String, dynamic>>>{}.obs;
  final loadingStock = <String, bool>{}.obs;
  final stockErrors = <String, String>{}.obs;
  final stockBalanceLabels = <String, String>{}.obs;
  List<String> _reportWarehouses = const [];
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
    var ownerGeneration = fields.ownerGeneration;
    _fieldsOwner = ever(fields.state, (_) {
      if (ownerGeneration == fields.ownerGeneration) return;
      ownerGeneration = fields.ownerGeneration;
      _clearReport();
      isLoading.value = false;
    });
    unawaited(fields.bind());
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
    _fieldsOwner?.dispose();
    fields.dispose();
    for (final controller in filterControllers.values) {
      controller.dispose();
    }
    _searchTimer?.cancel();
    _detailTimer?.cancel();
    _nameRequest?.cancel();
    stickyHeading.dispose();
    searchController.dispose();
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
    _reportWarehouses = const [];
    _nameRequest?.cancel();
    _nameRequest = null;
    _itemNames.clear();
    _checkedNames.clear();
    nameProgress.value = null;
    nameSearchIncomplete.value = false;
    _searchTimer?.cancel();
    _detailTimer?.cancel();
    _detailTimer = null;
    _requestedDetails.clear();
    _detailRetryAfter.clear();
    _nearbyDetails.clear();
    _matchedDetails.clear();
    _detailUpdates.clear();
    _fetchingDetails = false;
    _preSearchExpansion = null;
    stickyHeading.value = null;
    results.value = null;
    searchController.clear();
    query.value = '';
    inStock.value = false;
    hasRun.value = false;
    reportError.value = null;
    reportData.clear();
    reportColumns.clear();
    fields.replaceDefinition(itemVariantFields());
    itemDetails.clear();
    stockBalances.clear();
    loadingStock.clear();
    stockErrors.clear();
    stockBalanceLabels.clear();
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
    if (scrollController.hasClients) scrollController.jumpTo(0);

    try {
      final items = _values('item');
      final warehouses = _values('warehouse');
      final result = await _api.getItemVariantDetails(
        items: items,
        itemGroups: _values('item_group'),
        warehouses: warehouses,
      );
      if (!_isCurrent(generation)) return;
      _reportWarehouses = warehouses;
      reportColumns.assignAll(result.columns);
      fields.replaceDefinition(
        itemVariantFields(decodeDeskColumns(result.columns)),
      );
      reportData.assignAll(result.rows);
      results.value = VariantResults(
        result.rows,
        result.columns,
        singleRequestedTemplate: items.length == 1 ? items.single : null,
      );
    } on FormatException catch (error) {
      if (_isCurrent(generation)) reportError.value = error.message;
    } catch (error) {
      if (_isCurrent(generation)) {
        reportError.value = readableReportError(
          error,
          reportName: 'Item Variant Details',
        );
      }
    } finally {
      if (_isCurrent(generation)) {
        hasRun.value = true;
        isLoading.value = false;
      }
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
    stockErrors.remove(itemCode);
    try {
      final result = await _api.getStockBalanceDimensionResult(
        itemCode: itemCode,
        warehouses: _reportWarehouses,
      );
      if (_isCurrent(generation)) {
        final labels = {
          for (final column in result.columns)
            if (column.label.trim().isNotEmpty) column.fieldname: column.label,
        };
        final label =
            labels['bal_qty'] ?? labels['balance_qty'] ?? labels['qty'];
        if (label == null) {
          stockBalanceLabels.remove(itemCode);
        } else {
          stockBalanceLabels[itemCode] = label;
        }
        stockBalances[itemCode] = result.rows;
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        stockErrors[itemCode] = readableReportError(
          error,
          reportName: 'Stock Balance',
        );
      }
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

  void queueNearbyDetails(String code) {
    if (!_canRequestDetails(code)) return;
    _nearbyDetails.add(code);
    _scheduleDetails();
  }

  void queueMatchedDetails(Iterable<VariantRow> matches) {
    for (final row in matches) {
      final code = variantCode(row);
      if (_canRequestDetails(code)) {
        _matchedDetails.add(code);
      }
    }
    _scheduleDetails();
  }

  bool _canRequestDetails(String code) {
    if (code.isEmpty || _requestedDetails.contains(code)) return false;
    final retryAfter = _detailRetryAfter[code];
    return retryAfter == null || DateTime.now().isAfter(retryAfter);
  }

  void _scheduleDetails() {
    if (_fetchingDetails ||
        (_nearbyDetails.isEmpty && _matchedDetails.isEmpty)) {
      return;
    }
    _detailTimer ??= Timer(const Duration(milliseconds: 32), () {
      _detailTimer = null;
      unawaited(_fetchDetails(_reportGeneration));
    });
  }

  Future<void> _fetchDetails(int generation) async {
    // New viewport work overtakes search matches waiting in the queue.
    final batch = {
      ..._nearbyDetails.toList().reversed.take(50).toList().reversed,
      ..._matchedDetails.take(50),
    }.take(50).toList();
    _nearbyDetails.removeAll(batch);
    _matchedDetails.removeAll(batch);
    _requestedDetails.addAll(batch);
    _fetchingDetails = true;
    try {
      final details = await _api.getItemDetails(batch);
      if (!_isCurrent(generation)) return;
      itemDetails.addAll(details);
      final retryAfter = DateTime.now().add(const Duration(seconds: 8));
      for (final code in batch) {
        final detail = details[code];
        if (detail == null) {
          _requestedDetails.remove(code);
          _detailRetryAfter[code] = retryAfter;
        } else {
          _detailRetryAfter.remove(code);
          _detailUpdates[code]?.value = detail;
        }
      }
      final term = query.value.toLowerCase();
      if (term.isNotEmpty &&
          details.entries.any((entry) {
            final name = entry.value['item_name']?.toString().toLowerCase();
            return !_visibleSearchCodes.contains(entry.key) &&
                (name?.contains(term) ?? false);
          })) {
        searchRevision.value++;
      }
    } finally {
      if (_isCurrent(generation)) {
        _fetchingDetails = false;
        _scheduleDetails();
      }
    }
  }
}
