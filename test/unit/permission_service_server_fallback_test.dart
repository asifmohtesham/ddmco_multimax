import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

/// Answers `getdoctype` and `has_permission` without a server.
class _FakeApiProvider extends ApiProvider {
  /// permType → what `frappe.client.has_permission` would answer.
  Map<String, bool> serverGrants = const {};

  /// Every DocType-level `has_permission` call issued, as `doctype:permType`.
  final docTypePermissionCalls = <String>[];

  /// When set, `getdoctype` awaits it before resolving — lets a test hold the
  /// lookup in flight across a sign-out.
  Completer<void>? docTypeGate;

  @override
  Future<({Set<String> create, Set<String> write, String? module})>
      fetchDocTypeRoles(String doctype) async {
    await docTypeGate?.future;
    return (create: {'Stock User'}, write: <String>{}, module: 'Stock');
  }

  @override
  Future<Response> hasDocTypePermission(String doctype, String ptype) async {
    docTypePermissionCalls.add('$doctype:$ptype');
    return Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {
        'message': {'has_permission': serverGrants[ptype] ?? false},
      },
    );
  }
}

/// Auth fake: neutralises the network `checkAuthenticationStatus()` that the
/// real onInit fires.
class _FakeAuthController extends AuthenticationController {
  @override
  Future<void> checkAuthenticationStatus() async {}
}

/// StorageService fake: never touches GetStorage.
class _FakeStorageService extends StorageService {
  _FakeStorageService() : super.withStorage(null);

  @override
  String? getBaseUrl() => null;

  @override
  Future<void> clearUserData() async {}
}

const _entries = [
  (doctype: 'Stock Entry', permType: 'create'),
  (doctype: 'Stock Entry', permType: 'write'),
];

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ApiProvider's constructor fires _initDio(), which touches path_provider
    // for the cookie-jar directory — stub it so construction doesn't throw.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  late _FakeApiProvider api;
  late _FakeAuthController auth;
  late PermissionService service;

  setUp(() {
    // StorageService must precede ApiProvider: _initDio reads getBaseUrl.
    Get.put<StorageService>(_FakeStorageService());
    api = _FakeApiProvider();
    Get.put<ApiProvider>(api);
    service = Get.put<PermissionService>(PermissionService());
    auth = _FakeAuthController();
    Get.put<AuthenticationController>(auth);
  });

  tearDown(() => Get.deleteAll(force: true));

  /// Puts [auth] in the signed-in state login leaves it in.
  void signIn({required List<String> roles}) {
    auth.currentUser.value = User(
      id: 'operator@example.com',
      name: 'Operator',
      email: 'operator@example.com',
      roles: roles,
    );
    auth.isAuthenticated.value = true;
  }

  group('PermissionService.rolesKnown', () {
    test('an empty role set means the roles could not be read', () {
      expect(PermissionService.rolesKnown(const {}), isFalse);
    });

    test('any role means the roles are known', () {
      expect(PermissionService.rolesKnown({'All'}), isTrue);
    });
  });

  // Frappe v16, user who is not a System Manager: the roles cannot be read.
  group('create/write when the roles are unknown', () {
    test('grants what the server grants', () async {
      signIn(roles: const []);
      api.serverGrants = {'create': true, 'write': true};
      await service.prefetchAll(_entries);

      expect(service.hasAccess('Stock Entry', permType: 'create'), isTrue);
      expect(service.hasAccess('Stock Entry', permType: 'write'), isTrue);
    });

    test('denies what the server denies', () async {
      signIn(roles: const []);
      api.serverGrants = {'create': false, 'write': true};
      await service.prefetchAll(_entries);

      expect(service.hasAccess('Stock Entry', permType: 'create'), isFalse);
      expect(service.hasAccess('Stock Entry', permType: 'write'), isTrue);
    });

    test('asks the server once per permission type', () async {
      signIn(roles: const []);
      await service.prefetchAll(_entries);

      expect(
        api.docTypePermissionCalls,
        unorderedEquals(['Stock Entry:create', 'Stock Entry:write']),
      );
    });

    test('still records the module from getdoctype', () async {
      signIn(roles: const []);
      await service.prefetchAll(_entries);

      expect(await service.moduleOf('Stock Entry'), 'Stock');
    });
  });

  // Frappe v15, and System Managers on v16: unchanged behaviour.
  group('create/write when the roles are known', () {
    test('intersects the roles with the DocPerm rows', () async {
      signIn(roles: const ['Stock User']);
      // The server would say the opposite; it must not be consulted.
      api.serverGrants = {'create': false, 'write': true};
      await service.prefetchAll(_entries);

      expect(service.hasAccess('Stock Entry', permType: 'create'), isTrue);
      expect(service.hasAccess('Stock Entry', permType: 'write'), isFalse);
    });

    test('does not ask the server', () async {
      signIn(roles: const ['Stock User']);
      await service.prefetchAll(_entries);

      expect(api.docTypePermissionCalls, isEmpty);
    });
  });

  group('signing out', () {
    test('a lookup that lands after sign-out does not probe the server',
        () async {
      signIn(roles: const []);
      api.docTypeGate = Completer<void>();
      final pending = service.prefetchAll(_entries);

      // Same order as AuthenticationController._clearSessionAndLocalData.
      auth.currentUser.value = null;
      auth.isAuthenticated.value = false;
      service.clearCache();

      api.docTypeGate!.complete();
      await pending;

      expect(api.docTypePermissionCalls, isEmpty);
    });

    test('a lookup that lands mid sign-out does not probe the server',
        () async {
      signIn(roles: const []);
      api.docTypeGate = Completer<void>();
      final pending = service.prefetchAll(_entries);

      // The user is gone but the cache has not been cleared yet.
      auth.currentUser.value = null;
      auth.isAuthenticated.value = false;

      api.docTypeGate!.complete();
      await pending;

      expect(api.docTypePermissionCalls, isEmpty);
    });
  });
}
