import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;

import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';

// Focused coverage for HomeController.fetchActionableCounts — the "Upcoming &
// actionable" count strip (Task 3 of the 2026-07-16 dashboard-actionable-docs
// plan). The plan verified this method only via the full suite + on-device
// drive; the async orchestration (scope-flip race guard, access gating, and the
// per-(scope,email) cache) is exercised directly here.

/// ApiProvider fake: [getDocumentCount] returns a per-doctype Draft count and
/// records every query. Optional [mineGate]/[everyoneGate] completers let a test
/// hold a fetch mid-flight to reproduce the scope-flip race.
class _FakeApiProvider extends ApiProvider {
  /// Count returned for a doctype under mine scope (and the everyone fallback).
  final Map<String, int> counts = {};

  /// Count override for everyone-scope calls (filters carry no `owner`).
  final Map<String, int> everyoneCounts = {};

  /// When set, mine-/everyone-scope calls await the matching gate before
  /// resolving — lets a test complete overlapping fetches out of order.
  Completer<void>? mineGate;
  Completer<void>? everyoneGate;

  /// Every count query issued, in call order.
  final List<({String doctype, Map<String, dynamic>? filters})> queries = [];

  @override
  Future<Response> getDocumentCount(String doctype,
      {Map<String, dynamic>? filters}) async {
    queries.add((doctype: doctype, filters: filters));
    // Mine-scope filters carry an `owner` equality; everyone-scope don't.
    final isMine = filters?.containsKey('owner') ?? false;
    // Capture the value BEFORE awaiting the gate, so a later map mutation can't
    // change what an already-issued request resolves to.
    final value = (!isMine && everyoneCounts.containsKey(doctype))
        ? everyoneCounts[doctype]!
        : (counts[doctype] ?? 0);
    final gate = isMine ? mineGate : everyoneGate;
    if (gate != null) await gate.future;
    return Response(
      requestOptions:
          RequestOptions(path: '/api/method/frappe.client.get_count'),
      statusCode: 200,
      data: {'message': value},
    );
  }
}

/// PermissionService fake: [hasAccess] returns whatever [access] holds for a
/// doctype — `true`, `false`, or `null` (an unset entry reads back as `null`,
/// i.e. "still resolving").
class _FakePermissionService extends PermissionService {
  final Map<String, bool?> access = {};

  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => access[doctype];
}

/// Auth fake: neutralises the network `checkAuthenticationStatus()` that the
/// real onInit fires, while letting onInit's super-chain run normally.
/// [currentUser] is assigned directly by tests.
class _FakeAuthController extends AuthenticationController {
  @override
  Future<void> checkAuthenticationStatus() async {}
}

/// StorageService fake: never touches GetStorage. Only [getBaseUrl] is reached
/// (by ApiProvider._initDio during construction); everything else is unused.
class _FakeStorageService extends StorageService {
  _FakeStorageService() : super.withStorage(null);

  @override
  String? getBaseUrl() => null;
}

