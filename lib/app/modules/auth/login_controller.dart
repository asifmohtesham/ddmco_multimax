import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_navigator.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/auth/connect/connect_to_instance_controller.dart';
import 'package:multimax/app/modules/auth/connect/connect_to_instance_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class LoginController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final AuthenticationController _authController =
      Get.find<AuthenticationController>();
  final DatabaseService _dbService = Get.find<DatabaseService>();

  final GlobalKey<FormState> loginFormKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  var isLoading = false.obs;
  var showServerGuide = false.obs;

  final isPasswordHidden = ValueNotifier<bool>(true);

  // ── Connect-sheet lifecycle ───────────────────────────────────────────────

  void openConnectSheet(BuildContext context) {
    Get.put(ConnectToInstanceController());
    showConnectToInstanceSheet(context).then((_) async {
      // The sheet's dismiss animation is still running when its Future resolves.
      // Delaying Get.delete lets the animation finish so no widget tries
      // to call Get.find<ConnectToInstanceController>() after deletion.
      await Future.delayed(const Duration(milliseconds: 350));
      Get.delete<ConnectToInstanceController>(force: true);
      final savedUrl =
          await _dbService.getConfig(DatabaseService.serverUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        showServerGuide.value = false;
        update();
      }
    });
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    isPasswordHidden.dispose();
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

  void togglePasswordVisibility() =>
      isPasswordHidden.value = !isPasswordHidden.value;

  Future<void> loginUser() async {
    final storedUrl =
        await _dbService.getConfig(DatabaseService.serverUrlKey);

    if (storedUrl == null || storedUrl.isEmpty) {
      showServerGuide.value = true;
      update();
      AppNotification.warning(
        'Please set the Server URL using the settings icon above before logging in.',
      );
      return;
    }

    if (loginFormKey.currentState!.validate()) {
      isLoading.value = true;
      update();
      bool loggedIn = false;
      try {
        final response = await _apiProvider.loginWithFrappe(
          emailController.text.trim(),
          passwordController.text.trim(),
        );

        if (response.statusCode == 200 &&
            response.data?['message'] == 'Logged In') {
          await _authController.fetchUserDetails();
          if (_authController.currentUser.value != null) {
            _authController.processSuccessfulLogin(
                _authController.currentUser.value!);
          } else {
            final String fullName =
                response.data?['full_name'] ?? 'User';
            final user = User(
              id: emailController.text.trim(),
              name: fullName,
              email: emailController.text.trim(),
              roles: [],
            );
            _authController.processSuccessfulLogin(user);
          }
          loggedIn = true;
        } else if (response.statusCode == 401 ||
            response.statusCode == 403) {
          GlobalSnackbar.error(
            title: 'Login Failed',
            message:
                response.data?['message'] ?? 'Invalid credentials.',
          );
        } else {
          GlobalSnackbar.error(
            title: 'Login Error',
            message: response.data?['message'] ??
                'An unknown error occurred.',
          );
        }
      } catch (e) {
        GlobalSnackbar.error(
          title: 'Login Error',
          message: 'An unexpected error occurred.',
        );
      } finally {
        if (!loggedIn) {
          isLoading.value = false;
          update();
        }
      }
    }
  }

  Future<void> resetPassword() async {
    if (emailController.text.isEmpty) {
      GlobalSnackbar.error(
          message: 'Please enter your email address first');
      return;
    }
    isLoading.value = true;
    update();
    try {
      final response =
          await _apiProvider.resetPassword(emailController.text.trim());
      if (response.statusCode == 200) {
        AppNavigator.pop();
        GlobalSnackbar.success(
            message: 'Password reset instructions sent to your email');
      } else {
        GlobalSnackbar.error(message: 'Failed to send reset link');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Reset failed: $e');
    } finally {
      isLoading.value = false;
      update();
    }
  }
}
