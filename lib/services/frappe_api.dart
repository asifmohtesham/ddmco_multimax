import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response, FormData;
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/database_service.dart';

class FrappeApiService {
  static final FrappeApiService _instance = FrappeApiService._internal();
  late Dio _dio;
  bool _isInitialized = false;
  String _baseUrl = "https://erp.multimax.cloud";

  factory FrappeApiService() {
    return _instance;
  }

  FrappeApiService._internal();

  Future<void> init() async {
    if (_isInitialized) return;

    if (Get.isRegistered<DatabaseService>()) {
      try {
        final dbService = Get.find<DatabaseService>();
        final storedUrl = await dbService.getConfig(
          DatabaseService.serverUrlKey,
        );
        if (storedUrl != null && storedUrl.isNotEmpty) _baseUrl = storedUrl;
      } catch (e) {
        debugPrint("DatabaseService lookup failed: $e");
      }
    }

    if (Get.isRegistered<StorageService>()) {
      final storedUrl = Get.find<StorageService>().getBaseUrl();
      if (storedUrl != null && storedUrl.isNotEmpty) _baseUrl = storedUrl;
    }

    late CookieJar cookieJar;
    if (!kIsWeb) {
      final appSupportDir = await getApplicationSupportDirectory();
      final cookiePath = '${appSupportDir.path}/.cookies/';
      cookieJar = PersistCookieJar(
        ignoreExpires: true,
        storage: FileStorage(cookiePath),
      );
    } else {
      cookieJar = CookieJar();
    }

    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        // Validate status must be lenient to allow us to parse 417 errors manually
        validateStatus: (status) {
          return status != null && status < 500;
        },
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    if (!kIsWeb) {
      _dio.interceptors.add(CookieManager(cookieJar));
    }

    _isInitialized = true;
  }

  Future<Dio> get _client async {
    if (!_isInitialized) await init();
    return _dio;
  }

  String get baseUrl => _baseUrl;

  // --- METHODS ---

  Future<Map<String, dynamic>> getDoc(String doctype, String name) async {
    try {
      final dio = await _client;
      final encodedName = Uri.encodeComponent(name);
      final response = await dio.get('/api/resource/$doctype/$encodedName');
      _checkResponse(response);
      return response.data['data'];
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // FIX: Added method to fetch DocType Metadata
  Future<Map<String, dynamic>> getDocType(String doctype) async {
    try {
      final dio = await _client;
      // Fetching the DocType definition itself
      final response = await dio.get('/api/resource/DocType/$doctype');
      _checkResponse(response);
      return response.data['data'];
    } catch (e) {
      debugPrint("Failed to fetch metadata for $doctype: $e");
      return {};
    }
  }

  Future<void> saveDoc(String doctype, Map<String, dynamic> data) async {
    try {
      final dio = await _client;
      final submitData = Map<String, dynamic>.from(data);
      submitData.removeWhere((key, value) => key.startsWith('__'));

      Response response;
      if (data.containsKey('name') &&
          data['name'] != null &&
          !data.containsKey('__islocal')) {
        final encodedName = Uri.encodeComponent(data['name']);
        response = await dio.put(
          '/api/resource/$doctype/$encodedName',
          data: submitData,
        );
      } else {
        response = await dio.post('/api/resource/$doctype', data: submitData);
      }
      _checkResponse(response);
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  Future<List<String>> searchLink(String doctype, String txt) async {
    try {
      final dio = await _client;
      final response = await dio.post(
        '/api/method/frappe.desk.search.search_link',
        data: {'doctype': doctype, 'txt': txt, 'page_length': 20},
      );

      final data = response.data;
      List results = [];

      if (data is Map) {
        if (data['results'] != null) {
          results = data['results'];
        } else if (data['message'] != null) {
          results = data['message'];
        }
      } else if (data is List) {
        results = data;
      }

      return results
          .map<String>((e) {
            if (e is Map) {
              return (e['value'] ?? e['name'] ?? '').toString();
            }
            return e.toString();
          })
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getList({
    required String doctype,
    List<String>? fields,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
    int limit = 20,
    int limitStart = 0,
  }) async {
    try {
      final dio = await _client;
      final response = await dio.get(
        '/api/resource/$doctype',
        queryParameters: {
          'fields': jsonEncode(fields ?? ["name", "status", "modified"]),
          'filters': jsonEncode(filters ?? {}),
          'order_by': orderBy,
          'limit': limit,
          'limit_start': limitStart,
        },
      );

      _checkResponse(response);

      if (response.data['data'] != null) {
        return List<Map<String, dynamic>>.from(response.data['data']);
      }
      return [];
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  Future<void> deleteDoc(String doctype, String name) async {
    try {
      final dio = await _client;
      final encodedName = Uri.encodeComponent(name);
      final response = await dio.delete('/api/resource/$doctype/$encodedName');
      _checkResponse(response);
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // Helper to throw exception if status code is bad (since we loosened validateStatus)
  void _checkResponse(Response response) {
    if (response.statusCode != null && response.statusCode! >= 400) {
      // Create a dummy DioException to pass to _handleError logic
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
  }

  // --- ENHANCED ERROR HANDLING ---
  void _handleError(dynamic e) {
    if (e is DioException && e.response != null) {
      final response = e.response!;
      final data = response.data;

      // 1. Try extracting Frappe Server Messages (JSON String Array)
      if (data is Map && data.containsKey('_server_messages')) {
        try {
          final messages = jsonDecode(data['_server_messages']);
          if (messages is List && messages.isNotEmpty) {
            final cleanMsg = messages
                .map((m) {
                  try {
                    final inner = jsonDecode(m);
                    return inner['message'] ?? m.toString();
                  } catch (_) {
                    return m.toString();
                  }
                })
                .join('\n');

            // Throw just the clean message
            throw Exception(cleanMsg);
          }
        } catch (_) {}
      }

      // 2. Try extracting Exception Traceback
      if (data is Map && data.containsKey('exception')) {
        final exc = data['exception'].toString();
        // Remove Python class path if possible (e.g. frappe.exceptions.ValidationError: Message)
        final parts = exc.split(':');
        if (parts.length > 1) {
          throw Exception(parts.sublist(1).join(':').trim());
        }
        throw Exception(exc);
      }

      // 3. Fallback to Status Codes
      final code = response.statusCode;
      if (code == 417)
        throw Exception(
          "Validation Error: Please check required fields or stock availability.",
        );
      if (code == 403)
        throw Exception("Access Denied: You don't have permission.");
      if (code == 404) throw Exception("Not Found: Resource doesn't exist.");
      if (code == 401) throw Exception("Session Expired: Please login again.");
      if (code == 409)
        throw Exception("Duplicate Entry: Record already exists.");

      throw Exception('API Error $code: ${response.statusMessage}');
    }

    throw Exception(e.toString().replaceAll("Exception:", "").trim());
  }
}
