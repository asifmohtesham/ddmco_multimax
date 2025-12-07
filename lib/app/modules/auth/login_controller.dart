import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/user_model.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';

class LoginController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final AuthenticationController _authController = Get.find<AuthenticationController>();

  final GlobalKey<FormState> loginFormKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  var isLoading = false.obs;
  var isPasswordHidden = true.obs;

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    // Frappe username login might not be an email, so we allow non-email strings too if needed.
    // Keeping simple empty check is often safer for generic usernames.
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

          // 1. Fetch full details (including Roles) before proceeding
          await _authController.fetchUserDetails();

          if (_authController.currentUser.value != null) {
            // 2. Use the fully fetched user (with roles)
            _authController.processSuccessfulLogin(_authController.currentUser.value!);
          } else {
            // 3. Fallback: Create basic user with empty roles to satisfy compiler and allow entry
            // (RoleGuards will simply block restricted areas)
            final String fullName = response.data?['full_name'] ?? "User";
            final user = User(
              id: emailController.text.trim(),
              name: fullName,
              email: emailController.text.trim(),
              roles: [], // Empty roles list
            );
            _authController.processSuccessfulLogin(user);
          }

        } else if (response.statusCode == 401 || response.statusCode == 403) {
          Get.snackbar(
            'Login Failed',
            response.data?['message'] ?? 'Invalid credentials.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        } else {
          Get.snackbar(
            'Login Error',
            response.data?['message'] ?? 'An unknown error occurred.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      } on DioException catch (e) {
        String errorMessage = 'An error occurred. Please try again.';
        if (e.response != null && e.response!.data != null && e.response!.data is Map) {
          errorMessage = e.response!.data['message'] ?? 'Login failed.';
        } else if (e.type == DioExceptionType.connectionTimeout) {
          errorMessage = 'Connection timeout.';
        }
        Get.snackbar(
          'Login Error',
          errorMessage,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      } catch (e) {
        Get.snackbar(
          'Login Error',
          'An unexpected error occurred.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      } finally {
        isLoading.value = false;
      }
    }
  }
}