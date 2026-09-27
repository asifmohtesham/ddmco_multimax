// test/unit/authentication_controller_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
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
  late FakeStorageService storage;
  late FakePermissionService permissions;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() {
    Get.testMode = true;
    api = FakeApiProvider();
    storage = FakeStorageService();
    permissions = FakePermissionService();
    Get.put<ApiProvider>(api);
    Get.put<UserProvider>(FakeUserProvider());
    Get.put<StorageService>(storage);
    Get.put<PermissionService>(permissions);
  });

  tearDown(() => Get.deleteAll(force: true));

  /// A controller that already holds a signed-in user, as it would mid-shift.
  AuthenticationController signedInController() {
    storage.stored = cachedUser();
    return AuthenticationController()
      ..currentUser.value = cachedUser()
      ..isAuthenticated.value = true;
  }

  group('fetchUserDetails — server cannot be reached', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ]) {
      test('keeps the session on ${type.name}', () async {
        final auth = signedInController();
        api.onGetLoggedUser = () async => throw networkError(type);

        await auth.fetchUserDetails();

        expect(api.clearCookieCalls, 0);
        expect(auth.isAuthenticated.value, isTrue);
        expect(auth.currentUser.value?.email, kTestEmail);
        expect(storage.stored?.email, kTestEmail);
      });
    }

    test('keeps the session when the server answers 503', () async {
      final auth = signedInController();
      api.onGetLoggedUser = () async => throw httpError(503);

      await auth.fetchUserDetails();

      expect(api.clearCookieCalls, 0);
      expect(auth.isAuthenticated.value, isTrue);
    });
  });

  group('fetchUserDetails — server rejects the session', () {
    test('ends the session when Frappe reports Guest', () async {
      final auth = signedInController();
      api.onGetLoggedUser = () async => jsonResponse({'message': 'Guest'});

      await auth.fetchUserDetails();

      expect(api.clearCookieCalls, 1);
      expect(auth.isAuthenticated.value, isFalse);
      expect(auth.currentUser.value, isNull);
      expect(storage.stored, isNull);
    });

    for (final status in [401, 403]) {
      test('ends the session when the server answers $status', () async {
        final auth = signedInController();
        api.onGetLoggedUser = () async => throw httpError(status);

        await auth.fetchUserDetails();

        expect(api.clearCookieCalls, 1);
        expect(auth.isAuthenticated.value, isFalse);
      });
    }
  });

  group('fetchUserDetails — result', () {
    test('reports valid and loads the profile when the server confirms',
        () async {
      final auth = AuthenticationController();

      final result = await auth.fetchUserDetails();

      expect(result, SessionCheck.valid);
      expect(auth.currentUser.value?.employeeId, 'HR-EMP-00013');
      expect(storage.stored?.email, kTestEmail);
      expect(permissions.prefetchCalls, 1);
    });

    test('reports unverified when the server cannot be reached', () async {
      final auth = signedInController();
      api.onGetLoggedUser = () async => throw networkError();

      expect(await auth.fetchUserDetails(), SessionCheck.unverified);
    });

    test('reports invalid when Frappe reports Guest', () async {
      final auth = signedInController();
      api.onGetLoggedUser = () async => jsonResponse({'message': 'Guest'});

      expect(await auth.fetchUserDetails(), SessionCheck.invalid);
    });

    test('keeps a confirmed session when the profile is forbidden', () async {
      final auth = signedInController();
      api.onGetUserDetails = (_) async => throw httpError(403);

      final result = await auth.fetchUserDetails();

      expect(result, SessionCheck.unverified);
      expect(api.clearCookieCalls, 0);
      expect(auth.isAuthenticated.value, isTrue);
    });
  });

  group('checkAuthenticationStatus — app start', () {
    test('stays signed in as the cached user when offline', () async {
      storage.stored = cachedUser();
      api.onGetLoggedUser = () async => throw networkError();
      final auth = AuthenticationController();

      await auth.checkAuthenticationStatus();
      addTearDown(auth.onClose);

      expect(auth.isAuthenticated.value, isTrue);
      expect(auth.currentUser.value?.email, kTestEmail);
      expect(api.clearCookieCalls, 0);
    });

    test('shows login but keeps the cookie when offline with no cached user',
        () async {
      api.onGetLoggedUser = () async => throw networkError();
      final auth = AuthenticationController();

      await auth.checkAuthenticationStatus();
      addTearDown(auth.onClose);

      expect(auth.isAuthenticated.value, isFalse);
      expect(api.clearCookieCalls, 0);
    });

    test('is signed out when there is no session cookie', () async {
      storage.stored = cachedUser();
      api.hasCookies = false;
      final auth = AuthenticationController();

      await auth.checkAuthenticationStatus();

      expect(auth.isAuthenticated.value, isFalse);
      expect(storage.stored, isNull);
    });
  });

  group('recovery after an unverified start', () {
    testWidgets('re-checks until the server confirms, then stops',
        (tester) async {
      var identityChecks = 0;
      var online = false;
      api.onGetLoggedUser = () async {
        identityChecks++;
        if (!online) throw networkError();
        return jsonResponse({'message': kTestEmail});
      };
      storage.stored = cachedUser();
      final auth = AuthenticationController();
      addTearDown(auth.onClose);

      await auth.checkAuthenticationStatus();
      expect(permissions.prefetchCalls, 0);

      online = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(permissions.prefetchCalls, 1);
      final checksOnceVerified = identityChecks;

      await tester.pump(const Duration(minutes: 5));
      expect(identityChecks, checksOnceVerified);
    });

    testWidgets('ends the session if a later re-check is rejected',
        (tester) async {
      var rejected = false;
      api.onGetLoggedUser = () async {
        if (rejected) return jsonResponse({'message': 'Guest'});
        throw networkError();
      };
      storage.stored = cachedUser();
      final auth = AuthenticationController();
      addTearDown(auth.onClose);

      await auth.checkAuthenticationStatus();
      rejected = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(auth.isAuthenticated.value, isFalse);
      expect(api.clearCookieCalls, 1);
    });
  });

  group('performLogout', () {
    test('tells the server when it is reachable', () async {
      final auth = signedInController();

      await auth.performLogout();

      expect(api.logoutCalls, 1);
      expect(api.clearCookieCalls, 1);
      expect(auth.isAuthenticated.value, isFalse);
    });

    test('clears the local session when the server call fails', () async {
      final auth = signedInController();
      api.onLogout = () async => throw networkError();

      await auth.performLogout();

      expect(api.clearCookieCalls, 1);
      expect(auth.isAuthenticated.value, isFalse);
      expect(auth.currentUser.value, isNull);
      expect(storage.stored, isNull);
      expect(permissions.clearCalls, 1);
    });

    testWidgets('does not wait forever for a server that never answers',
        (tester) async {
      final auth = signedInController();
      api.onLogout = () => Completer<Response>().future;

      unawaited(auth.performLogout());
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(api.clearCookieCalls, 1);
      expect(auth.isAuthenticated.value, isFalse);
    });
  });

  group('handleSessionExpired', () {
    test('clears the session', () async {
      final auth = signedInController();

      await auth.handleSessionExpired();

      expect(api.clearCookieCalls, 1);
      expect(auth.isAuthenticated.value, isFalse);
      expect(storage.stored, isNull);
    });

    test('runs once when several requests report expiry together', () async {
      final auth = signedInController();

      await Future.wait([
        auth.handleSessionExpired(),
        auth.handleSessionExpired(),
        auth.handleSessionExpired(),
      ]);

      expect(api.clearCookieCalls, 1);
    });

    test('does nothing when nobody is signed in', () async {
      final auth = AuthenticationController();

      await auth.handleSessionExpired();

      expect(api.clearCookieCalls, 0);
    });
  });

  group('navigation', () {
    Widget app() => GetMaterialApp(
          initialRoute: AppRoutes.HOME,
          getPages: [
            GetPage(
              name: AppRoutes.HOME,
              page: () => const Scaffold(body: Text('home screen')),
            ),
            GetPage(
              name: AppRoutes.LOGIN,
              page: () => const Scaffold(body: Text('login screen')),
            ),
          ],
        );

    setUp(() => Get.testMode = false);

    testWidgets('an expired session lands on login with an explanation',
        (tester) async {
      final auth = signedInController();
      await tester.pumpWidget(app());

      await auth.handleSessionExpired();
      await tester.pumpAndSettle();

      expect(find.text('login screen'), findsOneWidget);
      expect(find.text('home screen'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a session rejected during an in-app refresh lands on login',
        (tester) async {
      final auth = signedInController();
      api.onGetLoggedUser = () async => jsonResponse({'message': 'Guest'});
      await tester.pumpWidget(app());

      final result = await auth.revalidateSession();
      await tester.pumpAndSettle();

      expect(result, SessionCheck.invalid);
      expect(find.text('login screen'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('an in-app refresh that cannot reach the server stays put',
        (tester) async {
      final auth = signedInController();
      api.onGetLoggedUser = () async => throw networkError();
      await tester.pumpWidget(app());

      final result = await auth.revalidateSession();
      await tester.pumpAndSettle();

      expect(result, SessionCheck.unverified);
      expect(find.text('home screen'), findsOneWidget);
      expect(auth.isAuthenticated.value, isTrue);
    });

    testWidgets('logging out offline still lands on login', (tester) async {
      final auth = signedInController();
      api.onLogout = () async => throw networkError();
      await tester.pumpWidget(app());

      await auth.performLogout();
      await tester.pumpAndSettle();

      expect(find.text('login screen'), findsOneWidget);
      expect(find.text('home screen'), findsNothing);
    });
  });

  group('ApiProvider wiring', () {
    test('reports whether a session is active', () {
      final auth = Get.put(AuthenticationController());

      expect(api.hasActiveSession(), isFalse);
      auth.isAuthenticated.value = true;
      expect(api.hasActiveSession(), isTrue);
    });

    test('an expiry reported by the HTTP layer ends the session', () async {
      final auth = Get.put(AuthenticationController());
      storage.stored = cachedUser();
      auth.currentUser.value = cachedUser();
      auth.isAuthenticated.value = true;

      api.onSessionExpired();
      await pumpEventQueue();

      expect(api.clearCookieCalls, 1);
      expect(auth.isAuthenticated.value, isFalse);
    });
  });
}
