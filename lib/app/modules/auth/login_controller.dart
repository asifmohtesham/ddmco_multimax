import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

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
        serverUrlController.text = ApiProvider.defaultBaseUrl; // Changed
      }
    }
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
        await _confirmAndSave(url); // Success path
        GlobalSnackbar.success(title: 'Connected', message: 'Successfully connected to $url');
      } else {
        throw Exception('Invalid response from server (Status: ${response.statusCode})');
      }

    } catch (e) {
      // Connection Failed: Ask user if they want to force it
      isCheckingConnection.value = false; // Stop loading before showing dialog
      Get.defaultDialog(
        title: "Connection Failed",
        middleText: "Could not verify connection to the server.\n\nError: $e\n\nDo you want to save this URL anyway?",
        textConfirm: "Save Anyway",
        textCancel: "Cancel",
        confirmTextColor: Colors.white,
        onConfirm: () async {
          Get.back(); // Close dialog
          await _confirmAndSave(url); // Force save
          GlobalSnackbar.success(title: 'Saved', message: 'Server URL saved (Validation skipped)');
        },
      );
    } finally {
      isCheckingConnection.value = false;
    }
  }

  // Helper function to save and close
  Future<void> _confirmAndSave(String url) async {
    if (Get.isRegistered<StorageService>()) {
      await Get.find<StorageService>().saveBaseUrl(url);
    }
    serverUrlController.text = url;
    _apiProvider.setBaseUrl(url); // Ensure provider is updated
    Get.back(); // Close the BottomSheet
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
          GlobalSnackbar.error(title: 'Login Failed', message: response.data?['message'] ?? 'Invalid credentials.');
        } else {
          GlobalSnackbar.error(title: 'Login Error', message: response.data?['message'] ?? 'An unknown error occurred.');
        }
      } catch (e) {
        GlobalSnackbar.error(title: 'Login Error', message: 'An unexpected error occurred.');
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