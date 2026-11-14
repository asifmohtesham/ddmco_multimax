import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;

import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';

// Seen on-device: ~300 ms after POST /api/method/logout returned 200 the app
// fired a burst of `frappe.client.get_list` permission probes, one per
// DocTypeGuard on the still-mounted Dashboard, and every one came back 403.
//
// Cause: clearing PermissionService's reactive cache notifies every mounted
// guard; each rebuilds, misses the cache, and lazily re-probes — with the
// session already gone. These tests pin both halves of the fix: no probe
// without a session, and no result from an old session written into a new one.

/// The DocTypes the Dashboard reads, i.e. the ones in the observed burst.
const _dashboardDoctypes = [
  'ToDo',
  'Attendance',
  'Stock Entry',
  'Delivery Note',
  'Purchase Receipt',
  'Packing Slip',
  'POS Upload',
  'BOM',
  'Work Order',
  'Job Card',
];

/// ApiProvider fake modelling the server session: probes succeed while
/// [hasSession], and fail 403 once it is cleared — as Frappe does for Guest.
class _FakeApiProvider extends ApiProvider {
  bool hasSession = true;

  /// Whether the signed-in user may read what is probed. A denied probe is
  /// answered 403 too, exactly like a missing session.
  bool grants = true;

  /// Every permission probe issued, in call order.
  final List<String> probes = [];

  /// Probes issued while there was no session — the bug.
  final List<String> probesWithoutSession = [];

  /// When a doctype has an entry, its probe awaits it before resolving — lets
  /// a test hold a probe in flight across a session change.
  final Map<String, Completer<void>> gates = {};

  @override
  Future<Response> hasPermission(String doctype, String permType) async {
    probes.add(doctype);
    // Capture the session BEFORE awaiting the gate: a request is answered for
    // the session it was sent with, not the one current when it lands.
    final sentWithSession = hasSession;
    final granted = hasSession && grants;
    if (!sentWithSession) probesWithoutSession.add(doctype);
    final gate = gates[doctype];
    if (gate != null) await gate.future;
    final options =
        RequestOptions(path: '/api/method/frappe.client.get_list');
    if (!granted) {
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 403),
        type: DioExceptionType.badResponse,
      );
    }
    return Response(
      requestOptions: options,
      statusCode: 200,
      data: {'message': <dynamic>[]},
    );
  }

  @override
  Future<Response> logoutApiCall({CancelToken? cancelToken}) async => Response(
        requestOptions: RequestOptions(path: '/api/method/logout'),
        statusCode: 200,
      );

  @override
  Future<void> clearSessionCookies() async => hasSession = false;
}

/// Auth fake: neutralises the network `checkAuthenticationStatus()` that the
/// real onInit fires. Logout itself is the real implementation.
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

User _user(String email) =>
    User(id: email, name: email, email: email, roles: const []);

