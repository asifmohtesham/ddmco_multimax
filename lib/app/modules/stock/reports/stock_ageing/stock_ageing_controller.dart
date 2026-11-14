import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_cache.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_logic.dart';

/// Stock → Reports → Stock Ageing.
///
/// Behaves as the Desk does for the "Stock Ageing - Custom" report: the
/// report's saved filters apply until the user changes one; from then on the
/// user's filters are sent. Only the default run is cached on the device.
class StockAgeingController extends GetxController {
  StockAgeingController({StockAgeingCache? cache})
      : _cache = cache ?? StockAgeingCache();

  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final StockAgeingCache _cache;

  // ── Filter controllers (keys match the report's filter fieldnames) ───────

  static const _filterKeys = [
    'to_date',
    'warehouse_type',
    'warehouse',
    'item_code',
    'brand',
    'range',
    'show_warehouse_wise_stock',
  ];

  static const _filterLabels = {
    'to_date': 'As on',
    'warehouse_type': 'Warehouse Type',
    'warehouse': 'Warehouse',
    'item_code': 'Item',
    'brand': 'Brand',
    'range': 'Ranges',
    'show_warehouse_wise_stock': 'Warehouse-wise',
  };

  final Map<String, TextEditingController> filterControllers = {
    for (final k in _filterKeys) k: TextEditingController(),
  };

  List<ReportFilterField> get filterFields => const [
        ReportFilterField(
          key: 'to_date',
          label: 'As On Date *',
          type: ReportFilterType.datePicker,
          prefixIcon: Icons.calendar_today_outlined,
          required: true,
        ),
        ReportFilterField(
          key: 'warehouse_type',
          label: 'Warehouse Type',
          type: ReportFilterType.doctypeLink,
          prefixIcon: Icons.category_outlined,
          linkDoctype: 'Warehouse Type',
        ),
        ReportFilterField(
          key: 'warehouse',
          label: 'Warehouse',
          type: ReportFilterType.doctypeLink,
          prefixIcon: Icons.warehouse_outlined,
          linkDoctype: 'Warehouse',
        ),
        ReportFilterField(
          key: 'item_code',
          label: 'Item',
          type: ReportFilterType.doctypeLink,
          prefixIcon: Icons.inventory_2_outlined,
          linkDoctype: 'Item',
        ),
        ReportFilterField(
          key: 'brand',
          label: 'Brand',
          type: ReportFilterType.doctypeLink,
          prefixIcon: Icons.sell_outlined,
          linkDoctype: 'Brand',
        ),
        ReportFilterField(
          key: 'range',
          label: 'Ageing Range *',
          prefixIcon: Icons.straighten_outlined,
          hint: '30, 60, 90',
          required: true,
        ),
      ];

  List<ReportFilterToggle> get filterToggles => const [
        ReportFilterToggle(
          key: 'show_warehouse_wise_stock',
          label: 'Show Warehouse-wise Stock',
          icon: Icons.warehouse_outlined,
        ),
      ];

  // ── State ────────────────────────────────────────────────────────────────

  /// True while a fetch is in flight (the screen shows a full-page spinner
  /// only when there are no rows to keep on screen).
  final isLoading = false.obs;

  final rows = <Map<String, dynamic>>[].obs;
  final buckets = <AgeBucket>[].obs;
  final searchQuery = ''.obs;
  final sort = 'age'.obs;

  /// Filters that differ from the report's saved defaults, for the chip row.
  final activeFilters = <String, String>{}.obs;

  /// When the rows on screen were fetched.
  final fetchedAt = Rxn<DateTime>();

  /// The `to_date` the rows on screen were calculated for (yyyy-MM-dd).
  final asOn = ''.obs;

  /// Set when a fetch fails and there are no rows to show.
  final errorMessage = RxnString();

