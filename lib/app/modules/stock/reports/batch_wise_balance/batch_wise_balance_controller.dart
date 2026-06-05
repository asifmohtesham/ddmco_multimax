import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class BatchWiseBalanceController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── Filter field controllers ──────────────────────────────────────

  final fromDateController  = TextEditingController();
  final toDateController    = TextEditingController();
  final itemCodeController  = TextEditingController();
  final batchNoController   = TextEditingController();
  final warehouseController = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  /// FocusNode exposed so DataWedge (hardware barcode scanner) can route
  /// its output directly to the Batch No field via the batchBrowse type.
  final batchNoFocusNode = FocusNode();

  // ── State ──────────────────────────────────────────────────

  final isLoading  = false.obs;
  final reportData = <Map<String, dynamic>>[].obs;

  /// Reactive map driving active filter chips in the screen.
  final activeFilters = <String, String>{}.obs;

  // ── Filter field descriptors (passed to ReportFilterSheet) ─────────────
  // NOTE: filterFields is now a getter (not const) so batchNoFocusNode
  // (an instance field) can be wired into the descriptor at runtime.
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
      key:        'item_code',
      label:      'Item Code *',
      prefixIcon: Icons.category_outlined,
      required:   true,
    ),
    // batch_no: optional, batchBrowse type for DataWedge + manual entry
    ReportFilterField(
      key:        'batch_no',
      label:      'Batch No',
      type:       ReportFilterType.batchBrowse,
      prefixIcon: Icons.qr_code_2_outlined,
      focusNode:  batchNoFocusNode,
      // required: false (default) — batch filter is now optional
    ),
    // warehouse: doctypeLink picker fetches from Warehouse DocType
    const ReportFilterField(
      key:         'warehouse',
      label:       'Warehouse',
      type:        ReportFilterType.doctypeLink,
      prefixIcon:  Icons.warehouse_outlined,
      linkDoctype: 'Warehouse',
    ),
  ];

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    filterControllers = {
      'from_date' : fromDateController,
      'to_date'   : toDateController,
      'item_code' : itemCodeController,
      'batch_no'  : batchNoController,
      'warehouse' : warehouseController,
    };
    // Pre-fill date range: today as both from and to.
    final today = _formatDate(DateTime.now());
    fromDateController.text = today;
    toDateController.text   = today;
    // Reflect pre-filled dates in active filters immediately.
    _rebuildActiveFilters();
  }

  @override
  void onClose() {
    for (final c in filterControllers.values) {
      c.dispose();
    }
    batchNoFocusNode.dispose();
    super.onClose();
  }

  // ── Public API ──────────────────────────────────────────────

  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilters() {
    itemCodeController.clear();
    batchNoController.clear();
    warehouseController.clear();
    // Keep dates at today on clear.
    final today = _formatDate(DateTime.now());
    fromDateController.text = today;
    toDateController.text   = today;
    _rebuildActiveFilters();
    reportData.clear();
  }

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    if (key == 'from_date' || key == 'to_date') {
      filterControllers[key]!.text = _formatDate(DateTime.now());
    }
    _rebuildActiveFilters();
  }

  /// Runs the Batch-Wise Balance History report with current filter values.
  ///
  /// Only [itemCode] is required. [batchNo] and [warehouse] are optional
  /// and are omitted from the API call when empty.
  Future<void> runReport() async {
    final itemCode = itemCodeController.text.trim();

    if (itemCode.isEmpty) {
      GlobalSnackbar.warning(
        title:   'Filter Required',
        message: 'Please enter an Item Code to run the report.',
      );
      return;
    }

    _rebuildActiveFilters();
    isLoading.value = true;
    reportData.clear();

    try {
      final batchNo   = batchNoController.text.trim();
      final warehouse = warehouseController.text.trim();

      final rows = await _apiProvider.getBatchWiseBalance(
        itemCode:  itemCode,
        batchNo:   batchNo.isEmpty   ? null : batchNo,
        warehouse: warehouse.isEmpty ? null : warehouse,
      );

      reportData.assignAll(rows);
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to fetch batch-wise balance: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  static const _filterLabels = {
    'from_date' : 'From',
    'to_date'   : 'To',
    'item_code' : 'Item',
    'batch_no'  : 'Batch',
    'warehouse' : 'Warehouse',
  };

  void _rebuildActiveFilters() {
    activeFilters.clear();
    filterControllers.forEach((key, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) {
        activeFilters[key] = '${_filterLabels[key] ?? key}: $v';
      }
    });
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
