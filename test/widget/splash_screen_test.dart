// test/widget/splash_screen_test.dart
import 'dart:async';
import 'dart:io' show Directory, File, FileSystemException;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_pages.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/session_cookie_jar.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/auth/splash/splash_screen.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:path/path.dart' as p;

import '../helpers/auth_fakes.dart';

class _CookieCheckingApi extends FakeApiProvider {
  _CookieCheckingApi(this._cookieApi);

  final ApiProvider _cookieApi;

  @override
  Future<bool> hasSessionCookies() => _cookieApi.hasSessionCookies();
}

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
  Future<void> launch(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: buildAppTheme(AppScheme.light, Brightness.light),
      darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
      themeMode: themeMode,
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

  testWidgets('retries a cookie read error and opens Home with the saved SID',
      (tester) async {
    const host = 'erp.example.com';
    const baseUrl = 'https://$host';
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final directory = Directory.systemTemp.createTempSync('splash_cookies_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final cookiePath = p.join(directory.path, '.cookies');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => directory.path,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));

    await tester.runAsync(() async {
      final jar = createSessionCookieJar(cookiePath);
      await jar.saveFromResponse(Uri.parse(baseUrl), [Cookie('sid', 'saved')]);
    });
    Map<String, List<int>> cookieFiles() => {
          for (final file in Directory(p.join(cookiePath, 'ie1_ps1'))
              .listSync()
              .whereType<File>())
            p.basename(file.path): file.readAsBytesSync(),
        };
    final savedFiles = cookieFiles();
    expect(savedFiles.keys, unorderedEquals(['.index', host]));

    final profileStorage = StorageService.withStorage(FakeStorageBox());
    await profileStorage.saveBaseUrl(baseUrl);
    Get.replace<StorageService>(profileStorage);
    var locked = true;
    var hostReads = 0;
    final cookieApi = ApiProvider(
      cookieJarFactory: (directory) => createSessionCookieJar(
        directory,
        readFile: (file) async {
          if (p.basename(file.path) == host) {
            hostReads++;
            if (locked) throw FileSystemException('File is locked', file.path);
          }
          return file.readAsBytesSync();
        },
      ),
    );
    api = _CookieCheckingApi(cookieApi);
    Get.replace<ApiProvider>(api);
    auth = AuthenticationController();
    Get.replace<AuthenticationController>(auth);

    await launch(tester);
    await tester.pumpAndSettle();

    expect(auth.isSessionVerificationPending.value, isTrue);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('login screen'), findsNothing);
    expect(api.identityChecks, 0);
    expect(api.clearCookieCalls, 0);
    expect(hostReads, 1);
    expect(cookieFiles(), savedFiles);

    locked = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(hostReads, 2);
    expect(api.identityChecks, 1);
    expect(auth.isSessionVerificationPending.value, isFalse);
    expect(find.text('home screen'), findsOneWidget);
    expect(profileStorage.getUser()?.email, kTestEmail);
    expect(cookieFiles(), savedFiles);
  });

  final inconclusiveAnswers = <String, Future<Response> Function()>{
    'a timeout': () async => throw networkError(),
    'HTTP 503': () async => throw httpError(503),
    'a malformed response': () async => jsonResponse({'message': []}),
  };

  for (final initial in inconclusiveAnswers.entries) {
    testWidgets('retries after ${initial.key} and opens Home without a login',
        (tester) async {
      api.onGetLoggedUser = () => api.identityChecks == 1
          ? initial.value()
          : Future.value(jsonResponse({'message': kTestEmail}));

      await launch(tester);
      await tester.pumpAndSettle();

      expect(find.text("Can't reach the server."), findsOneWidget);
      expect(find.text('login screen'), findsNothing);
      expect(storage.stored, isNull);
      expect(api.hasCookies, isTrue);

      await tester.pump(const Duration(seconds: 29));
      expect(api.identityChecks, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(api.identityChecks, 2);
      expect(find.text('home screen'), findsOneWidget);
      expect(find.text('login screen'), findsNothing);
      expect(storage.stored?.email, kTestEmail);
      expect(api.clearCookieCalls, 0);
    });
  }

  final rejectionAnswers = <String, Future<Response> Function()>{
    'Guest': () async => jsonResponse({'message': 'Guest'}),
    'HTTP 401': () async => throw httpError(401),
  };

  for (final rejection in rejectionAnswers.entries) {
    testWidgets('clears the session and opens Login after a retry returns '
        '${rejection.key}', (tester) async {
      api.onGetLoggedUser = () => api.identityChecks == 1
          ? Future.error(networkError())
          : rejection.value();

      await launch(tester);
      await tester.pumpAndSettle();
      expect(find.text("Can't reach the server."), findsOneWidget);
      expect(find.text('login screen'), findsNothing);
      expect(api.clearCookieCalls, 0);

      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(api.identityChecks, 2);
      expect(find.text('login screen'), findsOneWidget);
      expect(find.text('home screen'), findsNothing);
      expect(api.clearCookieCalls, 1);
      expect(api.hasCookies, isFalse);
      expect(storage.stored, isNull);
    });
  }

  testWidgets('opens Home with a valid cookie and a corrupt cached profile',
      (tester) async {
    final box = FakeStorageBox();
    box.values['currentUser'] = 'bad profile';
    final profileStorage = StorageService.withStorage(box);
    Get.replace<StorageService>(profileStorage);

    await launch(tester);
    await tester.pumpAndSettle();

    expect(find.text('home screen'), findsOneWidget);
    expect(find.text('login screen'), findsNothing);
    expect(box.removedKeys, ['currentUser']);
    expect(profileStorage.getUser()?.email, kTestEmail);
    expect(api.clearCookieCalls, 0);
  });

  testWidgets('dark Splash shows a guarded Retry and a way to go to Login',
      (tester) async {
    final retryAnswer = Completer<Response>();
    api.onGetLoggedUser = () => api.identityChecks == 1
        ? Future.error(networkError())
        : retryAnswer.future;

    await launch(tester, themeMode: ThemeMode.dark);
    await tester.pumpAndSettle();

    final heading = find.text("Can't reach the server.");
    final detail = find.text('We’ll retry automatically.');
    final retry = find.byType(FilledButton);
    final goToLogin = find.widgetWithText(TextButton, 'Go to Login');
    final theme = Theme.of(tester.element(heading));

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppScheme.dark.bg);
    expect(tester.widget<Text>(heading).style?.color, AppScheme.dark.text);
    expect(tester.widget<Text>(detail).style?.color, AppScheme.dark.textMuted);
    expect(tester.widget<TextButton>(goToLogin).onPressed, isNotNull);

    // A second event before the disabled button has repainted must be guarded.
    final onRetry = tester.widget<FilledButton>(retry).onPressed!;
    await tester.tap(find.text('Retry'));
    onRetry();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(api.identityChecks, 2);
    final busyButton = tester.widget<FilledButton>(retry);
    expect(busyButton.onPressed, isNull);
    expect(find.text('Checking…'), findsOneWidget);
    final progress = find.descendant(
      of: retry,
      matching: find.byType(CircularProgressIndicator),
    );
    expect(progress, findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(progress).color,
        theme.colorScheme.onPrimary);
    expect(busyButton.style?.backgroundColor?.resolve({WidgetState.disabled}),
        theme.colorScheme.primary);
    expect(tester.widget<TextButton>(goToLogin).onPressed, isNull);

    retryAnswer.completeError(networkError());
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
    expect(progress, findsNothing);
    await tester.tap(goToLogin);
    await tester.pumpAndSettle();

    expect(find.text('login screen'), findsOneWidget);
    expect(api.clearCookieCalls, 0);
    expect(api.hasCookies, isTrue);
    await tester.pump(const Duration(minutes: 1));
    expect(api.identityChecks, 2);
  });
}
