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

/// Outcome of asking the server whether the stored session is still good.
enum SessionCheck {
  /// The server confirmed the session and the user profile was loaded.
  valid,

  /// The cookie was absent or the server rejected the session.
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

  /// A saved session may still be usable, but Splash has no profile to open.
  final isSessionVerificationPending = false.obs;
  final isCheckingSession = false.obs;

  static const _recheckInterval = Duration(seconds: 30);

  Timer? _recheckTimer;
  Future<void>? _expiryInProgress;

  /// True while a logout is in flight; drives [LogoutDialog]'s busy state.
  final isLoggingOut = false.obs;

  /// Why the last logout attempt failed, shown inline in [LogoutDialog].
  final logoutError = RxnString();

  @override
  void onInit() {
    super.onInit();
    // Splash owns the first check so a slow server does not delay launch.
    _apiProvider.hasActiveSession = () => isAuthenticated.value;
    _apiProvider.onSessionExpired = handleSessionExpired;
  }

  @override
  void onClose() {
    _stopRecheck();
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
      final data = response.data;
      final message = data is Map ? data['message'] : null;
      if (message is! String || message.isEmpty) {
        return SessionCheck.unverified;
      }
      // Frappe returns "Guest" when the session has expired. Treat this as
      // unauthenticated — do not proceed with a Guest user or prefetch.
      if (message == 'Guest') {
        await _invalidateSession();
        return SessionCheck.invalid;
      }
      loggedInUserEmail = message;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await _invalidateSession();
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

      // The `roles` table is permlevel 1, so the document above carries it
      // only for a System Manager. Everyone else is filled in here.
      if (user.roles.isEmpty) {
        final roles = await _rolesOf(user.id);
        if (roles.isNotEmpty) user = user.copyWith(roles: roles);
      }

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

      if (Get.isRegistered<StorageService>()) {
        await Get.find<StorageService>().saveUser(user);
      }

      currentUser.value = user;
      isAuthenticated.value = true;

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
      unawaited(AppNavDrawerController.instance.loadFor(user.id));
      return SessionCheck.valid;
    } catch (e) {
      printError(info: 'Failed to fetch user details: $e');
      return SessionCheck.unverified;
    }
  }

  /// The roles of [userId] when the User document did not carry them.
  ///
  /// Frappe v15 answers `get_roles`; v16 removed it, and there the roles are
  /// read from Desk's boot data. If neither answers (offline, a server
  /// hiccup) the roles already known for this same user are kept, so a
  /// refresh never strips role-dependent features from a signed-in user.
  /// Empty when nothing is known: [PermissionService] then asks the server
  /// per permission instead.
  Future<List<String>> _rolesOf(String userId) async {
    try {
      final response = await _userProvider.getUserRoles(userId);
      final message = response.statusCode == 200 ? response.data['message'] : null;
      if (message is List && message.isNotEmpty) {
        return List<String>.from(message);
      }
    } catch (_) {
      // Not available on this server (v16) or not reachable: try Desk.
    }
    try {
      final roles = await _userProvider.getRolesFromDesk(userId);
      if (roles.isNotEmpty) return roles;
    } catch (e) {
      printError(info: 'Could not read roles from Desk: $e');
    }
    final known = currentUser.value;
    return known != null && known.id == userId ? known.roles : const [];
  }

  Future<void> checkAuthenticationStatus() async {
    if (isCheckingSession.value || isClosed) return;
    isCheckingSession.value = true;
    _stopRecheck();
    var result = SessionCheck.unverified;
    try {
      result = await _checkStoredSession();
    } catch (e) {
      printError(info: 'Could not check saved session: ${e.runtimeType}');
    } finally {
      final unverified = result == SessionCheck.unverified;
      isSessionVerificationPending.value = unverified && !isAuthenticated.value;
      if (unverified && !isClosed) {
        _recheckTimer = Timer(_recheckInterval, _recheck);
      }
      isCheckingSession.value = false;
    }
  }

  Future<SessionCheck> _checkStoredSession() async {
    bool? hasSession;
    try {
      hasSession = await _apiProvider.hasSessionCookies();
    } catch (e) {
      printError(info: 'Could not read session cookies: ${e.runtimeType}');
    }
    if (hasSession == false) {
      await _invalidateSession();
      return SessionCheck.invalid;
    }

    await _restoreCachedUser();
    // An unreadable jar cannot establish whether the cookie would be sent.
    if (hasSession == null) return SessionCheck.unverified;
    return fetchUserDetails();
  }

  Future<void> _restoreCachedUser() async {
    if (isAuthenticated.value || !Get.isRegistered<StorageService>()) return;
    final storage = Get.find<StorageService>();
    try {
      final user = storage.getUser();
      if (user != null) {
        currentUser.value = user;
        isAuthenticated.value = true;
      }
    } catch (e) {
      printError(info: 'Could not read cached profile: ${e.runtimeType}');
      try {
        await storage.clearCachedUser();
      } catch (error) {
        printError(info: 'Could not remove cached profile: ${error.runtimeType}');
      }
    }
  }

  /// Stops the scheduled check when the user chooses to enter credentials.
  void stopStartupRecheck() => _stopRecheck();

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
    await _invalidateSession();
    _showLoginAfterExpiry();
  }

  Future<void> _invalidateSession() async {
    try {
      await _clearSessionAndLocalData();
    } catch (e) {
      printError(info: 'Could not clear saved session: ${e.runtimeType}');
      _forgetSession();
    }
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

  void _stopRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = null;
  }

  Future<void> _recheck() async {
    final wasSignedIn = isAuthenticated.value;
    await checkAuthenticationStatus();
    if (wasSignedIn &&
        !isAuthenticated.value &&
        !isSessionVerificationPending.value) {
      _showLoginAfterExpiry();
    }
  }

  /// Opens the app for [user] after the server accepted their credentials.
  /// The caller has already run [fetchUserDetails]; it is not repeated here.
  void processSuccessfulLogin(User user) {
    _stopRecheck();
    isSessionVerificationPending.value = false;
    currentUser.value ??= user;
    isAuthenticated.value = true;
    Get.offAllNamed(AppRoutes.HOME);
    GlobalSnackbar.success(
      title: 'Login Successful',
      message: 'Welcome back, ${currentUser.value?.name ?? user.name}!',
    );
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
        onConfirm: performLogout,
      ),
    );
  }

  /// Signs out on this device whether or not the server can be told.
  ///
  /// The server call is best effort: on a shared handheld the account must
  /// never stay open just because WiFi dropped.
  Future<void> performLogout() async {
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
    try {
      await _apiProvider.clearSessionCookies();
    } finally {
      if (Get.isRegistered<StorageService>()) {
        await Get.find<StorageService>().clearUserData();
      }
    }
    _forgetSession();
  }

  void _forgetSession() {
    // Sign out before clearing the cache: clearing notifies every mounted
    // DocTypeGuard, and they must find no session to probe.
    currentUser.value = null;
    isAuthenticated.value = false;
    if (Get.isRegistered<AppNavDrawerController>()) {
      Get.find<AppNavDrawerController>().clearSession();
    }
    if (Get.isRegistered<PermissionService>()) {
      Get.find<PermissionService>().clearCache();
    }
  }
}
