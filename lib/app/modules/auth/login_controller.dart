import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
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
    // Length and strength rules belong to the server's password policy.
    if (value == null || value.isEmpty) return 'Please enter your password';
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
          // Sent exactly as typed: spaces can be part of a password.
          passwordController.text,
        );

        final data = response.data;
        if (data is! Map || data['message'] != 'Logged In') {
          GlobalSnackbar.error(
            title: 'Login Failed',
            message: 'The server gave an answer this app does not '
                'understand. Check the server address.',
          );
          return;
        }

        final check = await _authController.fetchUserDetails();
        if (check == SessionCheck.invalid) {
          GlobalSnackbar.error(
            title: 'Login Failed',
            message: 'The server accepted the login but not the session. '
                'Please try again.',
          );
          return;
        }

        // The login itself succeeded. If the profile could not be loaded,
        // carry on with what the login response told us about the user.
        final email = emailController.text.trim();
        final fullName = data['full_name'];
        _authController.processSuccessfulLogin(
          _authController.currentUser.value ??
              User(
                id: email,
                name: fullName is String ? fullName : 'User',
                email: email,
                roles: [],
              ),
        );
        loggedIn = true;
      } on DioException catch (e) {
        // Dio throws for every non-2xx status, so rejected credentials
        // arrive here rather than as a response.
        GlobalSnackbar.error(
          title: 'Login Failed',
          message: _describeLoginFailure(e),
        );
      } catch (e) {
        GlobalSnackbar.error(
          title: 'Login Failed',
          message: 'Something went wrong in the app. Please try again.',
        );
      } finally {
        if (!loggedIn) {
          isLoading.value = false;
          update();
        }
      }
    }
  }

  String _describeLoginFailure(DioException e) {
    final server = _apiProvider.baseUrl;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return "Can't reach $server. Check your connection or the "
            'server address.';
      case DioExceptionType.badCertificate:
        return "The security certificate of $server could not be verified.";
      default:
        break;
    }

    final status = e.response?.statusCode;
    if (status == null) return "Can't reach $server. Please try again.";

    if (status == 401 || status == 403) {
      // Frappe explains the refusal (wrong password, disabled user, ...).
      final body = e.response?.data;
      final reason = body is Map ? body['message'] : null;
      return reason is String && reason.isNotEmpty
          ? reason
          : 'Incorrect email or password.';
    }
    if (status == 404) {
      return 'No ERPNext login was found at $server. Check the server '
          'address.';
    }
    if (status == 429) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    if (status >= 500) {
      return 'The server had a problem ($status). Try again shortly.';
    }
    return 'The server refused the login ($status).';
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
