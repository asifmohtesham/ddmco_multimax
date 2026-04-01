import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_navigator.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class LoginController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final AuthenticationController _authController =
      Get.find<AuthenticationController>();
  final DatabaseService _dbService = Get.find<DatabaseService>();

  final GlobalKey<FormState> loginFormKey = GlobalKey<FormState>();
  final TextEditingController emailController    = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController serverUrlController = TextEditingController();

  // ---------------------------------------------------------------------------
  // Server-history search
  // ---------------------------------------------------------------------------

  /// Full list of historically-connected server URLs (most-recent first).
  final savedServerUrls = <String>[].obs;

  /// Subset of [savedServerUrls] matching the current [searchController] text.
  final filteredServerUrls = <String>[].obs;

  /// Search / filter field inside the server-config sheet.
  final TextEditingController searchController = TextEditingController();

  // ---------------------------------------------------------------------------
  // Other observables
  // ---------------------------------------------------------------------------

  var currentServerUrl    = ''.obs;
  var isCheckingConnection = false.obs;
  var isLoading           = false.obs;
  var isPasswordHidden    = true.obs;
  var showServerGuide     = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadSavedServerUrl();
    searchController.addListener(_filterServerUrls);
  }

  // ---------------------------------------------------------------------------
  // Server URL helpers
  // ---------------------------------------------------------------------------

  Future<void> _loadSavedServerUrl() async {
    // Load the currently-active URL
    final savedUrl = await _dbService.getConfig(DatabaseService.serverUrlKey);
    final targetUrl = savedUrl ?? ApiProvider.defaultBaseUrl;
    serverUrlController.text = targetUrl;
    currentServerUrl.value   = targetUrl;
    _apiProvider.setBaseUrl(targetUrl);

    // Load full history list
    await refreshServerHistory();
  }

  /// Reloads [savedServerUrls] from DB and resets the filter.
  Future<void> refreshServerHistory() async {
    final urls = await _dbService.getServerUrls();
    savedServerUrls.assignAll(urls);
    _filterServerUrls();
  }

  /// Called by the search field listener — keeps [filteredServerUrls] in sync.
  void _filterServerUrls() {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      filteredServerUrls.assignAll(savedServerUrls);
    } else {
      filteredServerUrls.assignAll(
        savedServerUrls.where((u) => u.toLowerCase().contains(query)),
      );
    }
  }

  /// Fills [serverUrlController] with [url] and clears the search field.
  void selectSavedUrl(String url) {
    serverUrlController.text = url;
    searchController.clear();
  }

  /// Removes [url] from history (both DB and observable lists).
  Future<void> deleteSavedUrl(String url) async {
    await _dbService.removeServerUrl(url);
    savedServerUrls.remove(url);
    _filterServerUrls();
  }

  // ---------------------------------------------------------------------------
  // Connect / save
  // ---------------------------------------------------------------------------

  Future<void> saveServerConfiguration() async {
    String url = serverUrlController.text.trim();
    if (url.isEmpty) {
      GlobalSnackbar.error(message: 'Server URL cannot be empty');
      return;
    }

    if (!url.startsWith('http')) url = 'https://$url';
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);

    isCheckingConnection.value = true;
    try {
      _apiProvider.setBaseUrl(url);
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 5);
      final response = await dio.get('$url/api/method/ping');

      if (response.statusCode == 200) {
        await _confirmAndSave(url);
        GlobalSnackbar.success(
            title: 'Connected', message: 'Successfully connected to $url');
        showServerGuide.value = false;
      } else {
        throw Exception(
            'Invalid response from server (Status: ${response.statusCode})');
      }
    } catch (e) {
      isCheckingConnection.value = false;
      Get.dialog(
        Builder(
          builder: (context) => AlertDialog(
            title: const Text('Connection Failed'),
            content: Text(
              'Could not verify connection to the server.\n\n'
              'Error: $e\n\n'
              'Do you want to save this URL anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _confirmAndSave(url);
                  GlobalSnackbar.success(
                      title: 'Saved',
                      message: 'Server URL saved (Validation skipped)');
                  showServerGuide.value = false;
                },
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        ),
      );
    } finally {
      isCheckingConnection.value = false;
    }
  }

  /// Persists the validated URL as the active URL **and** appends it to history,
  /// then closes any open overlay.
  Future<void> _confirmAndSave(String url) async {
    // Save as the active server URL
    await _dbService.saveConfig(DatabaseService.serverUrlKey, url);
    // Push into the searchable history list
    await _pushToServerHistory(url);
    serverUrlController.text = url;
    currentServerUrl.value   = url;
    _apiProvider.setBaseUrl(url);
    AppNavigator.pop();
  }

  /// Appends [url] to the persistent server-URL history and refreshes the
  /// in-memory observable list.
  Future<void> _pushToServerHistory(String url) async {
    await _dbService.saveServerUrl(url);
    await refreshServerHistory();
  }

  // ---------------------------------------------------------------------------
  // Auth helpers
  // ---------------------------------------------------------------------------

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    serverUrlController.dispose();
    searchController.dispose();
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
      AppNotification.warning(
        'Please set the Server URL using the settings icon above before logging in.',
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

        if (response.statusCode == 200 &&
            response.data?['message'] == 'Logged In') {
          await _authController.fetchUserDetails();
          if (_authController.currentUser.value != null) {
            _authController
                .processSuccessfulLogin(_authController.currentUser.value!);
          } else {
            final String fullName = response.data?['full_name'] ?? 'User';
            final user = User(
              id: emailController.text.trim(),
              name: fullName,
              email: emailController.text.trim(),
              roles: [],
            );
            _authController.processSuccessfulLogin(user);
          }
        } else if (response.statusCode == 401 ||
            response.statusCode == 403) {
          GlobalSnackbar.error(
              title: 'Login Failed',
              message:
                  response.data?['message'] ?? 'Invalid credentials.');
        } else {
          GlobalSnackbar.error(
              title: 'Login Error',
              message: response.data?['message'] ??
                  'An unknown error occurred.');
        }
      } catch (e) {
        GlobalSnackbar.error(
            title: 'Login Error',
            message: 'An unexpected error occurred.');
      } finally {
        isLoading.value = false;
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
    }
  }
}
