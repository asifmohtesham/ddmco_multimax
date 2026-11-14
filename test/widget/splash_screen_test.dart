// test/widget/splash_screen_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_pages.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/auth/splash/splash_screen.dart';

import '../helpers/auth_fakes.dart';

void main() {
  late FakeApiProvider api;
  late FakeStorageService storage;
  late AuthenticationController auth;

  setUp(() {
    Get.testMode = false;
    api = FakeApiProvider();
    storage = FakeStorageService();
    Get.put<ApiProvider>(api, permanent: true);
    Get.put<UserProvider>(FakeUserProvider(), permanent: true);
    Get.put<StorageService>(storage, permanent: true);
    Get.put<PermissionService>(FakePermissionService(), permanent: true);
    auth = Get.put(AuthenticationController(), permanent: true);
  });

  tearDown(Get.reset);

  /// Starts the app the way main() does: on the splash route, as registered
  /// in the real route table. Home and login are stand-ins.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: AppRoutes.SPLASH,
      getPages: [
        AppPages.routes.firstWhere((page) => page.name == AppRoutes.SPLASH),
        GetPage(
          name: AppRoutes.HOME,
          page: () => const Scaffold(body: Text('home screen')),
        ),
        GetPage(
          name: AppRoutes.LOGIN,
          page: () => const Scaffold(body: Text('login screen')),
        ),
      ],
    ));
    await tester.pump();
  }

  testWidgets('shows progress while the server is being asked',
      (tester) async {
    final answer = Completer<Response>();
    api.onGetLoggedUser = () => answer.future;

    await launch(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('home screen'), findsNothing);
    expect(find.text('login screen'), findsNothing);

    answer.complete(jsonResponse({'message': kTestEmail}));
    await tester.pumpAndSettle();

    expect(find.text('home screen'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('says so when the server is slow to answer', (tester) async {
    final answer = Completer<Response>();
    api.onGetLoggedUser = () => answer.future;

    await launch(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Still trying'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('Still trying'), findsOneWidget);

    answer.complete(jsonResponse({'message': kTestEmail}));
    await tester.pumpAndSettle();
  });

  testWidgets('opens home when the server confirms the session',
      (tester) async {
    await launch(tester);
    await tester.pumpAndSettle();

    expect(find.text('home screen'), findsOneWidget);
    expect(auth.currentUser.value?.email, kTestEmail);
  });

  testWidgets('opens login when there is no stored session', (tester) async {
    api.hasCookies = false;

    await launch(tester);
    await tester.pumpAndSettle();

    expect(find.text('login screen'), findsOneWidget);
    expect(api.identityChecks, 0);
  });

  testWidgets('opens login when the server rejects the stored session',
      (tester) async {
    storage.stored = cachedUser();
    api.onGetLoggedUser = () async => jsonResponse({'message': 'Guest'});

    await launch(tester);
    await tester.pumpAndSettle();

    expect(find.text('login screen'), findsOneWidget);
    expect(auth.isAuthenticated.value, isFalse);
  });

  testWidgets('opens home as the cached user when the server is unreachable',
      (tester) async {
    storage.stored = cachedUser();
    api.onGetLoggedUser = () async => throw networkError();

    await launch(tester);
    await tester.pumpAndSettle();

    expect(find.text('home screen'), findsOneWidget);
    expect(auth.currentUser.value?.email, kTestEmail);
    expect(api.clearCookieCalls, 0);

    // The background re-check keeps running by design; stop it so the
    // test can end.
    auth.onClose();
  });
}
