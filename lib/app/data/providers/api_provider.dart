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
  // Global Default URL
  static const String defaultBaseUrl = "https://erp.multimax.cloud";

  bool _dioInitialised = false;
  late Dio _dio;
  late CookieJar _cookieJar;
  String _baseUrl = defaultBaseUrl;

  // Expose the current base URL for UI usage (e.g. Images)
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
      receiveTimeout: const Duration(seconds: 10),
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
    _dioInitialised = true;
  }

  // --- Auth Methods ---

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

  // --- Core Fetching Methods ---

  Future<Response> callMethod(String method, {Map<String, dynamic>? params}) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/method/$method', queryParameters: params);
  }

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

  Future<Response> getReport(String reportName, {Map<String, dynamic>? filters}) async {
    if (!_dioInitialised) await _initDio();

    // Default Filters
    final Map<String, dynamic> defaultFilters = {};

    if (reportName == 'Stock Balance') {
      defaultFilters.addAll({
        "valuation_field_type": "Currency",
        "rack": [], // Default to all, but overridable
        "show_variant_attributes": 1,
        "show_dimension_wise_stock": 1,
        "from_date": DateFormat('yyyy-MM-dd').format(DateTime.now()),
        "to_date": DateFormat('yyyy-MM-dd').format(DateTime.now())
      });
    }

    // Merge passed filters ON TOP of defaults
    if (filters != null) {
      defaultFilters.addAll(filters);
    }

    return await _dio.get('/api/method/frappe.desk.query_report.run', queryParameters: {'report_name': reportName, 'filters': json.encode(defaultFilters), 'ignore_prepared_report': 'true'});
  }

  Future<Response> getBatchWiseBalance(String itemCode, String batchNo) async {
    return getReport('Batch-Wise Balance History', filters: {
      'company': 'Multimax', 'from_date': DateFormat('yyyy-MM-dd').format(DateTime.now()), 'to_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'item_code': itemCode, 'batch_no': batchNo, 'warehouse': 'WH-DXB1 - KA'
    });
  }

  // ... (Module specific getters remain same) ...
  Future<Response> getPurchaseReceipts({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async => getDocumentList('Purchase Receipt', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'owner', 'creation', 'modified', 'modified_by', 'docstatus', 'status', 'supplier', 'posting_date', 'posting_time', 'set_warehouse', 'currency', 'total_qty', 'grand_total']);
  Future<Response> getPurchaseReceipt(String name) async => getDocument('Purchase Receipt', name);
  Future<Response> getPackingSlips({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async => getDocumentList('Packing Slip', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'delivery_note', 'modified', 'creation', 'docstatus', 'custom_po_no', 'from_case_no', 'to_case_no', 'owner']);
  Future<Response> getPackingSlip(String name) async => getDocument('Packing Slip', name);
  Future<Response> getStockEntries({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async => getDocumentList('Stock Entry', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'purpose', 'total_amount', 'custom_total_qty', 'modified', 'docstatus', 'creation', 'stock_entry_type']);
  Future<Response> getStockEntry(String name) async => getDocument('Stock Entry', name);
  Future<Response> getDeliveryNotes({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async => getDocumentList('Delivery Note', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'grand_total', 'posting_date', 'modified', 'status', 'currency', 'po_no', 'total_qty', 'creation', 'docstatus']);
  Future<Response> getDeliveryNote(String name) async => getDocument('Delivery Note', name);
  Future<Response> getPosUploads({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (filters != null && filters.containsKey('docstatus')) filters.remove('docstatus');
    return getDocumentList('POS Upload', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'date', 'modified', 'status']);
  }
  Future<Response> getPosUpload(String name) async => getDocument('POS Upload', name);
  Future<Response> getTodos({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async => getDocumentList('ToDo', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'status', 'description', 'modified', 'priority', 'date']);
  Future<Response> getTodo(String name) async => getDocument('ToDo', name);
}