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
      final itemCode     = itemCodeController.text.trim();
      final warehouse    = warehouseController.text.trim();
      final itemGroup    = itemGroupController.text.trim();
      final customerCode = customerCodeController.text.trim();

      // Resolve Customer Code → parent item codes (server-side; the report has
      // no customer filter). Intersect with any typed Item filter.
      List<String>? customerItemCodes;
      if (customerCode.isNotEmpty) {
        customerItemCodes = await _api.resolveItemsByCustomerCode(customerCode);
      }
      final itemCodes = resolveItemCodeFilter(itemCode, customerItemCodes);

      // An active Customer Code (or Item) filter that matches no items must
      // yield an empty report rather than the unfiltered result set.
      if (itemCodes != null && itemCodes.isEmpty) {
        GlobalSnackbar.info(
          title:   'Customer Code',
          message: 'No items found for the selected filters.',
        );
        return;
      }

      final result = await _api.getStockBalanceReport(
        fromDate:              fromDateController.text.trim(),
        toDate:                toDateController.text.trim(),
        itemCodes:             itemCodes,
        warehouse:             warehouse.isEmpty ? null : warehouse,
        itemGroup:             itemGroup.isEmpty ? null : itemGroup,
        showDimensionWise:     dimensionWiseController.text == '1',
        showVariantAttributes: variantAttrsController.text  == '1',
      );

      reportColumns.assignAll(result.columns);
      reportData.assignAll(result.rows);
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
}
