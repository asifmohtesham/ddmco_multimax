import 'dart:async';
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/core/utils/app_navigator.dart';
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
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Outcome of asking the server whether the stored session is still good.
enum SessionCheck {
  /// The server confirmed the session and the user profile was loaded.
  valid,

  /// The server said there is no session. Local session data was cleared.
  invalid,

  /// The server could not be asked, or did not give a usable answer.
  /// Nothing was cleared.
  unverified,
}

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

  static const _recheckInterval = Duration(seconds: 30);
  static const _serverLogoutTimeout = Duration(seconds: 5);

  Timer? _recheckTimer;
  bool _recheckRunning = false;
  Future<void>? _expiryInProgress;

  @override
  void onInit() {
    super.onInit();
    // The startup check is awaited by main() before runApp, so it is not
    // started again here.
    _apiProvider.hasActiveSession = () => isAuthenticated.value;
    _apiProvider.onSessionExpired = handleSessionExpired;
  }

  @override
  void onClose() {
    _recheckTimer?.cancel();
    super.onClose();
  }

  /// Asks the server who is logged in and loads that user's profile.
  ///
  /// Only a definitive answer from the server ends the session: Frappe
  /// reporting "Guest", or a 401/403 on the identity check. Timeouts,
  /// connection errors and 5xx responses leave cookies and cached data
  /// untouched and return [SessionCheck.unverified].
  Future<SessionCheck> fetchUserDetails() async {
    final String loggedInUserEmail;
    try {
      final response = await _apiProvider.getLoggedUser();
      final message = response.data?['message'];
      if (message is! String || message.isEmpty) {
        return SessionCheck.unverified;
      }
      // Frappe returns "Guest" when the session has expired. Treat this as
      // unauthenticated — do not proceed with a Guest user or prefetch.
      if (message == 'Guest') {
        await _clearSessionAndLocalData();
        return SessionCheck.invalid;
      }
      loggedInUserEmail = message;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await _clearSessionAndLocalData();
        return SessionCheck.invalid;
      }
      printError(info: 'Could not verify session: ${e.type.name}');
      return SessionCheck.unverified;
    } catch (e) {
      printError(info: 'Could not verify session: $e');
      return SessionCheck.unverified;
    }

    // From here on the server has confirmed the session, so a failure to
    // load the profile must never end it.
    try {
      final userDetailsResponse =
          await _apiProvider.getUserDetails(loggedInUserEmail);
      if (userDetailsResponse.statusCode != 200 ||
          userDetailsResponse.data?['data'] == null) {
        return SessionCheck.unverified;
      }
      var user = User.fromJson(userDetailsResponse.data['data']);

      // --- ROLE FETCHING FIX ---
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
      return SessionCheck.valid;
    } catch (e) {
      printError(info: 'Failed to fetch user details: $e');
      return SessionCheck.unverified;
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
        // Offline policy: a session the server could not confirm stays
        // signed in only when a cached user exists. Either way the cookie
        // is kept, and the check repeats until the server answers.
        final result = await fetchUserDetails();
        if (result == SessionCheck.unverified && isAuthenticated.value) {
          _startRecheck();
        }
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

  /// Re-checks the session while the app is in use. Unlike
  /// [fetchUserDetails], a rejected session also sends the user to login.
  Future<SessionCheck> revalidateSession() async {
    final wasSignedIn = isAuthenticated.value;
    final result = await fetchUserDetails();
    if (result == SessionCheck.invalid && wasSignedIn) {
      _showLoginAfterExpiry();
    }
    return result;
  }

  /// Ends a session the server no longer accepts and returns to login.
  /// Safe to call from many failing requests at once: it runs once.
  Future<void> handleSessionExpired() {
    if (!isAuthenticated.value) return Future.value();
    return _expiryInProgress ??= _endExpiredSession()
        .whenComplete(() => _expiryInProgress = null);
  }

  Future<void> _endExpiredSession() async {
    await _clearSessionAndLocalData();
    _showLoginAfterExpiry();
  }

  void _showLoginAfterExpiry() {
    if (Get.currentRoute != AppRoutes.LOGIN) {
      Get.offAllNamed(AppRoutes.LOGIN);
    }
    GlobalSnackbar.warning(
      title: 'Session expired',
      message: 'Please log in again.',
    );
  }

  void _startRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer.periodic(_recheckInterval, (_) => _recheck());
  }

  void _stopRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = null;
  }

  Future<void> _recheck() async {
    if (_recheckRunning) return;
    _recheckRunning = true;
    try {
      final result = await revalidateSession();
      if (result != SessionCheck.unverified) _stopRecheck();
    } finally {
      _recheckRunning = false;
    }
  }

  /// Signs out on this device whether or not the server can be told.
  ///
  /// The server call is best effort: on a shared handheld the account must
  /// never stay open just because WiFi dropped.
  Future<void> performLogout() async {
    _stopRecheck();
    try {
      await _apiProvider.logoutApiCall().timeout(_serverLogoutTimeout);
    } catch (e) {
      printError(info: 'Server logout failed, signing out locally: $e');
    }
    await _clearSessionAndLocalData();
    Get.offAllNamed(AppRoutes.LOGIN);
  }

  /// Opens the app for [user] after the server accepted their credentials.
  /// The caller has already run [fetchUserDetails]; it is not repeated here.
  void processSuccessfulLogin(User user) {
    currentUser.value ??= user;
    isAuthenticated.value = true;
    Get.offAllNamed(AppRoutes.HOME);
    GlobalSnackbar.success(
      title: 'Login Successful',
      message: 'Welcome back, ${currentUser.value?.name ?? user.name}!',
    );
  }

  /// Asks the user to confirm, then signs out behind a loading overlay.
  Future<void> logoutUser() async {
    // Builder provides a valid local BuildContext so button callbacks
    // use Navigator.of(context).pop() instead of Get.back().
    Get.dialog(
      Builder(
        builder: (context) => AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              child: const Text('Logout'),
              onPressed: () {
                Navigator.of(context).pop();
                _logoutBehindOverlay();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logoutBehindOverlay() async {
    isLoading.value = true;
    Get.dialog(
      const PopScope(
        canPop: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Logging out…',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
      barrierColor: Colors.black54,
    );
    // Navigating to login replaces every route, overlay included.
    await performLogout();
    isLoading.value = false;
  }

  Future<void> _clearSessionAndLocalData() async {
    _stopRecheck();
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
    if (Get.isRegistered<PermissionService>()) {
      Get.find<PermissionService>().clearCache();
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
    return currentUser.value!.roles.any(
        (userRole) => roles.contains(userRole));
  }
}