User _user(String email) =>
    User(id: email, name: email, email: email, roles: const []);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ApiProvider's constructor fires _initDio(), which touches path_provider
    // for the cookie-jar directory — stub it so construction doesn't throw in
    // this headless environment (mirrors todo_form_controller_test).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  late _FakeApiProvider api;
  late _FakePermissionService perm;
  late _FakeAuthController auth;
  late HomeController controller;

  setUp(() {
    // StorageService must precede ApiProvider: _initDio reads getBaseUrl in its
    // synchronous prologue during ApiProvider construction.
    Get.put<StorageService>(_FakeStorageService());
    api = _FakeApiProvider();
    Get.put<ApiProvider>(api);

    // The remaining providers only resolve ApiProvider in a field initializer —
    // real instances are inert for these tests, so register them as-is.
    Get.put<ItemProvider>(ItemProvider());
    Get.put<JobCardProvider>(JobCardProvider());
    Get.put<UserProvider>(UserProvider());
    Get.put<PosUploadProvider>(PosUploadProvider());
    Get.put<StockEntryProvider>(StockEntryProvider());
    Get.put<DeliveryNoteProvider>(DeliveryNoteProvider());
    Get.put<ToDoProvider>(ToDoProvider());
    Get.put<ScanService>(ScanService());
    // Real DataWedgeService: its onInit only sets up an EventChannel broadcast
    // stream, which is inert under the test binary messenger (no scans arrive).
    Get.put<DataWedgeService>(DataWedgeService());

    auth = _FakeAuthController();
    Get.put<AuthenticationController>(auth);
    perm = _FakePermissionService();
    Get.put<PermissionService>(perm);

    // Construct directly (not via Get.put) so HomeController.onInit — which
    // kicks off the dashboard load and registers the DataWedge scan worker —
    // never runs. Every field is resolved from the fakes above at construction.
    controller = HomeController();
  });

  tearDown(() => Get.deleteAll(force: true));

  /// Grants read on all four actionable DocTypes.
  void grantAll() {
    for (final c in kActionableDocConfigs) {
      perm.access[c.doctype] = true;
    }
  }

  /// Expected count map with every actionable DocType at [v].
  Map<String, int> allAt(int v) =>
      {for (final c in kActionableDocConfigs) c.doctype: v};

  /// A plain snapshot of the controller's reactive count map, for equality.
  Map<String, int> snapshot() =>
      Map<String, int>.from(controller.actionableCounts);

  group('fetchActionableCounts', () {
    group('scope-flip race guard', () {
      test('a stale fetch does not clobber the newer scope\'s counts or loading',
          () async {
        grantAll();
        auth.currentUser.value = _user('me@x.com'); // selectedFilterUser null
        for (final c in kActionableDocConfigs) {
          api.counts[c.doctype] = 1; // mine scope → 1
          api.everyoneCounts[c.doctype] = 9; // everyone scope → 9
        }
        api.mineGate = Completer<void>();
        api.everyoneGate = Completer<void>();

        // Fetch A under the current (mine) scope — left in flight.
        controller.actionableScope.value = ActionableScope.mine;
        final futA = controller.fetchActionableCounts(force: true);

        // The scope flips to everyone, then fetch B starts — also in flight.
        // Both fetches issued all their count queries synchronously (before
        // suspending on Future.wait), so A captured mine filters and B everyone.
        controller.actionableScope.value = ActionableScope.everyone;
        final futB = controller.fetchActionableCounts(force: true);

        // B (the current scope) resolves FIRST and wins.
        api.everyoneGate!.complete();
        await futB;
        expect(snapshot(), allAt(9));
        expect(controller.isLoadingActionable.value, isFalse);

        // A (now stale) resolves LAST — its `scope == actionableScope.value`
        // guards must drop the result rather than overwrite everyone's counts
        // or re-toggle the loading flag.
        api.mineGate!.complete();
        await futA;
        expect(snapshot(), allAt(9),
            reason: 'stale mine-scope fetch must not overwrite everyone counts');
        expect(controller.isLoadingActionable.value, isFalse);
      });

      test('a stale fetch resolving mid-flight does not clear loading early',
          () async {
        grantAll();
        auth.currentUser.value = _user('me@x.com');
        for (final c in kActionableDocConfigs) {
          api.counts[c.doctype] = 1;
          api.everyoneCounts[c.doctype] = 9;
        }
        api.mineGate = Completer<void>();
        api.everyoneGate = Completer<void>();

        controller.actionableScope.value = ActionableScope.mine;
        final futA = controller.fetchActionableCounts(force: true);
        controller.actionableScope.value = ActionableScope.everyone;
        final futB = controller.fetchActionableCounts(force: true);

        // The stale (mine) fetch completes while the current (everyone) fetch is
        // still in flight. Its finally-block guard must leave loading = true.
        api.mineGate!.complete();
        await futA;
        expect(controller.isLoadingActionable.value, isTrue,
            reason: 'current everyone fetch is still loading');
        expect(snapshot(), isEmpty,
            reason: 'stale fetch must not publish counts for the newer scope');

        // Once the current fetch resolves it publishes its counts and clears
        // loading.
        api.everyoneGate!.complete();
        await futB;
        expect(snapshot(), allAt(9));
        expect(controller.isLoadingActionable.value, isFalse);
      });
    });

    group('access gating', () {
      test('only readable DocTypes are queried and appear as keys', () async {
        controller.selectedFilterUser.value = _user('a@b.com');
        perm.access['Purchase Order'] = true;
        perm.access['Purchase Receipt'] = false; // denied
        perm.access['Stock Entry'] = null; // still resolving
        perm.access['Delivery Note'] = true;
        api.counts['Purchase Order'] = 3;
        api.counts['Delivery Note'] = 7;

        await controller.fetchActionableCounts(force: true);

        // Denied (false) and unresolved (null) DocTypes are absent as keys...
        expect(snapshot(), {'Purchase Order': 3, 'Delivery Note': 7});
        expect(controller.actionableCounts.containsKey('Purchase Receipt'),
            isFalse);
        expect(
            controller.actionableCounts.containsKey('Stock Entry'), isFalse);
        // ...and were never queried (no 403-triggering requests).
        expect(api.queries.map((q) => q.doctype).toList(),
            ['Purchase Order', 'Delivery Note']);
      });

      test('a null (unresolved) access is treated as no-access', () async {
        controller.selectedFilterUser.value = _user('a@b.com');
        for (final c in kActionableDocConfigs) {
          perm.access[c.doctype] = null; // nothing resolved yet
          api.counts[c.doctype] = 5;
        }

        await controller.fetchActionableCounts(force: true);

        expect(snapshot(), isEmpty);
        expect(api.queries, isEmpty);
        expect(controller.isLoadingActionable.value, isFalse);
      });
    });

    group('cache keying', () {
      test('mine scope caches per email; a different user is a cache miss',
          () async {
        grantAll();
        controller.actionableScope.value = ActionableScope.mine;
        controller.selectedFilterUser.value = _user('a@b.com');
        for (final c in kActionableDocConfigs) {
          api.counts[c.doctype] = 5;
        }

        await controller.fetchActionableCounts(force: true);
        expect(snapshot(), allAt(5));
        expect(api.queries.length, kActionableDocConfigs.length);

        // Same user, no force → served from the `mine::a@b.com` cache, so a
        // count change is NOT observed and no new query is issued.
        for (final c in kActionableDocConfigs) {
          api.counts[c.doctype] = 9;
        }
        await controller.fetchActionableCounts();
        expect(snapshot(), allAt(5), reason: 'served from cache');
        expect(api.queries.length, kActionableDocConfigs.length,
            reason: 'no refetch on a cache hit');

        // Different user → different `mine::<email>` key → cache miss → refetch.
        controller.selectedFilterUser.value = _user('c@d.com');
        await controller.fetchActionableCounts();
        expect(snapshot(), allAt(9));
        expect(api.queries.length, kActionableDocConfigs.length * 2);
      });

      test('everyone scope cache is user-independent (keyed by `all`)',
          () async {
        grantAll();
        controller.actionableScope.value = ActionableScope.everyone;
        controller.selectedFilterUser.value = _user('a@b.com');
        for (final c in kActionableDocConfigs) {
          api.counts[c.doctype] = 4;
        }

        await controller.fetchActionableCounts(force: true);
        expect(snapshot(), allAt(4));
        final queriesAfterFirst = api.queries.length;

        // Switch the viewed user and change the counts; everyone collapses to
        // the single `all` bucket, so this is a cache hit — no new query, and
        // the counts stay put.
        for (final c in kActionableDocConfigs) {
          api.counts[c.doctype] = 9;
        }
        controller.selectedFilterUser.value = _user('c@d.com');
        await controller.fetchActionableCounts();
        expect(snapshot(), allAt(4), reason: 'everyone is user-independent');
        expect(api.queries.length, queriesAfterFirst,
            reason: 'no refetch: same `all` cache key');
      });

      test('force clears the cache and refetches', () async {
        grantAll();
        controller.actionableScope.value = ActionableScope.mine;
        controller.selectedFilterUser.value = _user('a@b.com');
        for (final c in kActionableDocConfigs) {
          api.counts[c.doctype] = 4;
        }

        await controller.fetchActionableCounts(force: true);
        expect(snapshot(), allAt(4));
        expect(api.queries.length, kActionableDocConfigs.length);

        // Change the counts and force → cache cleared, so the new values land.
        for (final c in kActionableDocConfigs) {
          api.counts[c.doctype] = 9;
        }
        await controller.fetchActionableCounts(force: true);
        expect(snapshot(), allAt(9));
        expect(api.queries.length, kActionableDocConfigs.length * 2);
      });
    });
  });
}
