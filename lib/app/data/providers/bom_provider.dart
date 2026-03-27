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
  }) async {
    return _apiProvider.getDocumentList(
      'BOM',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
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
  /// [bomName] is optional and narrows results to a specific BOM name.
  ///
  /// Response shape (Frappe query_report):
  ///   data.message.columns → List of column definitions
  ///   data.message.result  → List<List<dynamic>> rows
  Future<Response> getBomSearch({
    required String itemCode,
    String? bomName,
  }) async {
    final filters = <String, dynamic>{
      'item': itemCode,
    };
    if (bomName != null && bomName.trim().isNotEmpty) {
      filters['name'] = bomName.trim();
    }
    return _apiProvider.getReport('BOM Search', filters: filters);
  }
}
