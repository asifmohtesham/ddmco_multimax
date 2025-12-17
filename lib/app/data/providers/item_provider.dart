import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class ItemProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Updated to return Map and handle ReportView quirks
  Future<Map<String, dynamic>> getItems({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    String orderBy = '`tabItem`.`modified` desc',
  }) async {
    final fields = [
      '`tabItem`.`name`',
      '`tabItem`.`item_name`',
      '`tabItem`.`item_code`',
      '`tabItem`.`item_group`',
      '`tabItem`.`image`',
      '`tabItem`.`variant_of`',
      '`tabItem`.`country_of_origin`',
      '`tabItem`.`description`',
      '`tabItem`.`stock_uom`',
    ];

    try {
      final response = await _apiProvider.getReportView(
        'Item',
        start: limitStart,
        pageLength: limit,
        filters: filters,
        orderBy: orderBy,
        fields: fields,
      );

      if (response.statusCode == 200) {
        if (response.data is Map<String, dynamic>) {
          // 1. Check for specific Frappe Exception
          if (response.data['exc'] != null) {
            throw Exception("Server Error: ${response.data['exc']}");
          }

          // 2. Check 'message' field
          final message = response.data['message'];

          // --- FIX: Handle Empty List Response (No Results) ---
          if (message is List) {
            return {'data': []};
          }

          // 3. Parse Standard ReportView Data (Keys/Values)
          if (message != null && message is Map) {
            final List<dynamic> keys = message['keys'] ?? [];
            final List<dynamic> values = message['values'] ?? [];

            final List<Map<String, dynamic>> parsedData = values.map((row) {
              final Map<String, dynamic> map = {};
              if (row is List) {
                for (int i = 0; i < keys.length; i++) {
                  if (i < row.length) {
                    // Clean key names (e.g. `tabItem`.`name` -> name)
                    String key = keys[i].toString();
                    if (key.contains('.')) {
                      key = key.split('.').last.replaceAll('`', '');
                    }
                    map[key] = row[i];
                  }
                }
              }
              return map;
            }).toList();

            return {'data': parsedData};
          }

          throw Exception("Unexpected Response Format: ${response.data}");
        } else {
          throw Exception("Non-JSON Response: ${response.data.toString().take(150)}...");
        }
      }
      throw Exception("HTTP Error: ${response.statusCode}");
    } catch (e) {
      rethrow;
    }
  }

  // ... (Rest of methods remain unchanged) ...

  Future<Response> getItemGroups() async {
    return _apiProvider.getDocumentList('Item Group', limit: 0, fields: ['name'], orderBy: 'name asc');
  }

  Future<Response> getTemplateItems() async {
    return _apiProvider.getDocumentList('Item', limit: 0, filters: {'has_variants': 1}, fields: ['name'], orderBy: 'name asc');
  }

  Future<Response> getItemAttributes() async {
    return _apiProvider.getDocumentList('Item Attribute', limit: 0, fields: ['name'], orderBy: 'name asc');
  }

  Future<Response> getItemAttributeDetails(String name) async {
    return _apiProvider.getDocument('Item Attribute', name);
  }

  Future<Response> getItemVariantsByAttribute(String attribute, String value) async {
    return _apiProvider.getDocumentList('Item Variant Attribute', filters: {'attribute': attribute, 'attribute_value': value}, fields: ['parent'], limit: 5000);
  }

  Future<Response> getStockLevels(String itemCode) async {
    return _apiProvider.getReport('Stock Balance', filters: {'item_code': itemCode});
  }

  Future<Response> getWarehouseStock(String warehouse) async {
    final storage = Get.find<StorageService>();
    final company = storage.getCompany();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final filters = {
      "company": company,
      "from_date": today,
      "to_date": today,
      "warehouse": warehouse,
      "valuation_field_type": "Currency",
      "show_variant_attributes": 1,
      "show_dimension_wise_stock": 1,
    };

    return _apiProvider.getReport('Stock Balance', filters: filters);
  }

  Future<Response> getStockLedger(String itemCode, {DateTime? fromDate, DateTime? toDate}) async {
    final Map<String, dynamic> filters = {'item_code': itemCode};
    if (fromDate != null && toDate != null) {
      filters['posting_date'] = ['between', [DateFormat('yyyy-MM-dd').format(fromDate), DateFormat('yyyy-MM-dd').format(toDate)]];
    }
    return _apiProvider.getDocumentList('Stock Ledger Entry', filters: filters, fields: ['posting_date', 'posting_time', 'warehouse', 'actual_qty', 'qty_after_transaction', 'voucher_type', 'voucher_no', 'batch_no'], orderBy: 'posting_date desc, posting_time desc', limit: 50);
  }

  Future<Response> getBatchWiseHistory(String itemCode) async {
    final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 365)));
    final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _apiProvider.getReport('Batch-Wise Balance History', filters: {'item_code': itemCode, 'from_date': fromDate, 'to_date': toDate});
  }
}

extension StringExtension on String {
  String take(int n) {
    if (length <= n) return this;
    return substring(0, n);
  }
}