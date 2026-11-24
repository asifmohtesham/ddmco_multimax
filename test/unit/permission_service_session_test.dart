// test/unit/permission_service_session_test.dart
import 'dart:convert';

import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';

import '../helpers/auth_fakes.dart';

class _DeskUserProvider extends UserProvider {
  @override
  Future<Response> getEmployeeIdForUser(String userEmail) async =>
      jsonResponse({'data': []});
}

void main() {
  late FakeApiProvider api;
  late PermissionService permissions;

  setUp(() {
    Get.testMode = true;
    api = FakeApiProvider();
    Get.put<ApiProvider>(api, permanent: true);
    Get.put<UserProvider>(FakeUserProvider(), permanent: true);
    Get.put<StorageService>(FakeStorageService(), permanent: true);
    permissions =
        Get.put<PermissionService>(PermissionService(), permanent: true);
  });

  tearDown(Get.reset);

  AuthenticationController auth({required bool signedIn}) =>
      Get.put(AuthenticationController(), permanent: true)
        ..currentUser.value = signedIn ? cachedUser() : null
        ..isAuthenticated.value = signedIn;

  group('hasAccess', () {
    test('asks the server while signed in', () async {
      auth(signedIn: true);

      expect(permissions.hasAccess('Stock Entry'), isNull);
      await pumpEventQueue();

      expect(api.permissionChecks, ['Stock Entry']);
      expect(permissions.hasAccess('Stock Entry'), isTrue);
    });

    test('asks nothing of the server while signed out', () async {
      auth(signedIn: false);

      // Denied rather than loading, so guarded widgets hide at once.
      expect(permissions.hasAccess('Stock Entry'), isFalse);
      await pumpEventQueue();

      expect(api.permissionChecks, isEmpty);
    });

    test('does not remember a refusal from a signed-out moment', () async {
      final controller = auth(signedIn: false);
      permissions.hasAccess('Stock Entry');
      await pumpEventQueue();

      controller.isAuthenticated.value = true;
      permissions.hasAccess('Stock Entry');
      await pumpEventQueue();

      expect(permissions.hasAccess('Stock Entry'), isTrue);
    });

    test('treats a missing AuthenticationController as signed out',
        () async {
      expect(permissions.hasAccess('Stock Entry'), isFalse);
      await pumpEventQueue();

      expect(api.permissionChecks, isEmpty);
    });
  });

  group('prefetchAll', () {
    // fetchUserDetails marks the user signed in before it prefetches, so
    // the signed-out guard never holds back the login prefetch.
    test('runs once login has marked the user signed in', () async {
      auth(signedIn: true);

      await permissions.prefetchAll([
        (doctype: 'Stock Entry', permType: 'read'),
        (doctype: 'Delivery Note', permType: 'read'),
      ]);

      expect(api.permissionChecks, ['Stock Entry', 'Delivery Note']);
    });
  });

  test('Suppliers by Item uses the signed-in roles and skips prefetch probes',
      () async {
    final controller = auth(signedIn: true);
    const report = kSuppliersByItemPermission;
    bool? reportAccess() =>
        permissions.hasAccess(report.doctype, permType: report.permType);

    for (final role in ['Purchase User', 'Stock User']) {
      controller.currentUser.value = cachedUser().copyWith(roles: [role]);
      expect(reportAccess(), isTrue, reason: role);
      expect(permissions.canViewSuppliersByItem, isTrue, reason: role);
    }

    controller.currentUser.value = cachedUser().copyWith(roles: []);
    expect(reportAccess(), isFalse);
    controller.currentUser.value =
        cachedUser().copyWith(roles: ['System Manager']);
    expect(reportAccess(), isFalse);
    expect(permissions.canViewSuppliersByItem, isFalse);

    controller.currentUser.value = cachedUser();
    await permissions.prefetchAll([
      report,
      (doctype: 'Stock Entry', permType: 'read'),
    ]);
    expect(api.permissionChecks, ['Stock Entry']);

    controller.isAuthenticated.value = false;
    expect(reportAccess(), isFalse);
    expect(permissions.canViewSuppliersByItem, isFalse);
  });

  test('Suppliers by Item opens for a v16 purchase user with Desk boot roles',
      () async {
    await Get.delete<UserProvider>(force: true);
    Get.put<UserProvider>(_DeskUserProvider(), permanent: true);
    api.onGetUserDetails = (_) async {
      final document = userDocument();
      (document['data'] as Map<String, dynamic>).remove('roles');
      return jsonResponse(document);
    };
    api.onCallMethod = (_) async => throw httpError(417);
    const roles = ['All', 'Desk User', 'Purchase User'];
    final boot = jsonEncode({
      'user': {'name': kTestEmail, 'roles': roles},
    });
    api.onGetDeskHtml = () async => '<script>frappe.boot = $boot;</script>';

    final controller = auth(signedIn: false);
    expect(permissions.canViewSuppliersByItem, isFalse);

    expect(await controller.fetchUserDetails(), SessionCheck.valid);

    expect(controller.currentUser.value?.roles, roles);
    expect(permissions.canViewSuppliersByItem, isTrue);
    const report = kSuppliersByItemPermission;
    expect(permissions.hasAccess(report.doctype, permType: report.permType),
        isTrue);
    expect(api.permissionChecks, isNot(contains(report.doctype)));
  });

  test('Suppliers by Item quick action follows the drawer report permissions',
      () async {
    final controller = auth(signedIn: true);
    final report = kSuppliersByItemPermission.doctype;
    final drawer = AppNavDrawerController.instance;

    Future<void> loadDeskReports(Set<String> allowedReports) async {
      drawer.clearSession();
      final boot = jsonEncode({
        'user': {'name': kTestEmail},
        'allowed_reports': {
          for (final name in allowedReports) name: <String, Object>{},
        },
      });
      api.onGetDeskHtml = () async => '<script>frappe.boot = $boot;</script>';
      await drawer.loadFor(kTestEmail);
    }

    expect(AppNavDrawerController.canOpenSuppliersByItem, isTrue);
    await loadDeskReports({'Stock Balance'});
    expect(AppNavDrawerController.canOpenSuppliersByItem, isFalse);
    await loadDeskReports({report});
    expect(AppNavDrawerController.canOpenSuppliersByItem, isTrue);

    controller.currentUser.value = cachedUser().copyWith(roles: ['Sales User']);
    expect(AppNavDrawerController.canOpenSuppliersByItem, isFalse);

    controller.currentUser.value = cachedUser();
    controller.isAuthenticated.value = false;
    expect(AppNavDrawerController.canOpenSuppliersByItem, isFalse);
  });

  testWidgets('a guarded screen still on display during logout asks nothing',
      (tester) async {
    Get.testMode = false;
    final controller = auth(signedIn: true);
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: AppRoutes.HOME,
      getPages: [
        GetPage(
          name: AppRoutes.HOME,
          page: () => Scaffold(
            body: Obx(() =>
                Text('stock entry: ${permissions.hasAccess('Stock Entry')}')),
          ),
        ),
        GetPage(
          name: AppRoutes.LOGIN,
          page: () => const Scaffold(body: Text('login screen')),
        ),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('stock entry: true'), findsOneWidget);
    expect(api.permissionChecks, ['Stock Entry']);

    await controller.performLogout();
    await tester.pumpAndSettle();

    expect(find.text('login screen'), findsOneWidget);
    expect(api.permissionChecks, ['Stock Entry']);
  });
}
