import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class StockBalanceController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

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

    try {
      final itemCode  = itemCodeController.text.trim();
      final warehouse = warehouseController.text.trim();
      final itemGroup = itemGroupController.text.trim();

      final result = await _api.getStockBalanceReport(
        fromDate:              fromDateController.text.trim(),
        toDate:                toDateController.text.trim(),
        itemCode:              itemCode.isEmpty  ? null : itemCode,
        warehouse:             warehouse.isEmpty ? null : warehouse,
        itemGroup:             itemGroup.isEmpty ? null : itemGroup,
        showDimensionWise:     dimensionWiseController.text == '1',
        showVariantAttributes: variantAttrsController.text  == '1',
      );

      reportColumns.assignAll(result.columns);

      // Client-side Customer Code filter (no server-side equivalent exists).
      final customerCode = customerCodeController.text.trim();
      if (customerCode.isNotEmpty &&
          customerCodeColumnKey(result.columns) == null) {
        GlobalSnackbar.info(
          title:   'Customer Code',
          message: 'Customer Code column not available in this report; '
              'showing all rows.',
        );
        reportData.assignAll(result.rows);
      } else {
        reportData.assignAll(
          filterRowsByCustomerCode(result.rows, result.columns, customerCode),
        );
      }
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to fetch Stock Balance: $e',
      );
    } finally {
      isLoading.value = false;
    }
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

  // ── Customer Code filtering (client-side) ────────────────────────────────
  // The ERPNext Stock Balance report has no server-side customer filter; the
  // "Customer Code" column is a flattened Item.customer_items.ref_code value.
  // We mirror the web grid's column filter by narrowing the returned rows.

  /// Returns the row-map key for the report's Customer Code column, or null
  /// when the report did not return such a column.
  static String? customerCodeColumnKey(List<Map<String, dynamic>> columns) {
    for (final col in columns) {
      final label = (col['label'] ?? '').toString().toLowerCase().trim();
      if (label == 'customer code') return (col['fieldname'] ?? '').toString();
    }
    for (final col in columns) {
      if ((col['fieldname'] ?? '').toString() == 'customer_code') {
        return 'customer_code';
      }
    }
    return null;
  }

  /// Keeps only [rows] whose Customer Code value contains [query]
  /// (case-insensitive). Returns [rows] unchanged when [query] is blank or the
  /// report has no Customer Code column.
  static List<Map<String, dynamic>> filterRowsByCustomerCode(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> columns,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    final key = customerCodeColumnKey(columns);
    if (key == null || key.isEmpty) return rows;
    return rows.where((r) {
      final v = r[key];
      return v != null && v.toString().toLowerCase().trim().contains(q);
    }).toList();
  }
}
