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
        validateStatus: (status) => true,
        // We handle status codes manually in _checkResponse
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

  // --- CORE METHODS ---

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

  Future<Map<String, dynamic>> getDocType(String doctype) async {
    try {
      final dio = await _client;
      // Fetching the DocType definition itself
      final response = await dio.get('/api/resource/DocType/$doctype');
      _checkResponse(response);
      return response.data['data'];
    } catch (e) {
      return {};
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

  // FIX: Added generic method call support to fetch item details/rates
  Future<dynamic> callMethod(
    String method, {
    Map<String, dynamic>? args,
  }) async {
    try {
      final dio = await _client;
      // GET for reads, but many RPC calls work better with POST in Frappe to avoid URL length limits
      final response = await dio.post('/api/method/$method', data: args);
      _checkResponse(response);
      return response.data['message'];
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
        if (data['results'] != null)
          results = data['results'];
        else if (data['message'] != null)
          results = data['message'];
      } else if (data is List)
        results = data;

      return results
          .map<String>((e) {
            if (e is Map) return (e['value'] ?? e['name'] ?? '').toString();
            return e.toString();
          })
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ... (getList, deleteDoc, _checkResponse, _handleError remain the same as previous step)
  // Ensure _handleError parses 417 correctly as implemented previously
  void _checkResponse(Response response) {
    if (response.statusCode != null && response.statusCode! >= 400) {
      // Create a dummy DioException to pass to _handleError logic
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Request failed with status ${response.statusCode}',
      );
    }
  }

  // --- ENHANCED ERROR HANDLING ---
  void _handleError(dynamic e) {
    if (e is DioException && e.response != null) {
      final response = e.response!;
      final data = response.data;
      final int code = response.statusCode ?? 500;

      debugPrint("RAW API ERROR ($code): $data");

      // 1. Frappe _server_messages (JSON Array of Strings)
      if (data is Map && data.containsKey('_server_messages')) {
        try {
          final messages = jsonDecode(data['_server_messages']);
          if (messages is List && messages.isNotEmpty) {
            final htmlMessages = messages
                .map((m) {
                  try {
                    final inner = jsonDecode(m);
                    return inner['message'] ?? m.toString();
                  } catch (_) {
                    return m.toString();
                  }
                })
                .join('<br><br>');

            throw Exception(htmlMessages);
          }
        } catch (_) {}
      }

      // 2. Exception Traceback
      if (data is Map && data.containsKey('exception')) {
        String exc = data['exception'].toString();
        // Return mostly clean message, but preserve format
        final parts = exc.split(':');
        // Clean "frappe.exceptions.ValidationError: Message" -> "Message"
        if (parts.length > 1) exc = parts.sublist(1).join(':').trim();
        throw Exception("<b>Server Error</b><br>$exc");
      }

      // 3. Raw HTML Response (Server 500/404/417 Pages)
      if (data is String && data.trim().startsWith('<')) {
        // Just throw the raw HTML, our ErrorDialog will render it
        throw Exception(data);
      }

      // 4. Fallback for unparsed data (e.g. unexpected JSON structure)
      if (data != null && data is Map) {
        // Dump JSON contents if nothing else matched
        throw Exception("<b>Error ($code)</b><br>${jsonEncode(data)}");
      }

      // 5. Generic HTTP Status
      if (code == 403) {
        throw Exception("<b>Access Denied</b><br>You do not have permission.");
      }
      if (code == 404) {
        throw Exception("<b>Not Found</b><br>Resource does not exist.");
      }
      if (code == 401) {
        throw Exception("<b>Session Expired</b><br>Please log in again.");
      }

      throw Exception('API Error $code: ${response.statusMessage}');
    }
    throw Exception(e.toString().replaceAll("Exception:", "").trim());
  }
}
