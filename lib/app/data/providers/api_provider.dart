import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get/get.dart' hide Response, FormData;
import 'package:intl/intl.dart';
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
    if (Get.isRegistered<StorageService>()) {
      final storedUrl = Get.find<StorageService>().getBaseUrl();
      if (storedUrl != null && storedUrl.isNotEmpty) {
        _baseUrl = storedUrl;
      }
    }
    final appSupportDir = await getApplicationSupportDirectory();
    final cookiePath = '${appSupportDir.path}/.cookies/';
    _cookieJar = PersistCookieJar(ignoreExpires: true, storage: FileStorage(cookiePath));
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
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

    if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        if (entry.value is List && (entry.value as List).length == 2) {
          return [doctype, entry.key, entry.value[0], entry.value[1]];
        }
        return [doctype, entry.key, '=', entry.value];
      }).toList();

      queryParameters['filters'] = json.encode(filterList);
    }

    try {
      return await _dio.get(endpoint, queryParameters: queryParameters);
    } on DioException catch (e) {
      rethrow;
    }
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
    String? rack, // Added rack parameter
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final String company = storage.getCompany();

    // Priority: Argument -> Error
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
      // "warehouse": targetWarehouse,
      "valuation_field_type": "Currency",
      "rack": rack != null && rack.isNotEmpty ? [rack] : [], // Updated to filter by rack
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

  // Updated to query "Batch-Wise Balance History" with specific filters
  Future<Response> getBatchWiseBalance(String itemCode, String batchNo, {String? warehouse}) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final String company = storage.getCompany();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final Map<String, dynamic> filters = {
      "company": company,
      "from_date": today,
      "to_date": today,
      "item_code": itemCode,
      "batch_no": batchNo,
    };

    if (warehouse != null && warehouse.isNotEmpty) {
      filters["warehouse"] = warehouse;
    }

    return await _dio.get('/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name': 'Batch-Wise Balance History',
          'filters': json.encode(filters),
          'ignore_prepared_report': 'true', // Ensure we get fresh data
          'are_default_filters': 'false',
          '_': DateTime.now().millisecondsSinceEpoch
        }
    );
  }

  // ---------------------------------------------------------------------------
  // MODULE SPECIFIC GETTERS
  // ---------------------------------------------------------------------------

  // Purchase Receipt
  Future<Response> getPurchaseReceipts({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Purchase Receipt', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'owner', 'creation', 'modified', 'modified_by', 'docstatus', 'status', 'supplier', 'posting_date', 'posting_time', 'set_warehouse', 'currency', 'total_qty', 'grand_total']);

  Future<Response> getPurchaseReceipt(String name) async => getDocument('Purchase Receipt', name);

  // Packing Slip
  Future<Response> getPackingSlips({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Packing Slip', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'delivery_note', 'modified', 'creation', 'docstatus', 'custom_po_no', 'from_case_no', 'to_case_no', 'owner']);

  Future<Response> getPackingSlip(String name) async => getDocument('Packing Slip', name);

  // Stock Entry
  Future<Response> getStockEntries({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Stock Entry', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'purpose', 'total_amount', 'custom_total_qty', 'modified', 'docstatus', 'creation', 'stock_entry_type']);

  Future<Response> getStockEntry(String name) async => getDocument('Stock Entry', name);

  // Delivery Note
  Future<Response> getDeliveryNotes({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Delivery Note', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'grand_total', 'posting_date', 'modified', 'status', 'currency', 'po_no', 'total_qty', 'creation', 'docstatus']);

  Future<Response> getDeliveryNote(String name) async => getDocument('Delivery Note', name);

  // POS Upload
  Future<Response> getPosUploads({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (filters != null && filters.containsKey('docstatus')) filters.remove('docstatus');
    return getDocumentList('POS Upload', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'date', 'modified', 'status', 'total_qty']);
  }

  Future<Response> getPosUpload(String name) async => getDocument('POS Upload', name);

  // ToDo
  Future<Response> getTodos({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('ToDo', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'status', 'description', 'modified', 'priority', 'date']);

  Future<Response> getTodo(String name) async => getDocument('ToDo', name);

  // Purchase Order
  Future<Response> getPurchaseOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return getDocumentList(
      'Purchase Order',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      fields: ['name', 'supplier', 'transaction_date', 'grand_total', 'currency', 'status', 'docstatus', 'modified', 'creation'],
      orderBy: orderBy,
    );
  }

  Future<Response> getPurchaseOrder(String name) async => getDocument('Purchase Order', name);
  Future<Response> createPurchaseOrder(Map<String, dynamic> data) async => createDocument('Purchase Order', data);
  Future<Response> updatePurchaseOrder(String name, Map<String, dynamic> data) async => updateDocument('Purchase Order', name, data);

  // ---------------------------------------------------------------------------
  // AUTHENTICATION
  // ---------------------------------------------------------------------------

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
    if (!_dioInitialised) await _initDio();
    final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
    return cookies.any((cookie) => cookie.name == 'sid');
  }

  Future<void> clearSessionCookies() async {
    if (!_dioInitialised) await _initDio();
    await _cookieJar.deleteAll();
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
}