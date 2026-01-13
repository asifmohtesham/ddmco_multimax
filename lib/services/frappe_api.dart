import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response, FormData;
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/database_service.dart'; // Import if available, else optional checks handle it

class FrappeApiService {
  static final FrappeApiService _instance = FrappeApiService._internal();
  late Dio _dio;
  bool _isInitialized = false;

  // Default fallback if storage is empty
  String _baseUrl = "https://erp.multimax.cloud";

  factory FrappeApiService() {
    return _instance;
  }

  FrappeApiService._internal();

  /// Initializes Dio with Cookies, Base URL from Storage, and Timeouts
  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Resolve Base URL from Storage/Database
    if (Get.isRegistered<DatabaseService>()) {
      try {
        final dbService = Get.find<DatabaseService>();
        final storedUrl = await dbService.getConfig(DatabaseService.serverUrlKey);
        if (storedUrl != null && storedUrl.isNotEmpty) {
          _baseUrl = storedUrl;
        }
      } catch (e) {
        debugPrint("DatabaseService lookup failed: $e");
      }
    }

    if (Get.isRegistered<StorageService>()) {
      final storedUrl = Get.find<StorageService>().getBaseUrl();
      if (storedUrl != null && storedUrl.isNotEmpty) {
        _baseUrl = storedUrl;
      }
    }

    // 2. Setup Cookie Jar
    late CookieJar cookieJar;
    if (!kIsWeb) {
      final appSupportDir = await getApplicationSupportDirectory();
      final cookiePath = '${appSupportDir.path}/.cookies/';
      cookieJar = PersistCookieJar(ignoreExpires: true, storage: FileStorage(cookiePath));
    } else {
      cookieJar = CookieJar();
    }

    // 3. Configure Dio
    _dio = Dio(BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        }
    ));

    if (!kIsWeb) {
      _dio.interceptors.add(CookieManager(cookieJar));
    }

    // Add logging for easier debugging
    _dio.interceptors.add(LogInterceptor(
        request: false,
        requestHeader: false,
        responseHeader: false,
        error: true,
        logPrint: (obj) => debugPrint("API: $obj")
    ));

    _isInitialized = true;
    debugPrint("✅ FrappeApiService Initialized with URL: $_baseUrl");
  }

  /// Ensure Dio is initialized before usage
  Future<Dio> get _client async {
    if (!_isInitialized) await init();
    return _dio;
  }

  String get baseUrl => _baseUrl;

  // ---------------------------------------------------------------------------
  // CORE METHODS
  // ---------------------------------------------------------------------------

  /// 1. Fetch Document (Get Data)
  Future<Map<String, dynamic>> getDoc(String doctype, String name) async {
    try {
      final dio = await _client;
      // Critical: Encode the ID to handle special characters (e.g. /, #)
      final encodedName = Uri.encodeComponent(name);
      final response = await dio.get('/api/resource/$doctype/$encodedName');
      return response.data['data'];
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  /// 2. Save Document (Create or Update)
  Future<void> saveDoc(String doctype, Map<String, dynamic> data) async {
    try {
      final dio = await _client;
      // If data has a 'name' (ID), it's an update (PUT). Otherwise, it's new (POST).
      if (data.containsKey('name') && data['name'] != null) {
        final encodedName = Uri.encodeComponent(data['name']);
        await dio.put('/api/resource/$doctype/$encodedName', data: data);
      } else {
        await dio.post('/api/resource/$doctype', data: data);
      }
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  /// 3. Link Field Search
  Future<List<String>> searchLink(String doctype, String txt) async {
    try {
      final dio = await _client;
      final response = await dio.post('/api/method/frappe.desk.search.search_link', data: {
        'doctype': doctype,
        'txt': txt,
        'page_length': 20,
      });

      final List results = response.data['results'] ?? [];
      return results.map<String>((e) => e['value'].toString()).toList();
    } catch (e) {
      debugPrint("Search Link Error: $e");
      return [];
    }
  }

  void _handleError(dynamic e) {
    if (e is DioException) {
      if (e.response?.statusCode == 403) {
        throw Exception("Access Denied (403). Please check permissions or login status.");
      } else if (e.response?.statusCode == 404) {
        throw Exception("Document not found (404).");
      }
      throw Exception('API Error ${e.response?.statusCode}: ${e.message}');
    }
    throw Exception('Unknown Error: $e');
  }
}