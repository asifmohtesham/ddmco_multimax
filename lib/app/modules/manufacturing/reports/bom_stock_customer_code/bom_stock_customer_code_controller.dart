import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// Controller for the "BOM Stock with Customer Code" report.
///
/// Parsing logic is exposed as pure static helpers so it can be unit-tested
/// without the network or GetX. Instance members (reactive state + actions)
/// are added on top of these.
class BomStockCustomerCodeController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter state ────────────────────────────────────────────────────────
  final customer         = RxnString();
  final customerCodes    = <String>[].obs;
  final warehouses       = <String>[].obs;
  final posUpload        = RxnString();
  final showExplodedView = false.obs;
  final hideOutOfStock   = false.obs;

  // ── Result state ────────────────────────────────────────────────────────
  final reportRows      = <Map<String, dynamic>>[].obs;
  final totalRow        = Rxn<Map<String, dynamic>>();
  final posMissingCodes = <String>[].obs;
  final discoveredCodes = <String>[].obs;
  final isRunning       = false.obs;

  // ── Warehouse picker state ──────────────────────────────────────────────
  final warehouseOptions    = <String>[].obs;
  final isLoadingWarehouses = false.obs;

  // ── Active-filter chips ─────────────────────────────────────────────────
  final activeFilters = <String, String>{}.obs;

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> runReport() async {
    if (isRunning.value) return;
    isRunning.value = true;
    _rebuildActiveFilters();
    try {
      final resp = await _api.runBomStockWithCustomerCode(
        customer:         customer.value,
        customerCodes:    customerCodes.toList(),
        warehouses:       warehouses.toList(),
        posUpload:        posUpload.value,
        showExplodedView: showExplodedView.value,
        hideOutOfStock:   hideOutOfStock.value,
      );
      if (resp.statusCode == 200) {
        final message = resp.data['message'];
        reportRows.assignAll(parseDataRows(message));
        totalRow.value = extractTotalRow(message);
        discoveredCodes.assignAll(distinctCustomerCodes(reportRows));
      }
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to run BOM Stock with Customer Code: $e',
      );
    } finally {
      isRunning.value = false;
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
    final uploadCodes = await _api.getPosUploadRefCodes(value);
    customerCodes.assignAll(uploadCodes);
    await runReport();
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
    isLoadingWarehouses.value = true;
    try {
      warehouseOptions.assignAll(await _api.getWarehouseNames());
    } finally {
      isLoadingWarehouses.value = false;
    }
  }

  void clearFilters() {
    customer.value = null;
    customerCodes.clear();
    warehouses.clear();
    posUpload.value = null;
    showExplodedView.value = false;
    hideOutOfStock.value = false;
    posMissingCodes.clear();
    activeFilters.clear();
  }

  void clearFilter(String key) {
    switch (key) {
      case 'customer':           customer.value = null;
      case 'customer_code':      customerCodes.clear();
      case 'warehouse':          warehouses.clear();
      case 'pos_upload':         posUpload.value = null; posMissingCodes.clear();
      case 'show_exploded_view': showExplodedView.value = false;
      case 'hide_out_of_stock':  hideOutOfStock.value = false;
    }
    activeFilters.remove(key);
  }

  void _rebuildActiveFilters() {
    final m = <String, String>{};
    if ((customer.value ?? '').isNotEmpty) m['customer'] = 'Customer: ${customer.value}';
    if (customerCodes.isNotEmpty) m['customer_code'] = 'Codes: ${customerCodes.length}';
    if (warehouses.isNotEmpty) m['warehouse'] = 'Warehouses: ${warehouses.length}';
    if ((posUpload.value ?? '').isNotEmpty) m['pos_upload'] = 'POS: ${posUpload.value}';
    if (showExplodedView.value) m['show_exploded_view'] = 'Exploded';
    if (hideOutOfStock.value) m['hide_out_of_stock'] = 'Hide OOS';
    activeFilters.assignAll(m);
  }

  // ── Static parsers (pure) ───────────────────────────────────────────────

  /// Data rows from a `query_report.run` `message`, excluding the appended
  /// `add_total_row` total (identified by an empty/absent `item_code`).
  static List<Map<String, dynamic>> parseDataRows(dynamic message) {
    if (message is! Map) return [];
    final result = message['result'];
    if (result is! List) return [];
    return result
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((r) => (r['item_code'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  /// The appended total row (first result row with an empty `item_code`), or
  /// null when the report returned no total row.
  static Map<String, dynamic>? extractTotalRow(dynamic message) {
    if (message is! Map) return null;
    final result = message['result'];
    if (result is! List) return null;
    for (final e in result.whereType<Map>()) {
      final m = Map<String, dynamic>.from(e);
      if ((m['item_code'] ?? '').toString().trim().isEmpty) return m;
    }
    return null;
  }

  /// True when [row] is short of its POS-required quantity, mirroring the
  /// desk's red highlight: `required_qty` truthy and `running_total` below it.
  static bool isShortfall(Map<String, dynamic> row) {
    final req = toNum(row['required_qty']);
    if (req == null || req == 0) return false;
    final rt = toNum(row['running_total'])?.toDouble() ?? 0;
    return rt < req.toDouble();
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
}
