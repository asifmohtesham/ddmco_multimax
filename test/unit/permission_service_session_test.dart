// test/unit/permission_service_session_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

import '../helpers/auth_fakes.dart';

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

      expect(permissions.hasAccess('Stock Entry'), isNull);
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

    test('still works where no AuthenticationController exists', () async {
      permissions.hasAccess('Stock Entry');
      await pumpEventQueue();

      expect(api.permissionChecks, ['Stock Entry']);
    });
  });

  group('prefetchAll', () {
    test('is not held back: login calls it as it signs the user in',
        () async {
      auth(signedIn: false);

      await permissions.prefetchAll([
        (doctype: 'Stock Entry', permType: 'read'),
        (doctype: 'Delivery Note', permType: 'read'),
      ]);

      expect(api.permissionChecks, ['Stock Entry', 'Delivery Note']);
    });
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
