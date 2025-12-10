import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart'; // Added
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class AuthenticationController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  // UserProvider might not be registered yet if AuthBinding only puts AuthController
  // So we lazy load it or use Get.put/find safely.
  // Ideally UserProvider should be put in initial binding or main.dart, but here we can just ensure it exists.
  UserProvider get _userProvider {
    if (!Get.isRegistered<UserProvider>()) {
      Get.put(UserProvider());
    }
    return Get.find<UserProvider>();
  }

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
          var user = User.fromJson(userDetailsResponse.data['data']);

          // --- LINK EMPLOYEE DOCUMENT ---
          try {
            final empResponse = await _userProvider.getEmployeeIdForUser(user.email);
            if (empResponse.statusCode == 200 && empResponse.data['data'] != null) {
              final list = empResponse.data['data'] as List;
              if (list.isNotEmpty) {
                final empId = list[0]['name'];
                user = user.copyWith(employeeId: empId);
              }
            }
          } catch (e) {
            print('Could not link Employee record: $e');
          }
          // -----------------------------

          currentUser.value = user;
          isAuthenticated.value = true;

          // Persist user with employee_id to storage
          if (Get.isRegistered<StorageService>()) {
            await Get.find<StorageService>().saveUser(user);
          }

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
        // Try loading from storage first for speed
        if (Get.isRegistered<StorageService>()) {
          final storedUser = Get.find<StorageService>().getUser();
          if (storedUser != null) {
            currentUser.value = storedUser;
            isAuthenticated.value = true;
          }
        }
        // Always refresh from API
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
    // This is usually called from LoginController with basic info
    // Trigger full fetch to get roles and employee link
    fetchUserDetails().then((_) {
      Get.offAllNamed(AppRoutes.HOME);
      GlobalSnackbar.success(
        title: 'Login Successful',
        message: 'Welcome back, ${currentUser.value?.name ?? user.name}!',
      );
    });
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
                GlobalSnackbar.error(title: 'Logout Error', message: 'Could not log out.');
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

  bool hasRole(String role) {
    if (currentUser.value == null) return false;
    if (currentUser.value!.roles.contains('System Manager')) return true;
    return currentUser.value!.roles.contains(role);
  }

  bool hasAnyRole(List<String> roles) {
    if (currentUser.value == null) return false;
    if (currentUser.value!.roles.contains('System Manager')) return true;
    return currentUser.value!.roles.any((userRole) => roles.contains(userRole));
  }
}