/// Stand-in for the Dashboard: one guard per DocType it reads.
class _Dashboard extends StatelessWidget {
  const _Dashboard();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          for (final d in _dashboardDoctypes)
            DocTypeGuard(doctype: d, child: Text('tile $d')),
          TextButton(
            onPressed: () => Get.find<AuthenticationController>().logoutUser(),
            child: const Text('open logout'),
          ),
        ],
      ),
    );
  }
}

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
  late PermissionService perm;

  setUp(() {
    // StorageService must precede ApiProvider: _initDio reads getBaseUrl.
    Get.put<StorageService>(_FakeStorageService());
    api = _FakeApiProvider();
    Get.put<ApiProvider>(api);
    perm = Get.put<PermissionService>(PermissionService());
    auth = _FakeAuthController();
    Get.put<AuthenticationController>(auth);
  });

  tearDown(() => Get.deleteAll(force: true));

  /// Puts [auth] in the signed-in state login leaves it in.
  void signIn(String email, {bool grants = true}) {
    api.hasSession = true;
    api.grants = grants;
    auth.currentUser.value = _user(email);
    auth.isAuthenticated.value = true;
  }

  List<({String doctype, String permType})> readEntries() =>
      [for (final d in _dashboardDoctypes) (doctype: d, permType: 'read')];

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: AppRoutes.HOME,
      getPages: [
        GetPage(name: AppRoutes.HOME, page: () => const _Dashboard()),
        GetPage(
          name: AppRoutes.LOGIN,
          page: () => const Scaffold(body: Text('login screen')),
        ),
      ],
    ));
    await tester.pumpAndSettle();
  }

  group('after logout', () {
    testWidgets('mounted guards do not probe once the session is cleared',
        (tester) async {
      signIn('picker@multimax.cloud');
      await perm.prefetchAll(readEntries());
      await pumpDashboard(tester);
      expect(find.text('tile Stock Entry'), findsOneWidget);
      final probesWhileSignedIn = api.probes.length;

      await tester.tap(find.text('open logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.text('login screen'), findsOneWidget);
      expect(api.probesWithoutSession, isEmpty,
          reason: 'permission probes were issued with no session');
      expect(api.probes.length, probesWhileSignedIn);
    });

    testWidgets('guards fail closed rather than showing stale access',
        (tester) async {
      signIn('picker@multimax.cloud');
      await perm.prefetchAll(readEntries());
      await pumpDashboard(tester);

      // Session expiry: cleared in place, with no navigation to tear the
      // Dashboard down.
      api.hasSession = false;
      auth.currentUser.value = null;
      auth.isAuthenticated.value = false;
      perm.clearCache();
      await tester.pumpAndSettle();

      expect(find.text('tile Stock Entry'), findsNothing);
      expect(api.probesWithoutSession, isEmpty);
    });
  });

  group('across a session change', () {
    /// Signs the current user out in place, as `_clearSessionAndLocalData`
    /// does.
    void signOut() {
      api.hasSession = false;
      auth.currentUser.value = null;
      auth.isAuthenticated.value = false;
      perm.clearCache();
    }

    /// Signs [email] in and prefetches Stock Entry, as login does.
    Future<void> signInAndPrefetch(String email, {required bool grants}) async {
      signIn(email, grants: grants);
      perm.clearCache();
      await perm.prefetchAll(const [
        (doctype: 'Stock Entry', permType: 'read'),
      ]);
    }

    test("a slow grant for the last user cannot reach the next user",
        () async {
      // User A may read Stock Entry; the probe is slow (patchy warehouse
      // WiFi) and outlives A's session.
      signIn('a@multimax.cloud');
      final gate = api.gates['Stock Entry'] = Completer<void>();
      expect(perm.hasAccess('Stock Entry'), isNull);
      signOut();

      // B, who may NOT read it, signs in on the same handheld.
      api.gates.clear();
      await signInAndPrefetch('b@multimax.cloud', grants: false);
      expect(perm.hasAccess('Stock Entry'), isFalse);

      // A's answer finally lands.
      gate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(perm.hasAccess('Stock Entry'), isFalse,
          reason: "the previous user's grant leaked into this session");
    });

    test('a slow 403 for the last user cannot deny the next user', () async {
      signIn('a@multimax.cloud', grants: false);
      final gate = api.gates['Stock Entry'] = Completer<void>();
      expect(perm.hasAccess('Stock Entry'), isNull);
      signOut();

      api.gates.clear();
      await signInAndPrefetch('b@multimax.cloud', grants: true);
      expect(perm.hasAccess('Stock Entry'), isTrue);

      gate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(perm.hasAccess('Stock Entry'), isTrue,
          reason: "the previous user's 403 denied this session");
    });

    test('signed out reads as denied, and is not carried into the next login',
        () async {
      await signInAndPrefetch('a@multimax.cloud', grants: true);
      signOut();
      expect(perm.hasAccess('Stock Entry'), isFalse);

      await signInAndPrefetch('b@multimax.cloud', grants: true);

      expect(perm.hasAccess('Stock Entry'), isTrue);
      expect(api.probesWithoutSession, isEmpty);
    });
  });
}
