import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get/get.dart' hide Response, FormData; // For Get.find or dependency injection
import 'package:path_provider/path_provider.dart'; // To get a persistent storage path for cookies

class ApiProvider {
  // Add a flag in ApiProvider class
  bool _dioInitialized = false;

  late Dio _dio;
  late CookieJar _cookieJar;

  // Base URL for your API
  // Ensure this is your Frappe site URL
  final String _baseUrl = "https://erp.multimax.cloud"; // Replace with your actual API base URL

  ApiProvider() {
    _initDio();
  }

  // Modify _initDio
  Future<void> _initDio() async {
    if (_dioInitialized) return; // Prevent re-initialization

    final appDocDir = await getApplicationDocumentsDirectory();
    final cookiePath = '${appDocDir.path}/.cookies/';

    // ... rest of _initDio
    // Get a persistent directory to store cookies
    _cookieJar = PersistCookieJar(
      ignoreExpires: true, // If true, cookies will persist until explicitly deleted
      storage: FileStorage(cookiePath),
    );

    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10), // 10 seconds
      receiveTimeout: const Duration(seconds: 10), // 10 seconds
      // Frappe login expects form data
      // ContentType.json is not default for Frappe login,
      // but we'll set it per-request for login.
      // For other calls that need JSON, you'd set:
      // headers: {
      //   Headers.contentTypeHeader: Headers.jsonContentType,
      //   Headers.acceptHeader: Headers.jsonContentType,
      // }
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true)); // For debugging

    _dioInitialized = true; // Set flag after successful initialization
  }

  Future<Response> login(String email, String password) async {
    // Ensure Dio is initialized before making a request
    if (_dio == null) await _initDio(); // Or handle this more gracefully in a real app

    try {
      final response = await _dio.post(
        '/api/method/login', // Replace with your actual login endpoint
        data: {
          'usr': email,
          'pwd': password,
        },
      );
      return response;
    } on DioException catch (e) {
      // Handle Dio errors (e.g., network issues, timeouts, specific HTTP error codes)
      // You might want to throw a custom exception or return a specific error object
      Get.snackbar('Login Error', e.message ?? 'An unknown error occurred');
      rethrow;
    } catch (e) {
      Get.snackbar('Login Error', 'An unexpected error occurred: $e');
      rethrow;
    }
  }

  // --- FRAPPE LOGIN METHOD ---
  Future<Response> loginWithFrappe(String username, String password) async {
    if (!_dioInitialized) await _initDio();

    // Frappe login endpoint
    const String loginEndpoint = '/api/method/login';

    // Data needs to be sent as FormData
    final formData = FormData.fromMap({
      'usr': username,
      'pwd': password,
    });

    try {
      final response = await _dio.post(
        loginEndpoint,
        data: formData,
        options: Options(
          // Frappe login expects x-www-form-urlencoded
          contentType: Headers.formUrlEncodedContentType,
          // Important for Dio to correctly process the response even if it's not strictly JSON (e.g. plain text success)
          // However, Frappe login usually does return JSON on success/failure.
          // responseType: ResponseType.json, // Default is json, usually fine
        ),
      );
      return response;
    } on DioException catch (e) {
      // Log or handle specific Dio errors here if needed before rethrowing
      printError(info: "ApiProvider DioException during login: ${e.message} - ${e.response?.data}");
      // The LoginController will handle showing user-facing snackbars
      rethrow;
    } catch (e) {
      printError(info: "ApiProvider generic error during login: $e");
      rethrow;
    }
  }

  Future<bool> hasSessionCookies() async {
    if (!_dioInitialized) await _initDio();
    // Check for the 'sid' cookie, which is Frappe's session ID
    final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
    bool sidExists = cookies.any((cookie) => cookie.name == 'sid');
    printInfo(info: "Session ID (sid) exists: $sidExists");
    return sidExists;
  }

  Future<void> clearSessionCookies() async {
    if (!_dioInitialized) await _initDio();
    await _cookieJar.deleteAll();
    printInfo(info: "All session cookies cleared (Frappe sid included).");
  }

  // Example: Method to fetch logged-in user details (after login)
  Future<Response> getLoggedUser() async {
    if (!_dioInitialized) await _initDio();
    try {
      final response = await _dio.get('/api/method/frappe.auth.get_logged_user');
      return response;
    } on DioException catch (e) {
      printError(info: "ApiProvider DioException during getLoggedUser: ${e.message}");
      rethrow;
    }
  }

  // Helper to expose cookies if needed, for instance, to read 'full_name'
  Future<List<Cookie>> loadCookiesForBaseUrl() async {
    if (!_dioInitialized) await _initDio();
    return _cookieJar.loadForRequest(Uri.parse(_baseUrl));
  }

// Optional: If your backend has a specific logout endpoint
// Future<void> logoutApiCall() async {
//   if (!_dioInitialized) await _initDio();
//   try {
//     // Replace with your actual logout endpoint and method (POST, GET, etc.)
//     await _dio.post('/auth/logout');
//     printInfo(info: "Successfully called API logout endpoint.");
//   } on DioException catch (e) {
//     // Handle error, but don't let it block client-side logout
//     printError(info: "API logout request failed: ${e.message}");
//     // You might not want to rethrow here as client-side logout should still proceed
//   }
// }
// Add other API methods here (e.g., fetchUserData, postStockEntry)
}
