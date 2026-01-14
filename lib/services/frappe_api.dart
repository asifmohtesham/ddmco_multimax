import 'dart:convert'; // Import for jsonEncode
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

  // --- EXISTING METHODS (getDoc, saveDoc, searchLink) ---

  Future<Map<String, dynamic>> getDoc(String doctype, String name) async {
    try {
      final dio = await _client;
      final encodedName = Uri.encodeComponent(name);
      final response = await dio.get('/api/resource/$doctype/$encodedName');
      return response.data['data'];
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  Future<void> saveDoc(String doctype, Map<String, dynamic> data) async {
    try {
      final dio = await _client;
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

  Future<List<String>> searchLink(String doctype, String txt) async {
    try {
      final dio = await _client;
      final response = await dio.post(
        '/api/method/frappe.desk.search.search_link',
        data: {'doctype': doctype, 'txt': txt, 'page_length': 20},
      );
      final List results = response.data['results'] ?? [];
      return results.map<String>((e) => e['value'].toString()).toList();
    } catch (e) {
      return [];
    }
  }

  // --- NEW METHODS FOR LIST CONTROLLER ---

  /// Fetch a list of documents with standard Frappe params
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

      if (response.statusCode == 200 && response.data['data'] != null) {
        return List<Map<String, dynamic>>.from(response.data['data']);
      }
      return [];
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  /// Delete a document
  Future<void> deleteDoc(String doctype, String name) async {
    try {
      final dio = await _client;
      final encodedName = Uri.encodeComponent(name);
      await dio.delete('/api/resource/$doctype/$encodedName');
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  void _handleError(dynamic e) {
    if (e is DioException) {
      if (e.response?.statusCode == 403) throw Exception("Access Denied (403)");
      if (e.response?.statusCode == 404) throw Exception("Not Found (404)");
      throw Exception('API Error ${e.response?.statusCode}: ${e.message}');
    }
    throw Exception('Unknown Error: $e');
  }
}
