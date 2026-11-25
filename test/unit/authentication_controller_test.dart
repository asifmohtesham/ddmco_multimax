// test/unit/authentication_controller_test.dart
import 'dart:async';
import 'dart:io' show Directory, File, FileSystemException;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

import '../helpers/auth_fakes.dart';

class _FailingRemoveBox extends FakeStorageBox {
  @override
  Future<void> remove(String key) async {
    throw const FileSystemException('cache is read only');
  }
}

class _FailingClearCookiesApi extends FakeApiProvider {
  @override
  Future<void> clearSessionCookies() async {
    clearCookieCalls++;
    throw const FileSystemException('cookie files are read only');
  }
}

void main() {
  late FakeApiProvider api;
  late FakeStorageService storage;
  late FakePermissionService permissions;
  late FakeUserProvider users;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() {
    Get.testMode = true;
    api = FakeApiProvider();
    storage = FakeStorageService();
    permissions = FakePermissionService();
    Get.put<ApiProvider>(api);
    users = FakeUserProvider();
    Get.put<UserProvider>(users);
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

  StorageService useStorageBox(FakeStorageBox box) {
    final service = StorageService.withStorage(box);
    Get.replace<StorageService>(service);
    return service;
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
        expect(auth.currentUser.value, isNull);
        expect(storage.stored, isNull);
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

  group('fetchUserDetails — roles', () {
    /// What a user who is not a System Manager gets: the `roles` table is
    /// permlevel 1, so the User document arrives without it.
    Map<String, dynamic> userDocumentWithoutRoles() {
      final doc = userDocument();
      (doc['data'] as Map<String, dynamic>).remove('roles');
      return doc;
    }

    test('v15: get_roles answers, Desk is not consulted', () async {
      api.onGetUserDetails = (_) async => jsonResponse(userDocumentWithoutRoles());
      final auth = AuthenticationController();

      await auth.fetchUserDetails();

      expect(auth.currentUser.value?.roles, ['Stock User']);
      expect(users.deskRoleCalls, 0);
    });

    test('System Manager: roles on the User document are used as they are',
        () async {
      users.onGetUserRoles = (_) async => throw httpError(417);
      final auth = AuthenticationController();

      await auth.fetchUserDetails();

      expect(auth.currentUser.value?.roles, ['Stock User']);
      expect(users.deskRoleCalls, 0);
    });

    test('v16: get_roles is gone, roles come from Desk boot data', () async {
      api.onGetUserDetails = (_) async => jsonResponse(userDocumentWithoutRoles());
      users.onGetUserRoles = (_) async => throw httpError(417);
      users.onGetRolesFromDesk =
          (id) async => id == kTestEmail ? ['Sales User', 'Stock User - Custom'] : [];
      final auth = AuthenticationController();

      final result = await auth.fetchUserDetails();

      expect(result, SessionCheck.valid);
      expect(auth.currentUser.value?.roles, ['Sales User', 'Stock User - Custom']);
      expect(storage.stored?.roles, ['Sales User', 'Stock User - Custom']);
    });

    test('no source answers: the roles already known for this user are kept',
        () async {
      api.onGetUserDetails = (_) async => jsonResponse(userDocumentWithoutRoles());
      users.onGetUserRoles = (_) async => throw httpError(417);
      users.onGetRolesFromDesk = (_) async => throw networkError();
      final auth = signedInController(); // cached user holds ['Stock User']

      final result = await auth.fetchUserDetails();

      expect(result, SessionCheck.valid);
      expect(auth.currentUser.value?.roles, ['Stock User']);
    });

    test('no source answers and nobody was signed in: roles stay unknown',
        () async {
      api.onGetUserDetails = (_) async => jsonResponse(userDocumentWithoutRoles());
      users.onGetUserRoles = (_) async => throw httpError(417);
      final auth = AuthenticationController();

      final result = await auth.fetchUserDetails();

      expect(result, SessionCheck.valid);
      expect(auth.currentUser.value?.roles, isEmpty);
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
      expect(auth.isSessionVerificationPending.value, isFalse);
      expect(api.clearCookieCalls, 0);
    });

    test('replaces a corrupt cached profile and keeps the session cookie',
        () async {
      final box = FakeStorageBox()
        ..values['currentUser'] = {'name': kTestEmail, 'roles': 42}
        ..values['apiToken'] = 'saved token'
        ..values['baseUrl'] = 'https://erp.example.com';
      final realStorage = useStorageBox(box);
      api.onGetLoggedUser = () async {
        expect(box.values.containsKey('currentUser'), isFalse);
        return jsonResponse({'message': kTestEmail});
      };
      final auth = AuthenticationController();
      addTearDown(auth.onClose);

      await auth.checkAuthenticationStatus();

      expect(auth.isAuthenticated.value, isTrue);
      expect(auth.isSessionVerificationPending.value, isFalse);
      expect(auth.currentUser.value?.email, kTestEmail);
      expect(realStorage.getUser()?.email, kTestEmail);
      expect(box.removedKeys, ['currentUser']);
      expect(realStorage.getToken(), 'saved token');
      expect(realStorage.getBaseUrl(), 'https://erp.example.com');
      expect(api.hasCookies, isTrue);
      expect(api.clearCookieCalls, 0);
    });

    test('verifies the session even if the corrupt profile cannot be removed',
        () async {
      final box = _FailingRemoveBox()..values['currentUser'] = 'bad profile';
      final realStorage = useStorageBox(box);
      final auth = AuthenticationController();
      addTearDown(auth.onClose);

      await auth.checkAuthenticationStatus();

      expect(api.identityChecks, 1);
      expect(auth.isAuthenticated.value, isTrue);
      expect(realStorage.getUser()?.email, kTestEmail);
      expect(api.clearCookieCalls, 0);
    });

    test('is signed out when there is no session cookie', () async {
      storage.stored = cachedUser();
      api.hasCookies = false;
      final auth = AuthenticationController();

      await auth.checkAuthenticationStatus();

      expect(auth.isAuthenticated.value, isFalse);
      expect(auth.isSessionVerificationPending.value, isFalse);
      expect(api.identityChecks, 0);
      expect(api.clearCookieCalls, 1);
      expect(storage.stored, isNull);
    });

    test('signs out after Guest even if deleting the cookie fails', () async {
      storage.stored = cachedUser();
      final failingApi = _FailingClearCookiesApi()
        ..onGetLoggedUser = () async => jsonResponse({'message': 'Guest'});
      Get.replace<ApiProvider>(failingApi);
      final auth = AuthenticationController();
      addTearDown(auth.onClose);

      await auth.checkAuthenticationStatus();

      expect(failingApi.clearCookieCalls, 1);
      expect(storage.stored, isNull);
      expect(auth.currentUser.value, isNull);
      expect(auth.isAuthenticated.value, isFalse);
      expect(auth.isSessionVerificationPending.value, isFalse);
    });
  });

  group('cookie files at app start', () {
    const host = 'erp.example.com';
    const baseUrl = 'https://$host';
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    late Directory dir;
    late File hostFile;
    late List<int> originalHostBytes;
    late StorageService realStorage;
    late FakeStorageBox box;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('multimax_auth_cookies_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(pathProvider, (_) async => dir.path);
      addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));

      box = FakeStorageBox();
      realStorage = useStorageBox(box);
      await realStorage.saveBaseUrl(baseUrl);
      await realStorage.saveToken('saved token');

      final jar = PersistCookieJar(
        ignoreExpires: true,
        storage: FileStorage('${dir.path}/.cookies/'),
      );
      await jar.saveFromResponse(Uri.parse(baseUrl), [Cookie('sid', 'saved')]);
      hostFile = File('${dir.path}/.cookies/ie1_ps1/$host');
      originalHostBytes = await hostFile.readAsBytes();
    });

    final corruptionCases = [
      (
        file: host,
        bytes: [0xff],
        error: 'a host read error',
        withProfile: false,
      ),
      (
        file: host,
        bytes: '['.codeUnits,
        error: 'a malformed host file',
        withProfile: true,
      ),
      (
        file: '.index',
        bytes: '{'.codeUnits,
        error: 'a malformed cookie index',
        withProfile: true,
      ),
      (
        file: '.domains',
        bytes: '['.codeUnits,
        error: 'malformed domain cookies',
        withProfile: true,
      ),
    ];
    for (final corruption in corruptionCases) {
      test('preserves the session data after ${corruption.error}', () async {
        if (corruption.withProfile) await realStorage.saveUser(cachedUser());
        final unreadableFile =
            File('${hostFile.parent.path}/${corruption.file}');
        final originalBytes = await unreadableFile.exists()
            ? await unreadableFile.readAsBytes()
            : '{}'.codeUnits;
        await unreadableFile.writeAsBytes(corruption.bytes);
        final realApi = ApiProvider();
        await realApi.initDio();
        Get.replace<ApiProvider>(realApi);
        final auth = AuthenticationController();
        addTearDown(auth.onClose);

        await auth.checkAuthenticationStatus();

        final expectedEmail = corruption.withProfile ? kTestEmail : null;
        expect(auth.isAuthenticated.value, corruption.withProfile);
        expect(auth.isSessionVerificationPending.value, !corruption.withProfile);
        expect(auth.currentUser.value?.email, expectedEmail);
        expect(await unreadableFile.readAsBytes(), corruption.bytes);
        if (corruption.file != host) {
          expect(await hostFile.readAsBytes(), originalHostBytes);
        }
        expect(box.removedKeys, isEmpty);
        expect(realStorage.getUser()?.email, expectedEmail);
        expect(realStorage.getToken(), 'saved token');

        await unreadableFile.writeAsBytes(originalBytes);
        expect(await realApi.hasSessionCookies(), isTrue);
      });
    }

    test('preserves the cookie when the selected URL is empty', () async {
      final realApi = ApiProvider();
      await realApi.initDio();
      realApi.setBaseUrl('');
      Get.replace<ApiProvider>(realApi);
      final auth = AuthenticationController();
      addTearDown(auth.onClose);

      await auth.checkAuthenticationStatus();

      expect(auth.isSessionVerificationPending.value, isTrue);
      expect(await hostFile.readAsBytes(), originalHostBytes);
      expect(realStorage.getToken(), 'saved token');

      realApi.setBaseUrl(baseUrl);
      expect(await realApi.hasSessionCookies(), isTrue);
    });

    test('retries cookie initialization after a local directory error',
        () async {
      var directoryAvailable = false;
      var directoryRequests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (_) async {
        directoryRequests++;
        if (!directoryAvailable) {
          throw PlatformException(code: 'directory_unavailable');
        }
        return dir.path;
      });
      final realApi = ApiProvider();
      Get.replace<ApiProvider>(realApi);
      final auth = AuthenticationController();
      addTearDown(auth.onClose);

      await auth.checkAuthenticationStatus();

      expect(auth.isSessionVerificationPending.value, isTrue);
      expect(await hostFile.readAsBytes(), originalHostBytes);
      expect(realStorage.getToken(), 'saved token');
      expect(directoryRequests, 1);

      directoryAvailable = true;
      expect(await realApi.hasSessionCookies(), isTrue);
      expect(directoryRequests, 2);
    });
  });

  group('recovery after an unverified start', () {
    final transientAnswers = <String, Future<Response> Function()>{
      'a timeout': () async => throw networkError(),
      'a 503': () async => throw httpError(503),
      'a malformed answer': () async => jsonResponse({'message': []}),
    };
    for (final answer in transientAnswers.entries) {
      testWidgets('recovers without a cached profile after ${answer.key}',
          (tester) async {
        api.onGetLoggedUser = answer.value;
        final auth = AuthenticationController();
        addTearDown(auth.onClose);

        await auth.checkAuthenticationStatus();

        expect(auth.isAuthenticated.value, isFalse);
        expect(auth.isSessionVerificationPending.value, isTrue);
        expect(auth.isCheckingSession.value, isFalse);
        expect(api.identityChecks, 1);
        expect(api.hasCookies, isTrue);
        expect(storage.stored, isNull);

        api.onGetLoggedUser = () async => jsonResponse({'message': kTestEmail});
        await tester.pump(const Duration(seconds: 29));
        expect(api.identityChecks, 1);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(api.identityChecks, 2);
        expect(auth.isAuthenticated.value, isTrue);
        expect(auth.isSessionVerificationPending.value, isFalse);
        expect(auth.currentUser.value?.email, kTestEmail);
        expect(storage.stored?.email, kTestEmail);
        expect(api.clearCookieCalls, 0);

        await tester.pump(const Duration(minutes: 1));
        expect(api.identityChecks, 2);
      });
    }

    final rejectionAnswers = <String, Future<Response> Function()>{
      'Guest': () async => jsonResponse({'message': 'Guest'}),
      '401': () async => throw httpError(401),
    };
    for (final answer in rejectionAnswers.entries) {
      testWidgets('ends the pending session on ${answer.key}', (tester) async {
        api.onGetLoggedUser = () async => throw networkError();
        final auth = AuthenticationController();
        addTearDown(auth.onClose);
        await auth.checkAuthenticationStatus();
        expect(auth.isSessionVerificationPending.value, isTrue);

        api.onGetLoggedUser = answer.value;
        await tester.pump(const Duration(seconds: 30));
        await tester.pump();

        expect(auth.isAuthenticated.value, isFalse);
        expect(auth.isSessionVerificationPending.value, isFalse);
        expect(auth.currentUser.value, isNull);
        expect(storage.stored, isNull);
        expect(api.clearCookieCalls, 1);
        expect(api.hasCookies, isFalse);

        await tester.pump(const Duration(minutes: 1));
        expect(api.identityChecks, 2);
      });
    }

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
