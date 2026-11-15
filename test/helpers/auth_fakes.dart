// test/helpers/auth_fakes.dart
//
// In-memory stand-ins for the services AuthenticationController talks to.
// They `implement` rather than `extend` the real classes so no platform
// plugin (path_provider, get_storage) is touched in a headless test run.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';

const kTestEmail = 'picker@example.com';

/// A Frappe `User` document as returned by `/api/resource/User/<email>`.
Map<String, dynamic> userDocument() => {
      'data': {
        'name': kTestEmail,
        'full_name': 'Pat Picker',
        'email': kTestEmail,
        'user_image': null,
        'designation': null,
        'department': null,
        'mobile_no': '+971501234567',
        'roles': [
          {'role': 'Stock User'},
        ],
      },
    };

User cachedUser() => User(
      id: kTestEmail,
      name: 'Pat Picker',
      email: kTestEmail,
      employeeId: 'HR-EMP-00013',
      roles: ['Stock User'],
    );

Response<dynamic> jsonResponse(dynamic data, {int status = 200}) => Response(
      requestOptions: RequestOptions(path: '/'),
      statusCode: status,
      data: data,
    );

DioException httpError(int status, {dynamic data}) {
  final options = RequestOptions(path: '/');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: data),
  );
}

DioException networkError(
        [DioExceptionType type = DioExceptionType.connectionTimeout]) =>
    DioException(requestOptions: RequestOptions(path: '/'), type: type);

class FakeApiProvider extends Fake implements ApiProvider {
  bool hasCookies = true;
  int clearCookieCalls = 0;
  int logoutCalls = 0;
  int identityChecks = 0;

  /// Doctypes whose read permission was asked of the server, in order.
  final List<String> permissionChecks = [];

  Future<Response> Function() onGetLoggedUser =
      () async => jsonResponse({'message': kTestEmail});
  Future<Response> Function(String email) onGetUserDetails =
      (_) async => jsonResponse(userDocument());
  Future<Response> Function() onLogout = () async => jsonResponse({});
  Future<Response> Function(String usr, String pwd) onLogin = (_, __) async =>
      jsonResponse({'message': 'Logged In', 'full_name': 'Pat Picker'});

  @override
  bool Function() hasActiveSession = () => false;

  @override
  void Function() onSessionExpired = () {};

  @override
  String get baseUrl => 'https://erp.example.com';

  @override
  Future<bool> hasSessionCookies() async => hasCookies;

  @override
  Future<void> clearSessionCookies() async {
    clearCookieCalls++;
    hasCookies = false;
  }

  @override
  Future<Response> getLoggedUser() {
    identityChecks++;
    return onGetLoggedUser();
  }

  @override
  Future<Response> getUserDetails(String email) => onGetUserDetails(email);

  /// The Desk page (`frappe.boot`). `null` = not readable, as when offline.
  Future<String?> Function() onGetDeskHtml = () async => null;
  int deskHtmlCalls = 0;

  @override
  Future<String?> getDeskHtml() {
    deskHtmlCalls++;
    return onGetDeskHtml();
  }

  @override
  Future<Response> logoutApiCall({CancelToken? cancelToken}) {
    logoutCalls++;
    return onLogout();
  }

  @override
  Future<Response> loginWithFrappe(String username, String password) =>
      onLogin(username, password);

  /// Grants read access, in the shape `frappe.client.get_list` answers with.
  @override
  Future<Response> hasPermission(String doctype, String permType) async {
    permissionChecks.add(doctype);
    return jsonResponse({'message': <dynamic>[]});
  }

  /// The navigation drawer loads its workspaces through this after login.
  /// Unreachable by default, so the drawer keeps its default menu.
  Future<Response> Function(String method) onCallMethod =
      (_) async => throw networkError();
  final List<String> methodCalls = [];

  @override
  Future<Response> callMethod(String method,
      {Map<String, dynamic>? params}) {
    methodCalls.add(method);
    return onCallMethod(method);
  }
}

class FakeUserProvider extends Fake implements UserProvider {
  /// Frappe v15's `get_roles`. v16 removed it: make this throw `httpError(417)`.
  Future<Response> Function(String userId) onGetUserRoles =
      (_) async => jsonResponse({'message': <String>['Stock User']});

  /// Roles read from Desk's boot data, the v16 source.
  Future<List<String>> Function(String userId) onGetRolesFromDesk =
      (_) async => const <String>[];
  int deskRoleCalls = 0;

  @override
  Future<Response> getUserRoles(String userId) => onGetUserRoles(userId);

  @override
  Future<List<String>> getRolesFromDesk(String userId) {
    deskRoleCalls++;
    return onGetRolesFromDesk(userId);
  }

  @override
  Future<Response> getEmployeeIdForUser(String userEmail) async =>
      jsonResponse({
        'data': [
          {'name': 'HR-EMP-00013'},
        ],
      });
}

class FakeStorageService extends Fake implements StorageService {
  User? stored;

  @override
  Future<void> saveUser(User user) async => stored = user;

  @override
  User? getUser() => stored;

  @override
  Future<void> clearUserData() async => stored = null;

  @override
  List<dynamic>? getNavMenu(String user) => null;

  @override
  Future<void> saveNavMenu(
      String user, List<Map<String, dynamic>> menu) async {}
}

// Extends GetxService (not Fake) because Get.put drives the GetX lifecycle
// hooks on anything that is a GetLifeCycle.
class FakePermissionService extends GetxService implements PermissionService {
  int clearCalls = 0;
  int prefetchCalls = 0;

  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => true;

  @override
  Future<String?> moduleOf(String doctype) async => null;

  // Anything else on PermissionService is not part of the auth flow.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void clearCache() => clearCalls++;

  @override
  Future<void> prefetchAll(
    List<({String doctype, String permType})> entries,
  ) async =>
      prefetchCalls++;
}

/// Only the server URL lookup is scripted; anything else is unexpected here.
class FakeDatabaseService extends GetxService implements DatabaseService {
  String? serverUrl = 'https://erp.example.com';

  @override
  Future<String?> getConfig(String key) async => serverUrl;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
