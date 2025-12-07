import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/models/user_model.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/data/services/storage_service.dart';

class AuthenticationController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  var currentUser = Rx<User?>(null);
  var isAuthenticated = false.obs;
  var isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
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
        } else {
          await _clearSessionAndLocalData();
        }
      } else {
        await _clearSessionAndLocalData();
      }
    } catch (e) {
      printError(info: "Failed to fetch user details: $e");
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
        await _clearSessionAndLocalData();
      }
    } catch (e) {
      printError(info: "Error checking auth status: $e");
      await _clearSessionAndLocalData();
    } finally {
      isLoading.value = false;
    }
  }

  void processSuccessfulLogin(User user) {
    currentUser.value = user;
    isAuthenticated.value = true;
    Get.offAllNamed(AppRoutes.HOME);
    Get.snackbar(
      'Login Successful',
      'Welcome back, ${user.name}!',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

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
              Get.back();
              isLoading.value = true;
              try {
                await _apiProvider.logoutApiCall();
                await _clearSessionAndLocalData();
                Get.offAllNamed(AppRoutes.LOGIN);
              } catch (e) {
                Get.snackbar('Logout Error', 'Could not log out.');
              } finally {
                isLoading.value = false;
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _clearSessionAndLocalData() async {
    await _apiProvider.clearSessionCookies();
    if (Get.isRegistered<StorageService>()) {
      await Get.find<StorageService>().clearUserData();
    }
    currentUser.value = null;
    isAuthenticated.value = false;
  }

  // --- PERMISSION HELPERS ---

  /// Returns true if the user has specific role
  bool hasRole(String role) {
    if (currentUser.value == null) return false;
    // System Manager usually has all permissions
    if (currentUser.value!.roles.contains('System Manager')) return true;
    return currentUser.value!.roles.contains(role);
  }

  /// Returns true if the user has ANY of the provided roles
  bool hasAnyRole(List<String> roles) {
    if (currentUser.value == null) return false;
    if (currentUser.value!.roles.contains('System Manager')) return true;
    return currentUser.value!.roles.any((userRole) => roles.contains(userRole));
  }
}