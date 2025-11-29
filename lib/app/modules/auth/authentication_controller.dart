import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart'; // For UI elements like AlertDialog, SnackBar
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/models/user_model.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
// Optional: If you use a storage service for user data persistence
import 'package:ddmco_multimax/app/data/services/storage_service.dart';

class AuthenticationController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  // Optional: final StorageService _storageService = Get.find<StorageService>();

  // Observable for the current user. Null if no user is logged in.
  var currentUser = Rx<User?>(null);
  // Observable for the authentication status.
  var isAuthenticated = false.obs;
  // Observable for loading state during auth operations (e.g., checking session)
  var isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    // Automatically check authentication status when the controller is initialized.
    // This is useful for when the app starts.
    checkAuthenticationStatus();
  }

  Future<void> fetchUserDetails() async {
    try {
      final response = await _apiProvider.getLoggedUser();
      if (response.statusCode == 200 && response.data?['message'] != null) {
        final loggedInUserEmail = response.data['message'];

        final userDetailsResponse = await _apiProvider.getUserDetails(loggedInUserEmail);
        if (userDetailsResponse.statusCode == 200 && userDetailsResponse.data?['data'] != null) {
          final user = User.fromJson(userDetailsResponse.data['data']);
          currentUser.value = user;
          isAuthenticated.value = true;
          printInfo(info: "User details loaded: ${user.name}");
        } else {
          await _clearSessionAndLocalData();
        }
      } else {
        await _clearSessionAndLocalData();
      }
    } catch (e) {
      printError(info: "Failed to fetch or process logged user details: $e");
      await _clearSessionAndLocalData();
    }
  }

  Future<void> checkAuthenticationStatus() async {
    isLoading.value = true;
    try {
      bool hasSession = await _apiProvider.hasSessionCookies();
      if (hasSession) {
        await fetchUserDetails();
      } else {
        printInfo(info: "No active session found.");
        await _clearSessionAndLocalData();
      }
    } catch (e) { // Catch errors from hasSessionCookies or other initial problems
      printError(info: "Error checking authentication status: $e");
      await _clearSessionAndLocalData(); // Ensure clean state on error
    } finally {
      isLoading.value = false;
    }
  }

  /// Handles successful login.
  /// Sets the current user and updates authentication status.
  void processSuccessfulLogin(User user) {
    currentUser.value = user;
    isAuthenticated.value = true;
    // Optional: Save user to local storage for persistence across app restarts
    // if (Get.isRegistered<StorageService>()) {
    //   Get.find<StorageService>().saveUser(user);
    // }
    Get.offAllNamed(AppRoutes.HOME); // Navigate to Home
    Get.snackbar(
      'Login Successful',
      'Welcome back, ${user.name}!',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  /// Handles the logout process.
  Future<void> logoutUser() async {
    Get.dialog(
      AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Get.back(),
          ),
          TextButton(
            child: const Text('Logout'),
            onPressed: () async {
              Get.back(); // Dismiss confirmation dialog

              isLoading.value = true;

              try {
                await _apiProvider.logoutApiCall();

                await _clearSessionAndLocalData();

                Get.offAllNamed(AppRoutes.LOGIN);
                Get.snackbar(
                  'Logged Out',
                  'You have been successfully logged out.',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
              } catch (e) {
                printError(info: "Logout failed: $e");
                Get.snackbar(
                  'Logout Error',
                  'Could not log out. Please try again.',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              } finally {
                isLoading.value = false;
                if (Get.isDialogOpen ?? false) {
                  Get.back(); // Dismiss any stray loading dialog
                }
              }
            },
          ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  /// Private helper to clear session cookies and local user data.
  Future<void> _clearSessionAndLocalData() async {
    await _apiProvider.clearSessionCookies();
    // Optional: Clear from local storage
    if (Get.isRegistered<StorageService>()) {
      await Get.find<StorageService>().clearUserData();
    }
    currentUser.value = null;
    isAuthenticated.value = false;
  }
}
