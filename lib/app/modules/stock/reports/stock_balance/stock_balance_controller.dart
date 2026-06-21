import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class StockBalanceController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();
  final StorageService _storage = Get.find<StorageService>();

  // ── Filter controllers ───────────────────────────────────────────────────
  final fromDateController      = TextEditingController();
  final toDateController        = TextEditingController();
  final itemCodeController      = TextEditingController();
  final warehouseController     = TextEditingController();
  final itemGroupController     = TextEditingController();
  final customerCodeController  = TextEditingController();
  final dimensionWiseController = TextEditingController();
  final variantAttrsController  = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  // ── State ────────────────────────────────────────────────────────────────
  final isLoading     = false.obs;
  final reportData    = <Map<String, dynamic>>[].obs;
  final reportColumns = <Map<String, dynamic>>[].obs;
  final activeFilters = <String, String>{}.obs;

  // ── View preferences (persisted) ─────────────────────────────────────────
  // Client-side toggles over the already-loaded rows — they never re-query.
  final hideEmpty  = false.obs; // exclude rows where balance == 0
  final showImages = true.obs;  // show the leading item thumbnail

  // ── Quick filters (client-side, distinct from the report-options sheet) ───
  final quickSearch    = ''.obs;    // matches item_code OR item_name
  final quickWarehouse = 'ALL'.obs; // distinct warehouse value, or 'ALL'
  final quickState     = 'ALL'.obs; // ALL | instock | neg | empty
  final quickSort      = 'bal'.obs; // bal (asc) | val (desc) | move | code

  // ── Filter field descriptors (passed to ReportFilterSheet) ───────────────
  List<ReportFilterField> get filterFields => [
    const ReportFilterField(
      key:        'from_date',
      label:      'From Date',
      type:       ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
    ),
    const ReportFilterField(
      key:        'to_date',
      label:      'To Date',
      type:       ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
    ),
    const ReportFilterField(
      key:         'item_code',
      label:       'Item',
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Item',
      prefixIcon:  Icons.category_outlined,
    ),
    const ReportFilterField(
      key:         'warehouse',
      label:       'Warehouse',
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Warehouse',
      prefixIcon:  Icons.warehouse_outlined,
    ),
    const ReportFilterField(
      key:         'item_group',
      label:       'Item Group',
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Item Group',
      prefixIcon:  Icons.folder_outlined,
    ),
    const ReportFilterField(
      key:        'customer_code',
      label:      'Customer Code',
      type:       ReportFilterType.text,
      prefixIcon: Icons.badge_outlined,
    ),
  ];

  // ── Chip group descriptors (passed to ReportFilterSheet) ─────────────────
  List<ReportFilterChipGroup> get chipGroups => [
    const ReportFilterChipGroup(
      key:   'show_dimension_wise',
      label: 'Display Options',
      options: [
        ReportFilterChipOption(
          value: '1',
          label: 'Dimension-wise',
          icon:  Icons.shelves,
        ),
      ],
    ),
    const ReportFilterChipGroup(
      key:   'show_variant_attrs',
      label: 'Variant Options',
      options: [
        ReportFilterChipOption(
          value: '1',
          label: 'Variant Attributes',
          icon:  Icons.style_outlined,
        ),
      ],
    ),
  ];

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    filterControllers = {
      'from_date'          : fromDateController,
      'to_date'            : toDateController,
      'item_code'          : itemCodeController,
      'warehouse'          : warehouseController,
      'item_group'         : itemGroupController,
      'customer_code'      : customerCodeController,
      'show_dimension_wise': dimensionWiseController,
      'show_variant_attrs' : variantAttrsController,
    };
    final today = _formatDate(DateTime.now());
    fromDateController.text = today;
    toDateController.text   = today;
    // Restore persisted view preferences.
    hideEmpty.value  = _storage.getSbHideEmpty();
    showImages.value = _storage.getSbShowImages();
    _rebuildActiveFilters();
  }

  @override
  void onClose() {
    for (final c in filterControllers.values) {
      c.dispose();
    }
    super.onClose();
  }

  // ── Public API ───────────────────────────────────────────────────────────
  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    if (key == 'from_date' || key == 'to_date') {
      filterControllers[key]!.text = _formatDate(DateTime.now());
    }
    _rebuildActiveFilters();
  }

  void clearFilters() {
    itemCodeController.clear();
    warehouseController.clear();
    itemGroupController.clear();
    customerCodeController.clear();
    dimensionWiseController.clear();
    variantAttrsController.clear();
    final today = _formatDate(DateTime.now());
    fromDateController.text = today;
    toDateController.text   = today;
    _rebuildActiveFilters();
    reportData.clear();
    reportColumns.clear();
  }

  Future<void> runReport() async {
    _rebuildActiveFilters();
    isLoading.value = true;
    reportData.clear();
    reportColumns.clear();
    // A fresh result set may have a different warehouse list, so drop the
    // client-side view filters (the persisted toggles are kept).
    _resetQuickView();

    try {
      final itemCode     = itemCodeController.text.trim();
      final warehouse    = warehouseController.text.trim();
      final itemGroup    = itemGroupController.text.trim();
      final customerCode = customerCodeController.text.trim();

      // Resolve Customer Code → parent item codes (the report has no customer
      // filter). Intersect with any typed Item filter.
      List<String>? customerItemCodes;
      if (customerCode.isNotEmpty) {
        customerItemCodes = await _api.resolveItemsByCustomerCode(customerCode);
      }
      final allowedItems = resolveItemCodeFilter(itemCode, customerItemCodes);

      // No matching items → empty report rather than the unfiltered set.
      if (allowedItems != null && allowedItems.isEmpty) {
        GlobalSnackbar.info(
          title:   'Customer Code',
          message: 'No items found for the selected filters.',
        );
        return;
      }

      // getStockBalanceReport pushes the item restriction server-side when the
      // instance supports it (single item on any version, multi item on
      // v15.72+). On older versions a multi-item restriction can't be sent, so
      // we always narrow rows client-side below — a no-op when the server
      // already filtered (mirrors the web report's grid filter).
      final result = await _api.getStockBalanceReport(
        fromDate:              fromDateController.text.trim(),
        toDate:                toDateController.text.trim(),
        itemCodes:             allowedItems,
        warehouse:             warehouse.isEmpty ? null : warehouse,
        itemGroup:             itemGroup.isEmpty ? null : itemGroup,
        showDimensionWise:     dimensionWiseController.text == '1',
        showVariantAttributes: variantAttrsController.text  == '1',
      );

      reportColumns.assignAll(result.columns);

      final rows = allowedItems == null
          ? result.rows
          : filterRowsByItemCodes(result.rows, allowedItems);

      // Surface the Customer Code (omitted by the report response) on each
      // tile by fetching it for the displayed items and adding a column.
      final viewItemCodes = rows
          .map((r) => (r['item_code'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final ccMap = viewItemCodes.isEmpty
          ? const <String, String>{}
          : await _api.getItemCustomerCodes(viewItemCodes);
      if (ccMap.isNotEmpty &&
          !reportColumns.any((c) => c['fieldname'] == 'customer_code')) {
        reportColumns.add(
          {'fieldname': 'customer_code', 'label': 'Customer Code'},
        );
      }

      // Surface the item image (also omitted by the report) as an absolute URL
      // on each row, mirroring the customer-code enrichment above.
      final imgMap = viewItemCodes.isEmpty
          ? const <String, String>{}
          : await _api.getItemImages(viewItemCodes);

      var enriched = attachCustomerCode(rows, ccMap);
      enriched = attachItemImages(enriched, imgMap, _api.baseUrl);
      reportData.assignAll(enriched);
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to fetch Stock Balance: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  // ── Quick filters (client-side view over the loaded rows) ────────────────

  void setQuickSearch(String v)      => quickSearch.value = v.trim();
  void setQuickWarehouse(String v)   => quickWarehouse.value = v;
  void setQuickSort(String v)        => quickSort.value = v;
  void setQuickState(String v)       => quickState.value = v;

  /// The summary strip's negative chip toggles the Negative segment.
  void toggleNegativeFilter() =>
      quickState.value = quickState.value == 'neg' ? 'ALL' : 'neg';

  void toggleHideEmpty() {
    hideEmpty.toggle();
    _storage.saveSbHideEmpty(hideEmpty.value);
  }

  void toggleShowImages() {
    showImages.toggle();
    _storage.saveSbShowImages(showImages.value);
  }

  /// Resets the client-side view filters (not the persisted toggles, not sort).
  void clearQuickFilters() {
    quickSearch.value    = '';
    quickWarehouse.value = 'ALL';
    quickState.value     = 'ALL';
    if (hideEmpty.value) toggleHideEmpty();
  }

  void _resetQuickView() {
    quickSearch.value    = '';
    quickWarehouse.value = 'ALL';
    quickState.value     = 'ALL';
  }

  /// Distinct warehouses present in the loaded rows (for the warehouse facet).
  List<String> get distinctWarehouses {
    final set = <String>{};
    for (final r in reportData) {
      final w = (r['warehouse'] ?? '').toString().trim();
      if (w.isNotEmpty) set.add(w);
    }
    return set.toList()..sort();
  }

  /// Number of loaded rows whose balance is below zero (full set, not filtered).
  int get negativeCount =>
      reportData.where((r) => _rowNum(r, ['bal_qty', 'balance_qty']) < 0).length;

  /// The rows actually shown: search + warehouse + state + hideEmpty, sorted.
  List<Map<String, dynamic>> get visibleRows => filterAndSortRows(
        reportData,
        search: quickSearch.value,
        warehouse: quickWarehouse.value,
        state: quickState.value,
        hideEmpty: hideEmpty.value,
        sort: quickSort.value,
      );

  // ── Drill-downs (tap-to-navigate bottom sheets) ──────────────────────────

  /// Stock Ledger entries for a tile's item + warehouse over the report period.
  Future<List<Map<String, dynamic>>> fetchStockLedger(
    String itemCode,
    String warehouse,
  ) =>
      _api.getStockLedgerEntries(
        itemCode: itemCode,
        warehouse: warehouse,
        fromDate: fromDateController.text.trim(),
        toDate: toDateController.text.trim(),
      );

  /// Sales-Order reservations behind a tile's reserved figure.
  Future<List<Map<String, dynamic>>> fetchReservations(
    String itemCode,
    String warehouse,
  ) =>
      _api.getStockReservations(itemCode: itemCode, warehouse: warehouse);

  /// Loaded rows mapped to [customerCode] — client-side, no query.
  List<Map<String, dynamic>> itemsForCustomer(String customerCode) =>
      reportData
          .where((r) => (r['customer_code'] ?? '').toString() == customerCode)
          .toList();

  /// Re-runs the report restricted to [customerCode] (drives the customer
  /// sheet's "Filter report to this customer" action through the server filter).
  void applyCustomerFilter(String customerCode) {
    customerCodeController.text = customerCode;
    runReport();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static const _filterLabels = <String, String>{
    'from_date'          : 'From',
    'to_date'            : 'To',
    'item_code'          : 'Item',
    'warehouse'          : 'Warehouse',
    'item_group'         : 'Group',
    'customer_code'      : 'Customer Code',
    'show_dimension_wise': 'Dimension-wise',
    'show_variant_attrs' : 'Variant Attrs',
  };

  void _rebuildActiveFilters() {
    activeFilters.clear();
    filterControllers.forEach((key, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) {
        final label = _filterLabels[key] ?? key;
        activeFilters[key] =
            key.startsWith('show_') ? label : '$label: $v';
      }
    });
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // ── Customer Code → item-code resolution ─────────────────────────────────
  // The ERPNext Stock Balance report has no server-side customer filter and
  // query_report.run does not return the (web-only) Customer Code column, so
  // the filter is resolved server-side: Item.customer_items.ref_code →
  // parent item codes, fed to the report's native item_code filter.

  /// Computes the final list of item codes to restrict the report to.
  ///
  /// - [typedItemCode] — the value of the Item filter ('' when unset).
  /// - [customerItemCodes] — item codes resolved from the Customer Code
  ///   lookup, or null when no Customer Code filter is active.
  ///
  /// Returns null when no item restriction applies, or an empty list when the
  /// combination matches no items (the report should then show nothing).
  static List<String>? resolveItemCodeFilter(
    String typedItemCode,
    List<String>? customerItemCodes,
  ) {
    final typed = typedItemCode.trim();
    if (customerItemCodes == null) {
      return typed.isEmpty ? null : [typed];
    }
    if (typed.isEmpty) return customerItemCodes;
    return customerItemCodes.contains(typed) ? [typed] : <String>[];
  }

  /// Keeps only [rows] whose `item_code` is in [allowedItemCodes].
  ///
  /// The Stock Balance report cannot filter by more than one item server-side
  /// (item_code is a single SQL value), so when a Customer Code resolves to
  /// multiple items the report is run unfiltered and the rows are narrowed
  /// here — mirroring the web report's client-side grid filter.
  static List<Map<String, dynamic>> filterRowsByItemCodes(
    List<Map<String, dynamic>> rows,
    List<String> allowedItemCodes,
  ) {
    final allowed = allowedItemCodes.toSet();
    return rows.where((r) {
      final code = r['item_code'];
      return code != null && allowed.contains(code.toString());
    }).toList();
  }

  /// Returns copies of [rows] with a `customer_code` entry set from [ccMap]
  /// (keyed by item code). Rows whose item is absent from the map are left
  /// without a customer_code. Used to surface the Customer Code — which the
  /// report response omits — on each result tile.
  static List<Map<String, dynamic>> attachCustomerCode(
    List<Map<String, dynamic>> rows,
    Map<String, String> ccMap,
  ) {
    if (ccMap.isEmpty) return rows;
    return rows.map((r) {
      final code = (r['item_code'] ?? '').toString();
      final cc   = ccMap[code];
      if (cc == null || cc.isEmpty) return r;
      return {...r, 'customer_code': cc};
    }).toList();
  }

  /// Returns copies of [rows] with an absolute `item_image` URL set from
  /// [imgMap] (keyed by item code). Relative frappe paths (e.g. "/files/x.jpg")
  /// are prefixed with [baseUrl]; absolute URLs are kept as-is. Rows whose item
  /// has no image are left untouched.
  static List<Map<String, dynamic>> attachItemImages(
    List<Map<String, dynamic>> rows,
    Map<String, String> imgMap,
    String baseUrl,
  ) {
    if (imgMap.isEmpty) return rows;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return rows.map((r) {
      final code = (r['item_code'] ?? '').toString();
      final img  = imgMap[code];
      if (img == null || img.isEmpty) return r;
      final url = img.startsWith('http') ? img : '$base$img';
      return {...r, 'item_image': url};
    }).toList();
  }

  /// Reads the first numeric value among [keys] from [row] (0 when absent).
  static double _rowNum(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final parsed = double.tryParse(v.toString().trim());
      if (parsed != null) return parsed;
    }
    return 0.0;
  }

  /// Applies the client-side quick filters and sort to [rows] and returns a new
  /// list. Pure (no controller state) so it can be unit-tested directly.
  ///
  /// - [search]    — case-insensitive substring of item_code OR item_name.
  /// - [warehouse] — exact warehouse, or 'ALL' for no warehouse restriction.
  /// - [state]     — 'ALL' | 'instock' (bal>0) | 'neg' (bal<0) | 'empty' (bal==0).
  /// - [hideEmpty] — drops rows whose balance is exactly zero.
  /// - [sort]      — 'bal' (asc, surfaces negatives) | 'val' (desc) |
  ///                 'move' (|in|+|out| desc) | 'code' (asc).
  static List<Map<String, dynamic>> filterAndSortRows(
    List<Map<String, dynamic>> rows, {
    String search = '',
    String warehouse = 'ALL',
    String state = 'ALL',
    bool hideEmpty = false,
    String sort = 'bal',
  }) {
    final q = search.trim().toLowerCase();
    final out = rows.where((r) {
      if (warehouse != 'ALL' &&
          (r['warehouse'] ?? '').toString() != warehouse) {
        return false;
      }
      if (q.isNotEmpty) {
        final code = (r['item_code'] ?? '').toString().toLowerCase();
        final name = (r['item_name'] ?? '').toString().toLowerCase();
        if (!code.contains(q) && !name.contains(q)) return false;
      }
      final bal = _rowNum(r, ['bal_qty', 'balance_qty']);
      switch (state) {
        case 'instock':
          if (!(bal > 0)) return false;
          break;
        case 'neg':
          if (!(bal < 0)) return false;
          break;
        case 'empty':
          if (bal != 0) return false;
          break;
      }
      if (hideEmpty && bal == 0) return false;
      return true;
    }).toList();

    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (sort) {
        case 'val':
          return _rowNum(b, ['bal_val', 'balance_value', 'balance_val'])
              .compareTo(_rowNum(a, ['bal_val', 'balance_value', 'balance_val']));
        case 'move':
          final am = _rowNum(a, ['in_qty']).abs() + _rowNum(a, ['out_qty']).abs();
          final bm = _rowNum(b, ['in_qty']).abs() + _rowNum(b, ['out_qty']).abs();
          return bm.compareTo(am);
        case 'code':
          return (a['item_code'] ?? '')
              .toString()
              .compareTo((b['item_code'] ?? '').toString());
        case 'bal':
        default:
          return _rowNum(a, ['bal_qty', 'balance_qty'])
              .compareTo(_rowNum(b, ['bal_qty', 'balance_qty']));
      }
    }

    out.sort(cmp);
    return out;
  }
}
