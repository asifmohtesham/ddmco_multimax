import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get/get.dart' hide Response, FormData;
import 'package:intl/intl.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class ApiProvider {
  static const String defaultBaseUrl = "https://erp.multimax.cloud";

  bool _dioInitialised = false;
  late Dio _dio;
  late CookieJar _cookieJar;
  String _baseUrl = defaultBaseUrl;

  String get baseUrl => _baseUrl;

  ApiProvider() {
    _initDio();
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
    if (_dioInitialised) {
      _dio.options.baseUrl = _baseUrl;
    }
  }

  Future<void> _initDio() async {
    if (_dioInitialised) return;

    // Load URL from SQLite Database
    if (Get.isRegistered<DatabaseService>()) {
      final dbService = Get.find<DatabaseService>();
      final storedUrl = await dbService.getConfig(DatabaseService.serverUrlKey);
      if (storedUrl != null && storedUrl.isNotEmpty) {
        _baseUrl = storedUrl;
      }
    }

    if (Get.isRegistered<StorageService>()) {
      final storedUrl = Get.find<StorageService>().getBaseUrl();
      if (storedUrl != null && storedUrl.isNotEmpty) {
        _baseUrl = storedUrl;
      }
    }

    if (!kIsWeb) {
      final appSupportDir = await getApplicationSupportDirectory();
      final cookiePath = '${appSupportDir.path}/.cookies/';
      _cookieJar = PersistCookieJar(ignoreExpires: true, storage: FileStorage(cookiePath));
    } else {
      _cookieJar = CookieJar();
    }

    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
    
    // Only add CookieManager on native platforms (Android/iOS/Desktop)
    if (!kIsWeb) {
      _dio.interceptors.add(CookieManager(_cookieJar));
    }
    
    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
    _dioInitialised = true;
  }

  // ---------------------------------------------------------------------------
  // GENERIC METHODS
  // ---------------------------------------------------------------------------

  Future<Response> getDocumentList(String doctype, {
    int limit = 20,
    int limitStart = 0,
    List<String>? fields,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
    String orderBy = 'modified desc',
  }) async {
    if (!_dioInitialised) await _initDio();

    final String endpoint = '/api/resource/$doctype';
    final queryParameters = {
      'limit_page_length': limit,
      'limit_start': limitStart,
      'order_by': orderBy,
    };

    if (fields != null) {
      queryParameters['fields'] = json.encode(fields);
    }

    // Process Standard Filters (AND)
    if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        if (entry.value is List && (entry.value as List).length == 2) {
          return [doctype, entry.key, entry.value[0], entry.value[1]];
        }
        return [doctype, entry.key, '=', entry.value];
      }).toList();

      queryParameters['filters'] = json.encode(filterList);
    }

    // Process OR Filters (OR)
    if (orFilters != null && orFilters.isNotEmpty) {
      final List<List<dynamic>> orFilterList = orFilters.entries.map((entry) {
        if (entry.value is List && (entry.value as List).length == 2) {
          return [doctype, entry.key, entry.value[0], entry.value[1]];
        }
        return [doctype, entry.key, '=', entry.value];
      }).toList();

      queryParameters['or_filters'] = json.encode(orFilterList);
    }

    try {
      return await _dio.get(endpoint, queryParameters: queryParameters);
    } on DioException catch (e) {
      rethrow;
    }
  }

  // Support for Frappe Desk Report View (allows advanced joins/filtering)
  Future<Response> getReportView(String doctype, {
    int start = 0,
    int pageLength = 20,
    List<String>? fields,
    List<List<dynamic>>? filters,
    String orderBy = 'modified desc',
  }) async {
    if (!_dioInitialised) await _initDio();

    final data = {
      'doctype': doctype,
      'fields': json.encode(fields ?? ['`tab$doctype`.`name`']),
      'filters': json.encode(filters ?? []),
      'order_by': orderBy,
      'start': start,
      'page_length': pageLength,
      'view': 'List',
      'group_by': '`tab$doctype`.`name`',
      'with_comment_count': 1
    };

    // Using POST as per standard ReportView usage
    return await _dio.post('/api/method/frappe.desk.reportview.get',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType)
    );
  }

  Future<Response> getDocument(String doctype, String name) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/resource/$doctype/$name');
  }

  Future<Response> createDocument(String doctype, Map<String, dynamic> data) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post('/api/resource/$doctype', data: data);
  }

  Future<Response> updateDocument(String doctype, String name, Map<String, dynamic> data) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.put('/api/resource/$doctype/$name', data: data);
  }

  Future<Response> deleteDocument(String doctype, String name) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.delete('/api/resource/$doctype/$name');
  }

  Future<Response> callMethod(String method, {Map<String, dynamic>? params}) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/method/$method', queryParameters: params);
  }

  // ---------------------------------------------------------------------------
  // REPORT & LIST HELPERS
  // ---------------------------------------------------------------------------

  Future<List<String>> getList(String doctype) async {
    try {
      if (!_dioInitialised) await _initDio();
      final response = await _dio.get('/api/resource/$doctype', queryParameters: {
        'fields': json.encode(['name']),
        'limit_page_length': 0,
        'order_by': 'name asc'
      });
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching list for $doctype: $e');
    }
    return [];
  }

  Future<Response> getReport(String reportName, {Map<String, dynamic>? filters}) async {
    if (!_dioInitialised) await _initDio();

    return await _dio.get('/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name': reportName,
          'filters': json.encode(filters ?? {}),
          'ignore_prepared_report': 'true',
          '_': DateTime.now().millisecondsSinceEpoch
        }
    );
  }

  Future<Response> getStockBalance({
    required String itemCode,
    String? warehouse,
    String? batchNo,
    String? rack,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final String company = storage.getCompany();
    final String? targetWarehouse = warehouse;

    if (targetWarehouse == null || targetWarehouse.isEmpty) {
      throw Exception('Warehouse is required to check stock balance.');
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final Map<String, dynamic> filters = {
      "company": company,
      "from_date": today,
      "to_date": today,
      "item_code": itemCode,
      "valuation_field_type": "Currency",
      "rack": rack != null && rack.isNotEmpty ? [rack] : [],
      "show_variant_attributes": 1,
      "show_dimension_wise_stock": 1
    };

    if (batchNo != null && batchNo.isNotEmpty) {
      filters["batch_no"] = batchNo;
    }

    return await _dio.get('/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name': 'Stock Balance',
          'filters': json.encode(filters),
          'ignore_prepared_report': 'true',
          'are_default_filters': 'false',
          '_': DateTime.now().millisecondsSinceEpoch
        }
    );
  }

  /// Fetches Batch-Wise Balance History
  /// Updated to accept date range
  Future<Response> getBatchWiseBalance({
    required String itemCode,
    required String? batchNo,
    required String? fromDate,
    required String? toDate,
    String? warehouse,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final String company = storage.getCompany();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final Map<String, dynamic> filters = {
      "company": company,
      "from_date": fromDate ?? today,
      "to_date": toDate ?? today,
    };

    // ERP typically requires Item Code for this report
    if (itemCode.isNotEmpty) filters["item_code"] = itemCode;
    if (batchNo != null && batchNo.isNotEmpty) filters["batch_no"] = batchNo;
    if (warehouse != null && warehouse.isNotEmpty) filters["warehouse"] = warehouse;

    return await _dio.get('/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name': 'Batch-Wise Balance History',
          'filters': json.encode(filters),
          'ignore_prepared_report': 'true',
          'are_default_filters': 'false',
          '_': DateTime.now().millisecondsSinceEpoch
        }
    );
  }

  // Module specific getters
  Future<Response> getPurchaseReceipts({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters, String orderBy = 'modified desc'}) async =>
      getDocumentList('Purchase Receipt', limit: limit, limitStart: limitStart, filters: filters, orderBy: orderBy, fields: ['name', 'owner', 'creation', 'modified', 'modified_by', 'docstatus', 'status', 'supplier', 'posting_date', 'posting_time', 'set_warehouse', 'currency', 'total_qty', 'grand_total']);
  Future<Response> getPurchaseReceipt(String name) async => getDocument('Purchase Receipt', name);
  Future<Response> getPackingSlips({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Packing Slip', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'delivery_note', 'modified', 'creation', 'docstatus', 'custom_po_no', 'from_case_no', 'to_case_no', 'owner']);
  Future<Response> getPackingSlip(String name) async => getDocument('Packing Slip', name);
  Future<Response> getStockEntries({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Stock Entry', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'purpose', 'total_amount', 'custom_total_qty', 'modified', 'docstatus', 'creation', 'stock_entry_type']);
  Future<Response> getStockEntry(String name) async => getDocument('Stock Entry', name);
  Future<Response> getDeliveryNotes({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Delivery Note', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'grand_total', 'posting_date', 'modified', 'status', 'currency', 'po_no', 'total_qty', 'creation', 'docstatus']);
  Future<Response> getDeliveryNote(String name) async => getDocument('Delivery Note', name);
  Future<Response> getPosUploads({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (filters != null && filters.containsKey('docstatus')) filters.remove('docstatus');
    return getDocumentList('POS Upload', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'date', 'modified', 'status', 'total_qty']);
  }
  Future<Response> getPosUpload(String name) async => getDocument('POS Upload', name);
  Future<Response> getTodos({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('ToDo', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'status', 'description', 'modified', 'priority', 'date']);
  Future<Response> getTodo(String name) async => getDocument('ToDo', name);
  Future<Response> getPurchaseOrders({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters, String orderBy = 'modified desc'}) async {
    return getDocumentList('Purchase Order', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'supplier', 'transaction_date', 'grand_total', 'currency', 'status', 'docstatus', 'modified', 'creation'], orderBy: orderBy);
  }
  Future<Response> getPurchaseOrder(String name) async => getDocument('Purchase Order', name);
  Future<Response> createPurchaseOrder(Map<String, dynamic> data) async => createDocument('Purchase Order', data);
  Future<Response> updatePurchaseOrder(String name, Map<String, dynamic> data) async => updateDocument('Purchase Order', name, data);
  Future<Response> login(String email, String password) async {
    if (!_dioInitialised) await _initDio();
    try {
      final response = await _dio.post('/api/method/login', data: {'usr': email, 'pwd': password});
      return response;
    } on DioException catch (e) {
      GlobalSnackbar.error(title: 'Login Error', message: e.message ?? 'An unknown error occurred');
      rethrow;
    } catch (e) {
      GlobalSnackbar.error(title: 'Login Error', message: 'An unexpected error occurred: $e');
      rethrow;
    }
  }
  Future<Response> loginWithFrappe(String username, String password) async {
    if (!_dioInitialised) await _initDio();
    try {
      final formData = FormData.fromMap({'usr': username, 'pwd': password});
      return await _dio.post('/api/method/login', data: formData, options: Options(contentType: Headers.formUrlEncodedContentType));
    } on DioException catch (e) {
      rethrow;
    }
  }
  Future<bool> hasSessionCookies() async {
    // On Web, we assume optimistic true and let API verification fail if invalid
    if (kIsWeb) return true;

    if (!_dioInitialised) await _initDio();
    final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
    return cookies.any((cookie) => cookie.name == 'sid');
  }
  Future<void> clearSessionCookies() async {
    if (!_dioInitialised) await _initDio();
    if (!kIsWeb) {
      await _cookieJar.deleteAll();
    }
  }
  Future<Response> logoutApiCall() async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post('/api/method/logout');
  }
  Future<Response> getLoggedUser() async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/method/frappe.auth.get_logged_user');
  }
  Future<Response> getUserDetails(String email) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/resource/User/$email');
  }
  Future<Response> resetPassword(String email) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post('/api/method/frappe.core.doctype.user.user.reset_password', data: {'user': email}, options: Options(contentType: Headers.formUrlEncodedContentType));
  }
  Future<Response> changePassword(String oldPassword, String newPassword) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post('/api/method/frappe.core.doctype.user.user.update_password',
        data: {'old_password': oldPassword, 'new_password': newPassword, 'logout_all_sessions': 0},
        options: Options(contentType: Headers.formUrlEncodedContentType)
    );
  }

  // Updated to include getStockLedger and ensure consistency
  Future<Response> getStockLedger({
    required String company,
    required String fromDate,
    required String toDate,
    String? itemCode,
    String? warehouse,
    String? batchNo,
    String? segregateSerialBatchBundle = 'true',
  }) async {
    if (!_dioInitialised) await _initDio();

    final Map<String, dynamic> filters = {
      "company": company,
      "from_date": fromDate,
      "to_date": toDate,
      "segregate_serial_batch_bundle": segregateSerialBatchBundle
    };

    if (itemCode != null && itemCode.isNotEmpty) filters["item_code"] = itemCode;
    if (warehouse != null && warehouse.isNotEmpty) filters["warehouse"] = warehouse;
    if (batchNo != null && batchNo.isNotEmpty) filters["batch_no"] = batchNo;

    return await _dio.get('/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name': 'Stock Ledger',
          'filters': json.encode(filters),
          'ignore_prepared_report': 'true',
          'are_default_filters': 'false',
          '_': DateTime.now().millisecondsSinceEpoch
        }
    );
  }
}