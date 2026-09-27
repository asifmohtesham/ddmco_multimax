import 'dart:async';
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';
import 'package:multimax/app/data/services/attendance_notify_worker.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_worker.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/reminder_scheduler.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/logout_flow.dart';
import 'package:multimax/app/modules/auth/widgets/logout_dialog.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class AuthenticationController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  UserProvider get _userProvider {
    if (!Get.isRegistered<UserProvider>()) {
      Get.put(UserProvider());
    }
    return Get.find<UserProvider>();
  }

  var currentUser = Rx<User?>(null);
  var isAuthenticated = false.obs;
  var isLoading = false.obs;

  /// True while a logout is in flight; drives [LogoutDialog]'s busy state.
  final isLoggingOut = false.obs;

  /// Why the last logout attempt failed, shown inline in [LogoutDialog].
  final logoutError = RxnString();

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

        // Frappe returns "Guest" when the session has expired. Treat this as
        // unauthenticated — do not proceed with a Guest user or prefetch.
        if (loggedInUserEmail == 'Guest') {
          await _clearSessionAndLocalData();
          return;
        }

        final userDetailsResponse =
            await _apiProvider.getUserDetails(loggedInUserEmail);
        if (userDetailsResponse.statusCode == 200 &&
            userDetailsResponse.data?['data'] != null) {
          var user = User.fromJson(userDetailsResponse.data['data']);

          // --- ROLE FETCHING FIX ---
          // The `roles` table is permlevel 1, so it is empty here unless the
          // user is a System Manager. The endpoint below fills it in on
          // Frappe v15; it was removed in v16, where the roles of other
          // users stay empty and PermissionService asks the server instead.
          if (user.roles.isEmpty) {
            try {
              final rolesResponse =
                  await _userProvider.getUserRoles(user.id);
              if (rolesResponse.statusCode == 200 &&
                  rolesResponse.data['message'] != null) {
                final roleList =
                    List<String>.from(rolesResponse.data['message']);
                if (roleList.isNotEmpty) {
                  user = user.copyWith(roles: roleList);
                }
              }
            } catch (e) {
              print('Failed to fetch roles manually: $e');
            }
          }
          // -------------------------

          // --- LINK EMPLOYEE DOCUMENT ---
          try {
            final empResponse =
                await _userProvider.getEmployeeIdForUser(user.email);
            if (empResponse.statusCode == 200 &&
                empResponse.data['data'] != null) {
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

          if (Get.isRegistered<StorageService>()) {
            await Get.find<StorageService>().saveUser(user);
          }

          // Arm the scheduled digest for the user who just signed in.
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
            unawaited(DigestScheduler().rearm().catchError((_) {}));
          }

          // Arm attendance notifications for the user who just signed in
          // (Android only — iOS cannot check punches at fire time).
          if (!kIsWeb && Platform.isAndroid) {
            unawaited(AttendanceNotifyScheduler().rearm().catchError((_) {}));
          }

          if (Get.isRegistered<PermissionService>()) {
            // Clear before prefetch so stale cache entries from an expired
            // session (e.g. a prior Guest prefetch) cannot block fresh fetches.
            Get.find<PermissionService>().clearCache();
            await Get.find<PermissionService>().prefetchAll(kAppPermissions);
          }

          // Lay the drawer out from this user's Frappe workspaces.
          unawaited(AppNavDrawerController.instance.loadFor(user.email));
        } else {
          await _clearSessionAndLocalData();
        }
      } else {
        await _clearSessionAndLocalData();
      }
    } catch (e) {
      printError(info: 'Failed to fetch user details: $e');
      await _clearSessionAndLocalData();
    }
  }

  Future<void> checkAuthenticationStatus() async {
    isLoading.value = true;
    try {
      bool hasSession = await _apiProvider.hasSessionCookies();
      if (hasSession) {
        if (Get.isRegistered<StorageService>()) {
          final storedUser = Get.find<StorageService>().getUser();
          if (storedUser != null) {
            currentUser.value = storedUser;
            isAuthenticated.value = true;
          }
        }
        await fetchUserDetails();
      } else {
        await _clearSessionAndLocalData();
      }
    } catch (e) {
      printError(info: 'Error checking auth status: $e');
      await _clearSessionAndLocalData();
    } finally {
      isLoading.value = false;
    }
  }

  void processSuccessfulLogin(User user) {
    fetchUserDetails().then((_) {
      Get.offAllNamed(AppRoutes.HOME);
      GlobalSnackbar.success(
        title: 'Login Successful',
        message: 'Welcome back, ${currentUser.value?.name ?? user.name}!',
      );
    });
  }

  /// Confirms, then logs out. The confirmation and the loading feedback are
  /// one [LogoutDialog] driven by [isLoggingOut] — never a second route.
  Future<void> logoutUser() async {
    if (isLoggingOut.value) return;
    logoutError.value = null;
    Get.dialog(
      LogoutDialog(
        busy: isLoggingOut,
        error: logoutError,
        email: currentUser.value?.email,
        onConfirm: _performLogout,
      ),
    );
  }

  Future<void> _performLogout() async {
    if (isLoggingOut.value) return;
    isLoggingOut.value = true;
    logoutError.value = null;
    final cancelToken = CancelToken();
    try {
      final outcome = await localFirstLogout(
        serverLogout: () =>
            _apiProvider.logoutApiCall(cancelToken: cancelToken),
        clearLocal: _clearSessionAndLocalData,
        onServerTimeout: () => cancelToken.cancel('logout timed out'),
      );
      Get.offAllNamed(AppRoutes.LOGIN);
      if (outcome == LogoutOutcome.serverConfirmed) {
        GlobalSnackbar.success(message: 'You have been logged out.');
      } else {
        GlobalSnackbar.info(
          message: 'Logged out on this device. '
              "The server couldn't be reached.",
        );
      }
    } catch (e) {
      printError(info: 'Logout failed: $e');
      logoutError.value = "Couldn't clear the saved session. Try again.";
    } finally {
      isLoggingOut.value = false;
    }
  }

  Future<void> _clearSessionAndLocalData() async {
    // Cancel pending digest work and clear any posted digest notification
    // before the user identity disappears from storage.
    if (!kIsWeb && Platform.isAndroid) {
      await cancelDigestOnLogout();
      await cancelAttendanceOnLogout();
    }
    if (!kIsWeb && Platform.isIOS) {
      await cancelIosDigestReminders();
    }
    await _apiProvider.clearSessionCookies();
    if (Get.isRegistered<StorageService>()) {
      await Get.find<StorageService>().clearUserData();
    }
    // Sign out before clearing the cache: clearing notifies every mounted
    // DocTypeGuard, and they must find no session to probe.
    currentUser.value = null;
    isAuthenticated.value = false;
    if (Get.isRegistered<PermissionService>()) {
      Get.find<PermissionService>().clearCache();
    }
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
    return currentUser.value!.roles.any(
        (userRole) => roles.contains(userRole));
  }
}
