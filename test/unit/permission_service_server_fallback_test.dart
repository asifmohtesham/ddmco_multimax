import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';

/// Answers `getdoctype` and `has_permission` without a server.
class _FakeApiProvider extends ApiProvider {
  _FakeApiProvider({required this.serverGrants});

  /// permType → what `frappe.client.has_permission` would answer.
  final Map<String, bool> serverGrants;

  final docTypePermissionCalls = <String>[];

  @override
  Future<({Set<String> create, Set<String> write, String? module})>
      fetchDocTypeRoles(String doctype) async =>
          (create: {'Stock User'}, write: {'Stock User'}, module: 'Stock');

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

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Stub the path_provider channel so ApiProvider._initDio() doesn't throw
    // in a headless test environment (no platform plugins available).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  group('PermissionService.rolesKnown', () {
    test('an empty role set means the roles could not be read', () {
      expect(PermissionService.rolesKnown(const {}), isFalse);
    });

    test('any role means the roles are known', () {
      expect(PermissionService.rolesKnown({'All'}), isTrue);
    });
  });

  // No AuthenticationController is registered in these tests, so the service
  // sees no roles — the situation on Frappe v16 for a user who is not a
  // System Manager.
  group('PermissionService create/write without known roles', () {
    late _FakeApiProvider api;
    late PermissionService service;

    tearDown(() => Get.deleteAll(force: true));

    Future<void> resolve(Map<String, bool> serverGrants) async {
      api = _FakeApiProvider(serverGrants: serverGrants);
      Get.put<ApiProvider>(api);
      service = PermissionService();
      await service.prefetchAll([
        (doctype: 'Stock Entry', permType: 'create'),
        (doctype: 'Stock Entry', permType: 'write'),
      ]);
    }

    test('grants what the server grants', () async {
      await resolve({'create': true, 'write': true});
      expect(service.hasAccess('Stock Entry', permType: 'create'), isTrue);
      expect(service.hasAccess('Stock Entry', permType: 'write'), isTrue);
    });

    test('denies what the server denies', () async {
      await resolve({'create': false, 'write': true});
      expect(service.hasAccess('Stock Entry', permType: 'create'), isFalse);
      expect(service.hasAccess('Stock Entry', permType: 'write'), isTrue);
    });

    test('asks the server once per permission type', () async {
      await resolve({'create': true, 'write': true});
      expect(
        api.docTypePermissionCalls,
        unorderedEquals(['Stock Entry:create', 'Stock Entry:write']),
      );
    });

    test('still records the module from getdoctype', () async {
      await resolve({'create': true, 'write': true});
      expect(await service.moduleOf('Stock Entry'), 'Stock');
    });
  });
}
