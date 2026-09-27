// test/widget/login_screen_test.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/auth/login_controller.dart';
import 'package:multimax/app/modules/auth/login_screen.dart';

import '../helpers/auth_fakes.dart';

void main() {
  late FakeApiProvider api;
  late AuthenticationController auth;

  setUp(() {
    Get.testMode = false;
    api = FakeApiProvider()..hasCookies = false;
    // Permanent, as in main(): GetX otherwise ties an instance to the route
    // that was current when it was registered and deletes it with that route.
    Get.put<ApiProvider>(api, permanent: true);
    Get.put<UserProvider>(FakeUserProvider(), permanent: true);
    Get.put<StorageService>(FakeStorageService(), permanent: true);
    Get.put<PermissionService>(FakePermissionService(), permanent: true);
    Get.put<DatabaseService>(FakeDatabaseService(), permanent: true);
    auth = Get.put(AuthenticationController(), permanent: true);
  });

  tearDown(Get.reset);

  Future<void> submitLogin(
    WidgetTester tester, {
    String username = kTestEmail,
    String password = 'correct horse',
  }) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: AppRoutes.LOGIN,
      getPages: [
        GetPage(
          name: AppRoutes.LOGIN,
          page: () => const LoginScreen(),
          binding: BindingsBuilder(
              () => Get.lazyPut<LoginController>(() => LoginController())),
        ),
        GetPage(
          name: AppRoutes.HOME,
          page: () => const Scaffold(body: Text('home screen')),
        ),
      ],
    ));
    await tester.enterText(find.byType(TextFormField).at(0), username);
    await tester.enterText(find.byType(TextFormField).at(1), password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
  }

  group('a failed login tells the user why', () {
    testWidgets('wrong password shows the reason the server gave',
        (tester) async {
      api.onLogin = (_, __) async => throw httpError(401, data: {
            'message': 'Invalid login credentials',
            'exc_type': 'AuthenticationError',
          });

      await submitLogin(tester);

      expect(find.textContaining('Invalid login credentials'), findsOneWidget);
      expect(find.textContaining('unexpected'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('a bare 401 is described as incorrect credentials',
        (tester) async {
      api.onLogin = (_, __) async => throw httpError(401);

      await submitLogin(tester);

      expect(find.textContaining('Incorrect email or password'),
          findsOneWidget);
    });

    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.connectionError,
    ]) {
      testWidgets('${type.name} names the server that cannot be reached',
          (tester) async {
        api.onLogin = (_, __) async => throw networkError(type);

        await submitLogin(tester);

        expect(find.textContaining('erp.example.com'), findsOneWidget);
        expect(find.textContaining('Incorrect'), findsNothing);
      });
    }

    testWidgets('a server fault is not blamed on the credentials',
        (tester) async {
      api.onLogin = (_, __) async => throw httpError(502);

      await submitLogin(tester);

      expect(find.textContaining('502'), findsOneWidget);
      expect(find.textContaining('Incorrect'), findsNothing);
    });

    testWidgets('a 404 points at the server address', (tester) async {
      api.onLogin = (_, __) async => throw httpError(404);

      await submitLogin(tester);

      expect(find.textContaining('server address'), findsOneWidget);
    });

    testWidgets('the form can be submitted again afterwards', (tester) async {
      api.onLogin = (_, __) async => throw httpError(401);

      await submitLogin(tester);

      final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Login'));
      expect(button.onPressed, isNotNull);
    });
  });

  group('credentials are sent as typed', () {
    late List<(String, String)> submitted;

    setUp(() {
      submitted = [];
      api.onLogin = (usr, pwd) async {
        submitted.add((usr, pwd));
        return jsonResponse({'message': 'Logged In', 'full_name': 'Pat'});
      };
    });

    testWidgets('spaces in a password are part of the password',
        (tester) async {
      await submitLogin(tester, password: ' correct horse ');

      expect(submitted, [(kTestEmail, ' correct horse ')]);
    });

    testWidgets('a short password is left for the server to judge',
        (tester) async {
      await submitLogin(tester, password: 'abc');

      expect(submitted, [(kTestEmail, 'abc')]);
    });

    testWidgets('spaces around the username are dropped', (tester) async {
      await submitLogin(tester, username: '  $kTestEmail ');

      expect(submitted, [(kTestEmail, 'correct horse')]);
    });

    testWidgets('an empty password is not submitted', (tester) async {
      await submitLogin(tester, password: '');

      expect(submitted, isEmpty);
      expect(find.text('Please enter your password'), findsOneWidget);
    });
  });

  group('a successful login', () {
    testWidgets('opens home as the logged-in user', (tester) async {
      await submitLogin(tester);

      expect(find.text('home screen'), findsOneWidget);
      expect(auth.isAuthenticated.value, isTrue);
      expect(auth.currentUser.value?.employeeId, 'HR-EMP-00013');
    });

    testWidgets('asks the server for the identity once', (tester) async {
      await submitLogin(tester);

      expect(api.identityChecks, 1);
    });

    testWidgets('opens home even when the profile cannot be loaded',
        (tester) async {
      api.onGetUserDetails = (_) async => throw httpError(403);

      await submitLogin(tester);

      expect(find.text('home screen'), findsOneWidget);
      expect(auth.isAuthenticated.value, isTrue);
      expect(auth.currentUser.value?.name, 'Pat Picker');
      expect(api.clearCookieCalls, 0);
    });

    testWidgets('stays on login when the server disowns the new session',
        (tester) async {
      api.onGetLoggedUser = () async => jsonResponse({'message': 'Guest'});

      await submitLogin(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('home screen'), findsNothing);
      expect(auth.isAuthenticated.value, isFalse);
    });
  });
}
