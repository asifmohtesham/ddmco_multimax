import 'package:ddmco_multimax/app/data/models/user_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
// User model might not be directly populated from Frappe's login response,
// but you might have a simplified one or fetch details later.
import 'package:ddmco_multimax/app/data/models/user_model.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
// Import AuthenticationController to process login
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';
// AppRoutes is not needed here anymore as AuthController handles navigation after login

class LoginController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  // Get the global AuthenticationController instance
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

    // Frappe doesn't strictly require email format for 'usr' if it's a username
    // You can keep GetUtils.isEmail if you only want to allow email login.
    if (!GetUtils.isEmail(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    // You can add length validation if desired, but Frappe controls its own password policy
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
        // --- Frappe Specific Login Call ---
        final response = await _apiProvider.loginWithFrappe(
          emailController.text.trim(), // This will be 'usr'
          passwordController.text.trim(), // This will be 'pwd'
        );

        // Frappe login success typically returns 200 and a message "Logged In"
        // Cookies (sid, user_id, full_name) are set by the server and handled by CookieJar.
        if (response.statusCode == 200 && response.data?['message'] == "Logged In") {
          // Extract user details from the response or cookies.
          // Frappe's login response includes 'full_name'.
          // 'user_id' and 'user_image' are often available in cookies or via /api/method/frappe.auth.get_logged_user

          final String fullName = response.data?['full_name'] ?? "User";
          // The 'email' (username used for login) is already in emailController.text
          // The 'id' (user_id from cookie) can be fetched or might not be immediately needed
          // for the client-side User model if the session is cookie-based.

          // Create a User object. You might need to make another call to get more user details
          // or parse them from cookies if your ApiProvider and CookieJar setup allows.
          // For simplicity, we'll create a basic User object here.
          final user = User(
            id: emailController.text.trim(), // Or fetch user_id if critical for your User model
            name: fullName,
            email: emailController.text.trim(), // This was the 'usr'
            // token: null, // Frappe primarily uses session cookies
          );

          // Delegate to AuthenticationController to handle successful login
          _authController.processSuccessfulLogin(user);

        } else if (response.statusCode == 401 || response.statusCode == 403) {
          Get.snackbar(
            'Login Failed',
            response.data?['message'] ?? response.data?['exc_type'] ?? // Frappe might send 'exc_type' for auth errors
                'Invalid credentials.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        } else {
          // Handle other potential error responses from Frappe or network issues
          Get.snackbar(
            'Login Error',
            response.data?['message'] ?? 'An unknown error occurred during login. Status: ${response.statusCode}',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      } on DioException catch (e) {
        // Handle Dio specific errors (network, timeout, etc.)
        String errorMessage = 'An error occurred. Please try again.';
        if (e.response != null && e.response!.data != null && e.response!.data is Map) {
          errorMessage = e.response!.data['message'] ?? e.response!.data['exc_type'] ?? 'Login failed. Please check your connection or credentials.';
        } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.sendTimeout || e.type == DioExceptionType.receiveTimeout) {
          errorMessage = 'Connection timeout. Please check your internet connection.';
        } else if (e.type == DioExceptionType.unknown) {
          errorMessage = 'Network error. Please check your internet connection.';
        }
        printError(info: "Login DioException: ${e.message} - ${e.response?.data}");
        Get.snackbar(
          'Login Error',
          errorMessage,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      } catch (e) {
        printError(info: "Login Error in LoginController: $e");
        Get.snackbar(
          'Login Error',
          'An unexpected error occurred. Please try again.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      } finally {
        isLoading.value = false;
      }
    }
  }
// The logoutUser method is now in AuthenticationController
}
