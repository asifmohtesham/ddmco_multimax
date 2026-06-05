import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class BomProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── List ─────────────────────────────────────────────────────────────────────

  Future<Response> getBOMs({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
  }) async {
    return _apiProvider.getDocumentList(
      'BOM',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orFilters: orFilters,
      fields: [
        'name',
        'item',
        'item_name',
        'quantity',
        'uom',
        'company',
        'is_active',
        'is_default',
        'docstatus',
        'currency',
        'total_cost',
        'modified',
      ],
      orderBy: 'modified desc',
    );
  }

  // ── Single document ───────────────────────────────────────────────────────────

  /// Fetches the full BOM document including child tables
  /// (items, exploded_items). Used by BomFormController.
  Future<Response> getBom(String name) async =>
      _apiProvider.getDocument('BOM', name);

  // ── Update ───────────────────────────────────────────────────────────────────

  /// Partial update — used for inline toggle saves (is_active, is_default).
  /// The caller must include 'modified' for optimistic locking.
  Future<Response> patchBom(
    String name,
    Map<String, dynamic> data,
  ) async =>
      _apiProvider.updateDocument('BOM', name, data);

  // ── BOM Search report ─────────────────────────────────────────────────────────

  /// Runs the ERPNext v15 "BOM Search" query report.
  ///
  /// [itemCode] is required by the report (maps to the `item` filter).
  ///   This is driven by Item Code 1 in the filter sheet.
  ///
  /// [subAssemblyItems] is an optional list of up to 4 additional item codes
  ///   (Item Code 2–5) passed as the report's `sub_assembly_items` filter.
  ///   They are joined as a comma-separated string, matching the ERPNext
  ///   BOM Search report's expected filter format.
  ///
  /// Response shape (Frappe query_report):
  ///   data.message.columns → List of column definitions
  ///   data.message.result  → List<List<dynamic>> rows
  Future<Response> getBomSearch({
    required String itemCode,
    List<String>? subAssemblyItems,
  }) async {
    final filters = <String, dynamic>{
      'item': itemCode,
    };
    if (subAssemblyItems != null && subAssemblyItems.isNotEmpty) {
      filters['sub_assembly_items'] = subAssemblyItems.join(',');
    }
    return _apiProvider.getReport('BOM Search', filters: filters);
  }
}
