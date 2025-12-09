import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class LoginController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final AuthenticationController _authController = Get.find<AuthenticationController>();

  final GlobalKey<FormState> loginFormKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // Server Config
  final TextEditingController serverUrlController = TextEditingController();
  var isCheckingConnection = false.obs;

  var isLoading = false.obs;
  var isPasswordHidden = true.obs;

  @override
  void onInit() {
    super.onInit();
    _loadSavedServerUrl();
  }

  void _loadSavedServerUrl() {
    if (Get.isRegistered<StorageService>()) {
      final savedUrl = Get.find<StorageService>().getBaseUrl();
      if (savedUrl != null) {
        serverUrlController.text = savedUrl;
      } else {
        serverUrlController.text = "https://erp.multimax.cloud"; // Default
      }
    }
  }

  Future<void> saveServerConfiguration() async {
    String url = serverUrlController.text.trim();
    if (url.isEmpty) {
      Get.snackbar('Error', 'Server URL cannot be empty');
      return;
    }

    // Normalize URL
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

      // Simple health check (fetching a public endpoint or login check)
      // Since we don't have a guaranteed public health endpoint, we try the login endpoint which should respond 200 or 401, but certainly reachable.
      // Alternatively, we just save it. But let's try to get a response.
      // A get request to /api/method/ping is standard in Frappe
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 5);
      final response = await dio.get('$url/api/method/ping');

      if (response.statusCode == 200) {
        if (Get.isRegistered<StorageService>()) {
          await Get.find<StorageService>().saveBaseUrl(url);
        }
        serverUrlController.text = url;
        Get.back(); // Close bottom sheet
        Get.snackbar('Connected', 'Successfully connected to $url', backgroundColor: Colors.green, colorText: Colors.white);
      } else {
        throw Exception('Invalid response from server');
      }

    } catch (e) {
      Get.snackbar('Connection Failed', 'Could not connect to server: $url', backgroundColor: Colors.red, colorText: Colors.white);
      // Revert to old url in provider if needed, or keep as is since the user wants to change it.
    } finally {
      isCheckingConnection.value = false;
    }
  }

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    serverUrlController.dispose();
    super.onClose();
  }

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  void togglePasswordVisibility() {
    isPasswordHidden.value = !isPasswordHidden.value;
  }

  Future<void> loginUser() async {
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
          Get.snackbar('Login Failed', response.data?['message'] ?? 'Invalid credentials.', backgroundColor: Colors.red, colorText: Colors.white);
        } else {
          Get.snackbar('Login Error', response.data?['message'] ?? 'An unknown error occurred.', backgroundColor: Colors.red, colorText: Colors.white);
        }
      } catch (e) {
        Get.snackbar('Login Error', 'An unexpected error occurred.', backgroundColor: Colors.red, colorText: Colors.white);
      } finally {
        isLoading.value = false;
      }
    }
  }

  Future<void> resetPassword() async {
    if (emailController.text.isEmpty) {
      Get.snackbar('Error', 'Please enter your email address first', backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }

    isLoading.value = true;
    try {
      final response = await _apiProvider.resetPassword(emailController.text.trim());
      if (response.statusCode == 200) {
        Get.back(); // Close dialog if open
        Get.snackbar('Success', 'Password reset instructions sent to your email', backgroundColor: Colors.green, colorText: Colors.white);
      } else {
        Get.snackbar('Error', 'Failed to send reset link', backgroundColor: Colors.red, colorText: Colors.white);
      }
    } catch (e) {
      Get.snackbar('Error', 'Reset failed: $e', backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      isLoading.value = false;
    }
  }
}