  /// The report's saved default filters (`message.custom_filters`); empty
  /// until the first default run or cache read.
  Map<String, dynamic> _defaults = {};

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _restore();
  }

  @override
  void onClose() {
    for (final c in filterControllers.values) {
      c.dispose();
    }
    super.onClose();
  }

  Future<void> _restore() async {
    final snapshot = await _cache.read();
    if (isClosed) return;
    if (snapshot == null) {
      await runReport();
      return;
    }
    _show(snapshot);
    if (StockAgeingLogic.shouldAutoRefresh(
      fetchedAt: snapshot.fetchedAt,
      now: DateTime.now(),
    )) {
      await runReport();
    }
  }

  // ── Derived view ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get visibleRows => StockAgeingLogic.filterAndSort(
        rows,
        search: searchQuery.value,
        sort: sort.value,
        buckets: buckets,
      );

  StockAgeingTotals totalsOf(List<Map<String, dynamic>> shown) =>
      StockAgeingLogic.totals(shown, buckets);

  void setSort(String v) => sort.value = v;
  void onSearchChanged(String v) => searchQuery.value = v;

  // ── Filters ──────────────────────────────────────────────────────────────

  /// The sheet's current values as a server filter map (toggle as 1/absent).
  Map<String, dynamic> _currentFilters() {
    String t(String k) => filterControllers[k]!.text.trim();
    return ApiProvider.buildStockAgeingFilters(
      company: (_defaults['company']?.toString().trim().isNotEmpty ?? false)
          ? _defaults['company'].toString()
          : Get.find<StorageService>().getCompany(),
      toDate: t('to_date'),
      range: t('range'),
      warehouseType: t('warehouse_type'),
      warehouse: t('warehouse'),
      itemCode: t('item_code'),
      brand: t('brand'),
      showWarehouseWiseStock: t('show_warehouse_wise_stock') == '1',
    );
  }

  /// Writes [filters] into the sheet's controllers (missing keys are cleared).
  void _seedControllers(Map<String, dynamic> filters) {
    for (final k in _filterKeys) {
      final v = filters[k];
      final text = k == 'show_warehouse_wise_stock'
          ? (StockAgeingLogic.num_(v) == 1 ? '1' : '')
          : (v?.toString() ?? '');
      filterControllers[k]!.text = text;
    }
  }

  void _rebuildActiveFilters() {
    final current = _currentFilters();
    final next = <String, String>{};
    for (final k in _filterKeys) {
      final now = current[k]?.toString().trim() ?? '';
      final def = _defaults[k]?.toString().trim() ?? '';
      if (now == def || (now.isEmpty && def == '0')) continue;
      final label = _filterLabels[k]!;
      next[k] = k == 'show_warehouse_wise_stock'
          ? '$label: ${now == '1' ? 'on' : 'off'}'
          : '$label: ${now.isEmpty ? '—' : now}';
    }
    activeFilters.assignAll(next);
  }

  /// Restores the report's saved defaults and re-runs.
  void clearFilters() {
    _seedControllers(_defaults);
    runReport();
  }

  /// Restores one filter to its saved default and re-runs.
  void clearFilter(String key) {
    _seedControllers({..._currentFilters(), key: _defaults[key]});
    runReport();
  }

  // ── Fetch ────────────────────────────────────────────────────────────────

  /// Pull-to-refresh: re-runs with whatever filters are set.
  Future<void> refreshReport() => runReport();

  /// Runs the report. While the sheet still holds the saved defaults (or the
  /// defaults are not known yet) the server's saved filters are used, as on
  /// the Desk; otherwise the user's filters are sent.
  Future<void> runReport() async {
    if (isLoading.value) return;

    // With no known defaults (first run, or a report saved without filters)
    // an untouched sheet asks for the server's defaults; once the user has
    // typed the mandatory filters themselves, those are sent instead.
    final current = _currentFilters();
    final useDefaults = _defaults.isEmpty
        ? current['to_date'] == '' && current['range'] == ''
        : StockAgeingLogic.sameFilters(current, _defaults);

    Map<String, dynamic>? filters;
    if (!useDefaults) {
      filters = _currentFilters();
      if (filters['to_date'] == '' || filters['range'] == '') {
        GlobalSnackbar.warning(
          title: 'Filter Required',
          message: 'As On Date and Ageing Range are required.',
        );
        return;
      }
    }

    isLoading.value = true;
    errorMessage.value = null;
    try {
      final response = await _apiProvider.runStockAgeingCustom(filters: filters);
      if (isClosed) return;
      final message = response.data is Map ? response.data['message'] : null;
      if (message is! Map) {
        throw const FormatException('Unexpected response from the server.');
      }

      final columns = message['columns'] is List
          ? List<dynamic>.from(message['columns'] as List)
          : const <dynamic>[];
      final parsed = StockAgeingLogic.parseRows(message['result']);
      final now = DateTime.now();

      if (useDefaults) {
        final custom = message['custom_filters'];
        final snapshot = StockAgeingSnapshot(
          fetchedAt: now,
          columns: columns,
          rows: parsed,
          defaults:
              custom is Map ? Map<String, dynamic>.from(custom) : const {},
        );
        _show(snapshot);
        // A cache failure must not hide a successful fetch.
        try {
          await _cache.write(snapshot);
        } catch (_) {}
      } else {
        buckets.assignAll(StockAgeingLogic.parseBuckets(columns));
        rows.assignAll(parsed);
        fetchedAt.value = now;
        asOn.value = filters!['to_date'].toString();
        _rebuildActiveFilters();
      }
    } catch (e) {
      if (isClosed) return;
      final text = _describe(e);
      // Keep whatever is on screen; only an empty screen shows the error.
      if (rows.isEmpty) errorMessage.value = text;
      GlobalSnackbar.error(title: 'Report Error', message: text);
    } finally {
      isLoading.value = false;
    }
  }

  /// Puts a default-run snapshot on screen and adopts its saved filters.
  void _show(StockAgeingSnapshot snapshot) {
    _defaults = snapshot.defaults;
    _seedControllers(_defaults);
    buckets.assignAll(StockAgeingLogic.parseBuckets(snapshot.columns));
    rows.assignAll(snapshot.rows);
    fetchedAt.value = snapshot.fetchedAt;
    asOn.value = _defaults['to_date']?.toString() ?? '';
    _rebuildActiveFilters();
  }

  String _describe(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['exception'] != null) {
        return data['exception'].toString().split('\n').first;
      }
      return e.message ?? 'Could not reach the server.';
    }
    if (e is FormatException) return e.message;
    return e.toString();
  }
}
