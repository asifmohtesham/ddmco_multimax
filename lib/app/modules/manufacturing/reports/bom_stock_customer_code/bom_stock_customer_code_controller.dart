import 'package:flutter/widgets.dart' show ScrollController;
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/utils/report_error.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_fields.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// Controller for the "BOM Stock with Customer Code" report.
///
/// Parsing logic is exposed as pure static helpers so it can be unit-tested
/// without the network or GetX. Instance members (reactive state + actions)
/// are added on top of these.
class BomStockCustomerCodeController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter state ────────────────────────────────────────────────────────
  final customer = RxnString();
  final customerCodes = <String>[].obs;
  final warehouses = <String>[].obs;
  final posUpload = RxnString();
  final showExplodedView = false.obs;
  final hideOutOfStock = false.obs;

  // ── Segmented row filter (All | In Stock | Shortage) ────────────────────
  final rowFilter = 'ALL'.obs;
  void setRowFilter(String v) => rowFilter.value = v;

  // ── Customer-code group expand state (collapsed by default) ─────────────
  final expandedCodes = <String>{}.obs;
  void toggleGroup(String code) {
    if (expandedCodes.contains(code)) {
      expandedCodes.remove(code);
    } else {
      expandedCodes.add(code);
    }
  }

  bool isGroupExpanded(String code) => expandedCodes.contains(code);

  // ── Result state ────────────────────────────────────────────────────────
  final reportRows = <Map<String, dynamic>>[].obs;
  final totalRow = Rxn<Map<String, dynamic>>();
  final posMissingCodes = <String>[].obs;
  final discoveredCodes = <String>[].obs;
  final isRunning = false.obs;
  final hasResult = false.obs;
  final errorMessage = RxnString();
  final resultRevision = 0.obs;
  final scrollController = ScrollController();
  final fields = ScopedReportFieldsController.forReport(bomStockFields);
  List<DeskColumn> reportColumns = const [];
  late final Worker _fieldsOwnerWorker;

  /// Result rows after the segmented filter is applied.
  List<Map<String, dynamic>> get filteredRows =>
      applyRowFilter(reportRows, rowFilter.value);

  /// In-stock / required / shortage sums over the currently-filtered rows.
  Map<String, num> get filteredTotals => sumTotals(filteredRows);

  /// Filtered rows grouped by customer code (first-seen order).
  List<BomStockGroup> get groupedRows => groupByCustomerCode(filteredRows);

  // ── Warehouse picker state ──────────────────────────────────────────────
  final warehouseOptions = <String>[].obs;
  final isLoadingWarehouses = false.obs;

  // ── Active-filter chips ─────────────────────────────────────────────────
  final activeFilters = <String, String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    var owner = fields.ownerGeneration;
    _fieldsOwnerWorker = ever(fields.state, (_) {
      if (owner == fields.ownerGeneration) return;
      owner = fields.ownerGeneration;
      reportColumns = const [];
      reportRows.clear();
      totalRow.value = null;
      discoveredCodes.clear();
      errorMessage.value = null;
      hasResult.value = false;
      isRunning.value = false;
      warehouseOptions.clear();
      isLoadingWarehouses.value = false;
      clearFilters();
    });
    fields.bind();
  }

  @override
  void onClose() {
    _fieldsOwnerWorker.dispose();
    fields.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> runReport() async {
    if (isRunning.value) return;
    final owner = fields.ownerGeneration;
    resultRevision.value++;
    isRunning.value = true;
    errorMessage.value = null;
    hasResult.value = false;
    _rebuildActiveFilters();
    try {
      final resp = await _api.runBomStockWithCustomerCode(
        customer: customer.value,
        customerCodes: customerCodes.toList(),
        warehouses: warehouses.toList(),
        posUpload: posUpload.value,
        showExplodedView: showExplodedView.value,
        hideOutOfStock: hideOutOfStock.value,
      );
      if (isClosed || owner != fields.ownerGeneration) return;
      final message = resp.data is Map ? resp.data['message'] : null;
      if (resp.statusCode != 200 || message is! Map) {
        throw StateError('Missing report response');
      }
      final rawColumns = message['columns'];
      reportColumns = decodeDeskColumns(rawColumns);
      fields.replaceDefinition(
        bomStockFields.withColumns(
          rawColumns is List ? reportColumns : null,
          aliases: bomStockFieldsAliases,
        ),
      );
      final parsed = _parseRows(message, reportColumns);
      reportRows.assignAll(parsed.where(_isItemRow));
      totalRow.value = parsed.where((row) => !_isItemRow(row)).firstOrNull;
      discoveredCodes.assignAll(distinctCustomerCodes(reportRows));
      hasResult.value = true;
    } catch (e) {
      if (isClosed || owner != fields.ownerGeneration) return;
      final error = readableReportError(
        e,
        reportName: 'BOM Stock with Customer Code',
      );
      errorMessage.value = error;
      GlobalSnackbar.error(title: 'Report Error', message: error);
    } finally {
      if (!isClosed && owner == fields.ownerGeneration) {
        isRunning.value = false;
      }
    }
  }

  /// Selecting a POS Upload auto-fills [customerCodes] from its items, runs
  /// the report, then flags codes not present in the results as missing.
  Future<void> onPosUploadSelected(String? name) async {
    final value = (name ?? '').trim();
    if (value.isEmpty) {
      posUpload.value = null;
      posMissingCodes.clear();
      customerCodes.clear();
      await runReport();
      return;
    }
    posUpload.value = value;
    final owner = fields.ownerGeneration;
    final uploadCodes = await _api.getPosUploadRefCodes(value);
    if (isClosed ||
        owner != fields.ownerGeneration ||
        posUpload.value != value) {
      return;
    }
    customerCodes.assignAll(uploadCodes);
    await runReport();
    if (isClosed ||
        owner != fields.ownerGeneration ||
        posUpload.value != value ||
        !hasResult.value) {
      return;
    }
    final (_, missing) = splitPosCodes(uploadCodes, reportRows.toList());
    posMissingCodes.assignAll(missing);
  }

  void addCustomerCode(String code) {
    final c = code.trim();
    if (c.isEmpty || customerCodes.contains(c)) return;
    customerCodes.add(c);
  }

  void removeCustomerCode(String code) => customerCodes.remove(code);

  void addWarehouse(String wh) {
    if (wh.isEmpty || warehouses.contains(wh)) return;
    warehouses.add(wh);
  }

  void removeWarehouse(String wh) => warehouses.remove(wh);

  Future<void> loadWarehouseOptions() async {
    if (warehouseOptions.isNotEmpty || isLoadingWarehouses.value) return;
    final owner = fields.ownerGeneration;
    isLoadingWarehouses.value = true;
    try {
      final options = await _api.getWarehouseNames();
      if (!isClosed && owner == fields.ownerGeneration) {
        warehouseOptions.assignAll(options);
      }
    } finally {
      if (!isClosed && owner == fields.ownerGeneration) {
        isLoadingWarehouses.value = false;
      }
    }
  }

  void clearFilters() {
    resultRevision.value++;
    customer.value = null;
    customerCodes.clear();
    warehouses.clear();
    posUpload.value = null;
    showExplodedView.value = false;
    hideOutOfStock.value = false;
    posMissingCodes.clear();
    activeFilters.clear();
    rowFilter.value = 'ALL';
    expandedCodes.clear();
  }

  void clearFilter(String key) {
    resultRevision.value++;
    switch (key) {
      case 'customer':
        customer.value = null;
      case 'customer_code':
        customerCodes.clear();
      case 'warehouse':
        warehouses.clear();
      case 'pos_upload':
        posUpload.value = null;
        posMissingCodes.clear();
      case 'show_exploded_view':
        showExplodedView.value = false;
      case 'hide_out_of_stock':
        hideOutOfStock.value = false;
    }
    activeFilters.remove(key);
  }

  void _rebuildActiveFilters() {
    final m = <String, String>{};
    if ((customer.value ?? '').isNotEmpty) {
      m['customer'] = 'Customer: ${customer.value}';
    }
    if (customerCodes.isNotEmpty) {
      m['customer_code'] = 'Codes: ${customerCodes.length}';
    }
    if (warehouses.isNotEmpty) {
      m['warehouse'] = 'Warehouses: ${warehouses.length}';
    }
    if ((posUpload.value ?? '').isNotEmpty) {
      m['pos_upload'] = 'POS: ${posUpload.value}';
    }
    if (showExplodedView.value) m['show_exploded_view'] = 'Exploded';
    if (hideOutOfStock.value) m['hide_out_of_stock'] = 'Hide OOS';
    activeFilters.assignAll(m);
  }

  // ── Static parsers (pure) ───────────────────────────────────────────────

  /// Data rows from a `query_report.run` `message`, excluding the appended
  /// `add_total_row` total (identified by an empty/absent `item_code`).
  static List<Map<String, dynamic>> parseDataRows(dynamic message) {
    if (message is! Map) return [];
    return _parseRows(
      message,
      decodeDeskColumns(message['columns']),
    ).where(_isItemRow).toList();
  }

  /// The appended total row (first result row with an empty `item_code`), or
  /// null when the report returned no total row.
  static Map<String, dynamic>? extractTotalRow(dynamic message) {
    if (message is! Map) return null;
    return _parseRows(
      message,
      decodeDeskColumns(message['columns']),
    ).where((row) => !_isItemRow(row)).firstOrNull;
  }

  static bool _isItemRow(Map<String, dynamic> row) =>
      (row['item_code'] ?? '').toString().trim().isNotEmpty;

  static List<Map<String, dynamic>> _parseRows(
    Map<dynamic, dynamic> message,
    List<DeskColumn> columns,
  ) {
    final result = message['result'];
    if (result is! List) return const [];
    return [
      for (final rawRow in result)
        if (decodeDeskRow(rawRow, columns) case final row?)
          if (row.isNotEmpty)
            {
              ...row,
              if (!row.containsKey('item_code') && row.containsKey('item'))
                'item_code': row['item'],
              if (!row.containsKey('sl_no') && row.containsKey('#'))
                'sl_no': row['#'],
            },
    ];
  }

  /// True when the row is short of its POS demand (server-computed shortage).
  static bool isShortfall(Map<String, dynamic> row) {
    final s = toNum(row['shortage_qty']);
    return s != null && s > 0;
  }

  /// Distinct, non-empty `customer_code` values in first-seen order.
  static List<String> distinctCustomerCodes(List<Map<String, dynamic>> rows) {
    final out = <String>[];
    for (final r in rows) {
      final c = (r['customer_code'] ?? '').toString().trim();
      if (c.isNotEmpty && !out.contains(c)) out.add(c);
    }
    return out;
  }

  /// Splits [uploadCodes] into codes present in [resultRows] (found) and codes
  /// absent from them (missing) — reproduces the desk's POS missing-codes
  /// banner using only readable result data.
  static (List<String>, List<String>) splitPosCodes(
    List<String> uploadCodes,
    List<Map<String, dynamic>> resultRows,
  ) {
    final present = distinctCustomerCodes(resultRows).toSet();
    final found = <String>[];
    final missing = <String>[];
    for (final raw in uploadCodes) {
      final code = raw.trim();
      if (code.isEmpty) continue;
      if (present.contains(code)) {
        if (!found.contains(code)) found.add(code);
      } else {
        if (!missing.contains(code)) missing.add(code);
      }
    }
    return (found, missing);
  }

  /// Applies the segmented filter. 'instock' → positive stock; 'shortage' →
  /// short rows; anything else → all rows.
  static List<Map<String, dynamic>> applyRowFilter(
    List<Map<String, dynamic>> rows,
    String filter,
  ) {
    switch (filter) {
      case 'instock':
        return rows.where((r) => (toNum(r['in_stock_qty']) ?? 0) > 0).toList();
      case 'shortage':
        return rows.where(isShortfall).toList();
      default:
        return List<Map<String, dynamic>>.from(rows);
    }
  }

  /// Buckets [rows] by `customer_code` in first-seen order.
  static List<BomStockGroup> groupByCustomerCode(
    List<Map<String, dynamic>> rows,
  ) {
    final order = <String>[];
    final byCode = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final code = (r['customer_code'] ?? '').toString().trim();
      if (!byCode.containsKey(code)) {
        byCode[code] = [];
        order.add(code);
      }
      byCode[code]!.add(r);
    }
    return [for (final code in order) BomStockGroup(code, byCode[code]!)];
  }

  /// Sums in_stock_qty / required_qty / shortage_qty across [rows].
  static Map<String, num> sumTotals(List<Map<String, dynamic>> rows) {
    num inStock = 0, required = 0, shortage = 0;
    for (final r in rows) {
      inStock += toNum(r['in_stock_qty']) ?? 0;
      required += toNum(r['required_qty']) ?? 0;
      shortage += toNum(r['shortage_qty']) ?? 0;
    }
    return {'in_stock': inStock, 'required': required, 'shortage': shortage};
  }
}

/// A customer-code bucket of result rows.
class BomStockGroup {
  final String code;
  final List<Map<String, dynamic>> rows;
  const BomStockGroup(this.code, this.rows);

  int get itemCount => rows.length;
  num get totalShortage =>
      rows.fold<num>(0, (a, r) => a + (toNum(r['shortage_qty']) ?? 0));
  bool get anyShort => rows.any(BomStockCustomerCodeController.isShortfall);
  bool get shortageMeasured =>
      rows.every((r) => toNum(r['shortage_qty']) != null);
}
