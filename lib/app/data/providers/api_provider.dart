import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get/get.dart' hide Response, FormData; // For Get.find or dependency injection
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart'; // To get a persistent storage path for cookies

class ApiProvider {
  bool _dioInitialized = false;

  late Dio _dio;
  late CookieJar _cookieJar;

  final String _baseUrl = "https://erp.multimax.cloud";

  ApiProvider() {
    _initDio();
  }

  Future<void> _initDio() async {
    if (_dioInitialized) return;

    final appSupportDir = await getApplicationSupportDirectory();
    final cookiePath = '${appSupportDir.path}/.cookies/';

    _cookieJar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage(cookiePath),
    );

    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));

    _dioInitialized = true;
  }

  Future<Response> login(String email, String password) async {
    if (!_dioInitialized) await _initDio();

    try {
      final response = await _dio.post(
        '/api/method/login',
        data: {'usr': email, 'pwd': password},
      );
      return response;
    } on DioException catch (e) {
      Get.snackbar('Login Error', e.message ?? 'An unknown error occurred');
      rethrow;
    } catch (e) {
      Get.snackbar('Login Error', 'An unexpected error occurred: $e');
      rethrow;
    }
  }

  Future<Response> loginWithFrappe(String username, String password) async {
    if (!_dioInitialized) await _initDio();

    const String loginEndpoint = '/api/method/login';

    final formData = FormData.fromMap({
      'usr': username,
      'pwd': password,
    });

    try {
      final response = await _dio.post(
        loginEndpoint,
        data: formData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      return response;
    } on DioException catch (e) {
      printError(info: "ApiProvider DioException during login: ${e.message} - ${e.response?.data}");
      rethrow;
    } catch (e) {
      printError(info: "ApiProvider generic error during login: $e");
      rethrow;
    }
  }

  Future<bool> hasSessionCookies() async {
    if (!_dioInitialized) await _initDio();
    final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
    return cookies.any((cookie) => cookie.name == 'sid');
  }

  Future<void> clearSessionCookies() async {
    if (!_dioInitialized) await _initDio();
    await _cookieJar.deleteAll();
  }

  Future<Response> logoutApiCall() async {
    if (!_dioInitialized) await _initDio();
    try {
      return await _dio.post('/api/method/logout');
    } on DioException catch (e) {
      // It's okay if this fails, e.g. if the session was already expired.
      printError(info: "Logout API call failed, but this might be okay: ${e.message}");
      rethrow;
    }
  }

  Future<Response> getLoggedUser() async {
    if (!_dioInitialized) await _initDio();
    try {
      return await _dio.get('/api/method/frappe.auth.get_logged_user');
    } on DioException catch (e) {
      printError(info: "ApiProvider DioException during getLoggedUser: ${e.message}");
      rethrow;
    }
  }

  Future<Response> getUserDetails(String email) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/User/$email';
    try {
      return await _dio.get(endpoint);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException for User '$email': ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error for User '$email': $e", isError: true);
      rethrow;
    }
  }

  Future<List<Cookie>> loadCookiesForBaseUrl() async {
    if (!_dioInitialized) await _initDio();
    return _cookieJar.loadForRequest(Uri.parse(_baseUrl));
  }

  // --- Generic Document Fetching Methods ---

  Future<Response> getDocumentList(String doctype, {
    int limit = 20,
    int limitStart = 0,
    List<String>? fields,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    if (!_dioInitialized) await _initDio();

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
        return [doctype, entry.key, '=', entry.value];
      }).toList();
      queryParameters['filters'] = json.encode(filterList);
    }

    try {
      final response = await _dio.get(endpoint, queryParameters: queryParameters);
      return response;
    } on DioException catch (e) {
      Get.log("ApiProvider DioException during getDocumentList for $doctype: ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error during getDocumentList for $doctype: $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getDocument(String doctype, String name) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/$doctype/$name';
    try {
      return await _dio.get(endpoint);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException for $doctype '$name': ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error for $doctype '$name': $e", isError: true);
      rethrow;
    }
  }

  Future<Response> createDocument(String doctype, Map<String, dynamic> data) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/$doctype';
    try {
      return await _dio.post(endpoint, data: data);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException during createDocument for $doctype: ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error during createDocument for $doctype: $e", isError: true);
      rethrow;
    }
  }

  Future<Response> updateDocument(String doctype, String name, Map<String, dynamic> data) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/$doctype/$name';
    try {
      return await _dio.put(endpoint, data: data);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException during updateDocument for $doctype '$name': ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error during updateDocument for $doctype '$name': $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getReport(String reportName, {Map<String, dynamic>? filters}) async {
    if (!_dioInitialized) await _initDio();
    
    Map<String, dynamic> allFilters = {};

    if (reportName == 'Stock Balance') {
      allFilters = {
        "valuation_field_type": "Currency",
        "rack": [],
        "show_variant_attributes": 1,
        "show_dimension_wise_stock": 1,
        "from_date": DateFormat('yyyy-MM-dd').format(DateTime.now()),
        "to_date": DateFormat('yyyy-MM-dd').format(DateTime.now()),
        ...filters ?? {},
      };
    } else {
      allFilters = filters ?? {};
    }

    try {
      return await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name': reportName,
          'filters': json.encode(allFilters),
          'ignore_prepared_report': 'true',
        },
      );
    } on DioException catch (e) {
      Get.log("ApiProvider DioException fetching Report '$reportName': ${e.message}", isError: true);
      rethrow;
    }
  }

  Future<Response> getBatchWiseBalance(String itemCode, String batchNo) async {
    return getReport('Batch-Wise Balance History', filters: {
      'company': 'Multimax',
      'from_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'to_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'item_code': itemCode,
      'batch_no': batchNo,
      'warehouse': 'WH-DXB1 - KA'
    });
  }

  // --- Specific Document Methods (kept for compatibility, but can be refactored to use generic methods) ---

  Future<Response> getPurchaseReceipts({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return getDocumentList('Purchase Receipt', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'owner', 'creation', 'modified', 'modified_by', 'docstatus', 'status', 'supplier', 'posting_date', 'posting_time', 'set_warehouse', 'currency', 'total_qty', 'grand_total']);
  }

  Future<Response> getPurchaseReceipt(String name) async {
    return getDocument('Purchase Receipt', name);
  }

  Future<Response> getPackingSlips({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return getDocumentList('Packing Slip', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'delivery_note', 'modified', 'docstatus']);
  }

  Future<Response> getPackingSlip(String name) async {
    return getDocument('Packing Slip', name);
  }

  Future<Response> getStockEntries({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return getDocumentList('Stock Entry', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'purpose', 'total_amount', 'custom_total_qty', 'modified', 'docstatus', 'creation']);
  }

  Future<Response> getStockEntry(String name) async {
    return getDocument('Stock Entry', name);
  }

  Future<Response> getDeliveryNotes({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return getDocumentList('Delivery Note', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'grand_total', 'posting_date', 'modified', 'status', 'currency', 'po_no', 'total_qty', 'creation', 'docstatus']);
  }

  Future<Response> getDeliveryNote(String name) async {
    return getDocument('Delivery Note', name);
  }

   Future<Response> getPosUploads({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (filters != null && filters.containsKey('docstatus')) {
      filters.remove('docstatus'); 
    }
    
    return getDocumentList('POS Upload', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'date', 'modified', 'status']);
  }

  Future<Response> getPosUpload(String name) async {
    return getDocument('POS Upload', name);
  }

  Future<Response> getTodos({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return getDocumentList('ToDo', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'status', 'description', 'modified', 'priority', 'date']);
  }

  Future<Response> getTodo(String name) async {
    return getDocument('ToDo', name);
  }
}
