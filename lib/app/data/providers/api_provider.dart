import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get/get.dart' hide Response, FormData; // For Get.find or dependency injection
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

  Future<Response> getPurchaseReceipts({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (!_dioInitialized) await _initDio();

    const String endpoint = '/api/resource/Purchase Receipt';
    final queryParameters = {
      'fields': '["name", "supplier", "grand_total", "posting_date", "modified", "status", "currency"]',
      'limit_page_length': limit,
      'limit_start': limitStart,
      'order_by': 'modified desc',
    };

    if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        return ['Purchase Receipt', entry.key, '=', entry.value];
      }).toList();
      queryParameters['filters'] = json.encode(filterList);
    }

    try {
      final response = await _dio.get(endpoint, queryParameters: queryParameters);
      return response;
    } on DioException catch (e) {
      Get.log("ApiProvider DioException during getPurchaseReceipts: ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error during getPurchaseReceipts: $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getPurchaseReceipt(String name) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/Purchase Receipt/$name';
    try {
      return await _dio.get(endpoint);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException for '$name': ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error for '$name': $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getPackingSlips({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (!_dioInitialized) await _initDio();

    const String endpoint = '/api/resource/Packing Slip';
    final queryParameters = {
      'fields': '["name", "delivery_note", "modified", "docstatus"]',
      'limit_page_length': limit,
      'limit_start': limitStart,
      'order_by': 'modified desc',
    };

    if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        return ['Packing Slip', entry.key, '=', entry.value];
      }).toList();
      queryParameters['filters'] = json.encode(filterList);
    }

    try {
      final response = await _dio.get(endpoint, queryParameters: queryParameters);
      return response;
    } on DioException catch (e) {
      Get.log("ApiProvider DioException during getPackingSlips: ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error during getPackingSlips: $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getPackingSlip(String name) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/Packing Slip/$name';
    try {
      return await _dio.get(endpoint);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException for '$name': ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error for '$name': $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getStockEntries({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (!_dioInitialized) await _initDio();

    const String endpoint = '/api/resource/Stock Entry';
    final queryParameters = {
      'fields': '["name", "purpose", "total_amount", "modified", "docstatus"]',
      'limit_page_length': limit,
      'limit_start': limitStart,
      'order_by': 'modified desc',
    };

    if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        return ['Stock Entry', entry.key, '=', entry.value];
      }).toList();
      queryParameters['filters'] = json.encode(filterList);
    }

    try {
      final response = await _dio.get(endpoint, queryParameters: queryParameters);
      return response;
    } on DioException catch (e) {
      Get.log("ApiProvider DioException during getStockEntries: ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error during getStockEntries: $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getStockEntry(String name) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/Stock Entry/$name';
    try {
      return await _dio.get(endpoint);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException for '$name': ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error for '$name': $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getDeliveryNotes({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (!_dioInitialized) await _initDio();

    const String endpoint = '/api/resource/Delivery Note';
    final queryParameters = {
      'fields': '["name", "customer", "grand_total", "posting_date", "modified", "status", "currency"]',
      'limit_page_length': limit,
      'limit_start': limitStart,
      'order_by': 'modified desc',
    };

    if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        return ['Delivery Note', entry.key, '=', entry.value];
      }).toList();
      queryParameters['filters'] = json.encode(filterList);
    }

    try {
      final response = await _dio.get(endpoint, queryParameters: queryParameters);
      return response;
    } on DioException catch (e) {
      Get.log("ApiProvider DioException during getDeliveryNotes: ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error during getDeliveryNotes: $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getDeliveryNote(String name) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/Delivery Note/$name';
    try {
      return await _dio.get(endpoint);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException for '$name': ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error for '$name': $e", isError: true);
      rethrow;
    }
  }

   Future<Response> getPosUploads({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (!_dioInitialized) await _initDio();

    const String endpoint = '/api/resource/POS Upload';
    final queryParameters = {
      'fields': '["name", "customer", "date", "modified", "status"]',
      'limit_page_length': limit,
      'limit_start': limitStart,
      'order_by': 'modified desc',
    };

    // Remove docstatus filter if it exists, as we're now filtering by 'status' field directly
    if (filters != null && filters.containsKey('docstatus')) {
      filters.remove('docstatus');
    }

    if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        return ['POS Upload', entry.key, '=', entry.value];
      }).toList();
      queryParameters['filters'] = json.encode(filterList);
    }

    try {
      final response = await _dio.get(endpoint, queryParameters: queryParameters);
      return response;
    } on DioException catch (e) {
      Get.log("ApiProvider DioException during getPosUploads: ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error during getPosUploads: $e", isError: true);
      rethrow;
    }
  }

  Future<Response> getPosUpload(String name) async {
    if (!_dioInitialized) await _initDio();
    final String endpoint = '/api/resource/POS Upload/$name';
    try {
      return await _dio.get(endpoint);
    } on DioException catch (e) {
      Get.log("ApiProvider DioException for '$name': ${e.message} - ${e.response?.data}", isError: true);
      rethrow;
    } catch (e) {
      Get.log("ApiProvider generic error for '$name': $e", isError: true);
      rethrow;
    }
  }
}
