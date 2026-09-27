// test/widget/logout_confirmation_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/profile/user_profile_controller.dart';
import 'package:multimax/app/modules/profile/user_profile_screen.dart';

import '../helpers/auth_fakes.dart';

void main() {
  late FakeApiProvider api;
  late AuthenticationController auth;

  setUp(() {
    Get.testMode = false;
    api = FakeApiProvider();
    final storage = FakeStorageService()..stored = cachedUser();
    Get.put<ApiProvider>(api, permanent: true);
    Get.put<UserProvider>(FakeUserProvider(), permanent: true);
    Get.put<StorageService>(storage, permanent: true);
    Get.put<PermissionService>(FakePermissionService(), permanent: true);
    auth = Get.put(AuthenticationController(), permanent: true)
      ..currentUser.value = cachedUser()
      ..isAuthenticated.value = true;
  });

  tearDown(Get.reset);

  Future<void> openApp(WidgetTester tester, String route) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: route,
      getPages: [
        GetPage(
          name: AppRoutes.HOME,
          page: () => const Scaffold(body: Text('home screen')),
        ),
        GetPage(
          name: AppRoutes.LOGIN,
          page: () => const Scaffold(body: Text('login screen')),
        ),
        GetPage(
          name: AppRoutes.PROFILE,
          page: () => const UserProfileScreen(),
          binding: BindingsBuilder(() => Get.lazyPut<UserProfileController>(
              () => UserProfileController())),
        ),
      ],
    ));
    await tester.pumpAndSettle();
  }

  group('from the navigation drawer', () {
    testWidgets('asks once, then signs out', (tester) async {
      await openApp(tester, AppRoutes.HOME);

      auth.logoutUser();
      await tester.pumpAndSettle();
      expect(find.text('Confirm Logout'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Logout'));
      await tester.pumpAndSettle();

      expect(find.text('login screen'), findsOneWidget);
      expect(api.logoutCalls, 1);
    });

    testWidgets('cancelling keeps the user signed in', (tester) async {
      await openApp(tester, AppRoutes.HOME);

      auth.logoutUser();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('home screen'), findsOneWidget);
      expect(api.logoutCalls, 0);
      expect(auth.isAuthenticated.value, isTrue);
    });
  });

  group('from the profile screen', () {
    testWidgets('the screen\'s own confirmation is the only one',
        (tester) async {
      await openApp(tester, AppRoutes.PROFILE);

      await tester.scrollUntilVisible(find.text('Logout'), 200);
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      expect(find.text('Log Out?'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Log Out'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Logout'), findsNothing);
      expect(find.text('login screen'), findsOneWidget);
      expect(api.logoutCalls, 1);
    });

    testWidgets('backing out of the confirmation keeps the user signed in',
        (tester) async {
      await openApp(tester, AppRoutes.PROFILE);

      await tester.scrollUntilVisible(find.text('Logout'), 200);
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(UserProfileScreen), findsOneWidget);
      expect(api.logoutCalls, 0);
    });
  });
}
