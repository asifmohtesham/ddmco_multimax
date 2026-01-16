import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class LoginController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final AuthenticationController _authController = Get.find<AuthenticationController>();
  final DatabaseService _dbService = Get.find<DatabaseService>();

  final GlobalKey<FormState> loginFormKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // Server Config
  final TextEditingController serverUrlController = TextEditingController();

  // Observable string for UI indication
  var currentServerUrl = ''.obs;

  var isCheckingConnection = false.obs;
  var isLoading = false.obs;
  var isPasswordHidden = true.obs;

  // UI State for Guide
  var showServerGuide = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadSavedServerUrl();
  }

  Future<void> _loadSavedServerUrl() async {
    final savedUrl = await _dbService.getConfig(DatabaseService.serverUrlKey);
    // Use saved URL or fallback to default
    final targetUrl = savedUrl ?? ApiProvider.defaultBaseUrl;

    // Populate the Text Field Controller
    serverUrlController.text = targetUrl;

    // Update the observable for the UI label
    currentServerUrl.value = targetUrl;

    // Ensure API Provider is synced
    _apiProvider.setBaseUrl(targetUrl);
  }

  Future<void> saveServerConfiguration() async {
    String url = serverUrlController.text.trim();
    if (url.isEmpty) {
      GlobalSnackbar.error(message: 'Server URL cannot be empty');
      return;
    }

    // Normalise URL
    if (!url.startsWith('http')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    isCheckingConnection.value = true;
    try {
      // Update Provider temporarily to test connection
      _apiProvider.setBaseUrl(url);

      // Simple health check
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 5);
      final response = await dio.get('$url/api/method/ping');

      if (response.statusCode == 200) {
        await _confirmAndSave(url);
        GlobalSnackbar.success(message: 'Successfully connected to $url');
        // Disable guide if successful
        showServerGuide.value = false;
      } else {
        throw Exception('Invalid response from server (Status: ${response.statusCode})');
      }

    } catch (e) {
      isCheckingConnection.value = false;
      Get.defaultDialog(
        title: "Connection Failed",
        middleText: "Could not verify connection to the server.\n\nError: $e\n\nDo you want to save this URL anyway?",
        textConfirm: "Save Anyway",
        textCancel: "Cancel",
        confirmTextColor: Colors.white,
        onConfirm: () async {
          Get.back();
          await _confirmAndSave(url);
          GlobalSnackbar.success(message: 'Server URL saved (Validation skipped)');
          showServerGuide.value = false;
        },
      );
    } finally {
      isCheckingConnection.value = false;
    }
  }

  // Helper function to save and close
  Future<void> _confirmAndSave(String url) async {
    // Save to SQLite
    await _dbService.saveConfig(DatabaseService.serverUrlKey, url);
    serverUrlController.text = url;
    currentServerUrl.value = url; // Update the UI label
    _apiProvider.setBaseUrl(url);
    Get.back();
  }

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    serverUrlController.dispose();
    super.onClose();
  }

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  void togglePasswordVisibility() => isPasswordHidden.value = !isPasswordHidden.value;

  Future<void> loginUser() async {
    // Check if Server URL is configured in DB
    final storedUrl = await _dbService.getConfig(DatabaseService.serverUrlKey);

    if (storedUrl == null || storedUrl.isEmpty) {
      showServerGuide.value = true;
      Get.snackbar(
        "Configuration Required",
        "Please set the Server URL using the settings icon above before logging in.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.orangeAccent,
        colorText: Colors.white,
        icon: const Icon(Icons.settings_suggest, color: Colors.white),
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(16),
      );
      return;
    }

    if (loginFormKey.currentState!.validate()) {
      isLoading.value = true;
      try {
        final response = await _apiProvider.loginWithFrappe(
          emailController.text.trim(),
          passwordController.text.trim(),
        );

        if (response.statusCode == 200 && response.data?['message'] == "Logged In") {
          await _authController.fetchUserDetails();
          if (_authController.currentUser.value != null) {
            _authController.processSuccessfulLogin(_authController.currentUser.value!);
          } else {
            final String fullName = response.data?['full_name'] ?? "User";
            final user = User(
              id: emailController.text.trim(),
              name: fullName,
              email: emailController.text.trim(),
              roles: [],
            );
            _authController.processSuccessfulLogin(user);
          }
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          GlobalSnackbar.error(message: response.data?['message'] ?? 'Invalid credentials.');
        } else {
          GlobalSnackbar.error(message: response.data?['message'] ?? 'An unknown error occurred.');
        }
      } catch (e) {
        GlobalSnackbar.error(message: 'An unexpected error occurred.');
      } finally {
        isLoading.value = false;
      }
    }
  }

  Future<void> resetPassword() async {
    if (emailController.text.isEmpty) {
      GlobalSnackbar.error(message: 'Please enter your email address first');
      return;
    }
    isLoading.value = true;
    try {
      final response = await _apiProvider.resetPassword(emailController.text.trim());
      if (response.statusCode == 200) {
        Get.back();
        GlobalSnackbar.success(message: 'Password reset instructions sent to your email');
      } else {
        GlobalSnackbar.error(message: 'Failed to send reset link');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Reset failed: $e');
    } finally {
      isLoading.value = false;
    }
  }
}