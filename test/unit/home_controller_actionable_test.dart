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

  /// Rows [getDocumentList] returns for a doctype, keyed by doctype. A test
  /// sets this before triggering a fetch; missing entries return an empty list.
  final Map<String, List<Map<String, dynamic>>> listRows = {};

  /// Per-doctype completers: when a doctype has an entry here, its
  /// [getDocumentList] call awaits the completer before resolving — lets a
  /// test hold two overlapping preview fetches in flight and resolve them out
  /// of order to reproduce the stale-selection race.
  final Map<String, Completer<void>> listGates = {};

  /// Doctypes whose [getDocumentList] call throws instead of resolving —
  /// reproduces a mid-fetch network/API error.
  final Set<String> throwingDoctypes = {};

  /// Every [getDocumentList] query issued, in call order.
  final List<({String doctype, Map<String, dynamic>? filters})> listQueries =
      [];

  @override
  Future<Response> getDocumentList(
    String doctype, {
    int limit = 20,
    int limitStart = 0,
    List<String>? fields,
    String? groupBy = '',
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
    Map<String, dynamic>? orFilters,
    List<List<dynamic>>? orFilterTuples,
    String orderBy = 'modified desc',
  }) async {
    listQueries.add((doctype: doctype, filters: filters));
    // Capture the rows BEFORE awaiting the gate, so a later map mutation
    // can't change what an already-issued request resolves to.
    final rows = listRows[doctype] ?? const <Map<String, dynamic>>[];
    final gate = listGates[doctype];
    if (gate != null) await gate.future;
    if (throwingDoctypes.contains(doctype)) {
      throw Exception('Simulated getDocumentList failure for $doctype');
    }
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/$doctype'),
      statusCode: 200,
      data: {'data': rows},
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

  // setActionableScope persists the flipped scope via this — the real
  // implementation writes through the (null, in this fake) GetStorage box.
  @override
  Future<void> saveDashboardActionableScope(String value) async {}
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

  // GetX runs onClose synchronously when the route is disposed, while the
  // Dashboard can still rebuild once more; its scan box then re-attaches to
  // barcodeController. Disposing it in onClose crashed logout ("used after
  // being disposed" → '_dependents.isEmpty' red screen).
  test('onClose leaves barcodeController usable for a still-mounted scan box',
      () {
    controller.onClose();
    expect(() => controller.barcodeController.addListener(() {}),
        returnsNormally);
  });

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

  /// A Purchase Order preview row — matches its config's previewFields
  /// (`name`, `supplier`, `transaction_date`, `owner`).
  Map<String, dynamic> poRow(String name,
          {String supplier = 'Acme', String owner = 'a@b.com'}) =>
      {
        'name': name,
        'supplier': supplier,
        'transaction_date': '2026-07-10',
        'owner': owner,
      };

  /// A Delivery Note preview row — matches its config's previewFields
  /// (`name`, `customer`, `posting_date`, `owner`).
  Map<String, dynamic> dnRow(String name,
          {String customer = 'Beta Co', String owner = 'a@b.com'}) =>
      {
        'name': name,
        'customer': customer,
        'posting_date': '2026-07-11',
        'owner': owner,
      };

  /// Flushes the microtask queue so a fire-and-forget `fetchPreviewDocs()`
  /// call (launched via `selectActionable`, which is `void` and cannot be
  /// awaited directly) has a chance to run to completion. `Future.delayed`
  /// schedules a Timer, and Dart drains the entire microtask queue before any
  /// Timer callback fires, so this deterministically waits out any pending
  /// `await` chain rather than racing a fixed delay.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

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

  group('fetchPreviewDocs', () {
    group('stale-selection race guard', () {
      test(
          'a stale doctype fetch does not clobber the newer selection\'s '
          'docs or loading', () async {
        controller.selectedFilterUser.value = _user('a@b.com');
        api.listRows['Purchase Order'] = [poRow('PO-0001')];
        api.listRows['Delivery Note'] = [dnRow('DN-0001')];
        api.listGates['Purchase Order'] = Completer<void>();
        api.listGates['Delivery Note'] = Completer<void>();

        // Fetch A: select Purchase Order — starts a gated fetch, left in
        // flight (selectActionable is void, so the fetch runs fire-and-forget;
        // it still executes synchronously up to its first await).
        controller.selectActionable('Purchase Order');
        expect(controller.isLoadingPreview.value, isTrue);

        // The selection flips to Delivery Note before A resolves — fetch B
        // starts, also gated.
        controller.selectActionable('Delivery Note');
        expect(controller.isLoadingPreview.value, isTrue);

        // B (the current selection) resolves FIRST and wins.
        api.listGates['Delivery Note']!.complete();
        await flush();
        expect(controller.previewDocs.map((r) => r.name).toList(),
            ['DN-0001']);
        expect(controller.isLoadingPreview.value, isFalse);

        // A (now stale) resolves LAST — its `doctype == selectedActionable.value`
        // guard must drop the result rather than overwrite Delivery Note's
        // preview or re-toggle the loading flag.
        api.listGates['Purchase Order']!.complete();
        await flush();
        expect(controller.previewDocs.map((r) => r.name).toList(),
            ['DN-0001'],
            reason:
                'stale Purchase Order fetch must not overwrite Delivery Note preview');
        expect(controller.isLoadingPreview.value, isFalse);
      });

      test('a stale fetch resolving mid-flight does not clear loading early',
          () async {
        controller.selectedFilterUser.value = _user('a@b.com');
        api.listRows['Purchase Order'] = [poRow('PO-0001')];
        api.listRows['Delivery Note'] = [dnRow('DN-0001')];
        api.listGates['Purchase Order'] = Completer<void>();
        api.listGates['Delivery Note'] = Completer<void>();

        controller.selectActionable('Purchase Order');
        controller.selectActionable('Delivery Note');

        // The stale (Purchase Order) fetch completes while the current
        // (Delivery Note) fetch is still in flight. Its guarded finally-block
        // must leave loading = true and must not publish its docs.
        api.listGates['Purchase Order']!.complete();
        await flush();
        expect(controller.isLoadingPreview.value, isTrue,
            reason: 'current Delivery Note fetch is still loading');
        expect(controller.previewDocs, isEmpty,
            reason:
                'stale fetch must not publish docs for the newer selection');

        // Once the current fetch resolves it publishes its docs and clears
        // loading.
        api.listGates['Delivery Note']!.complete();
        await flush();
        expect(controller.previewDocs.map((r) => r.name).toList(),
            ['DN-0001']);
        expect(controller.isLoadingPreview.value, isFalse);
      });
    });

    test(
        'selecting ToDo with a doc fetch in flight synchronously clears docs '
        'and leaves loading false', () async {
      controller.selectedFilterUser.value = _user('a@b.com');
      api.listRows['Purchase Order'] = [poRow('PO-0001')];
      api.listGates['Purchase Order'] = Completer<void>();

      controller.selectActionable('Purchase Order');
      expect(controller.isLoadingPreview.value, isTrue);

      // ToDo needs no fetch — the early return clears docs and loading
      // synchronously, without waiting on the in-flight Purchase Order fetch.
      controller.selectActionable('ToDo');
      expect(controller.previewDocs, isEmpty);
      expect(controller.isLoadingPreview.value, isFalse);

      // The stale Purchase Order fetch resolving afterwards must not
      // resurrect docs or loading: its `doctype == selectedActionable.value`
      // guard fails ('Purchase Order' != 'ToDo').
      api.listGates['Purchase Order']!.complete();
      await flush();
      expect(controller.previewDocs, isEmpty);
      expect(controller.isLoadingPreview.value, isFalse);
    });

    group('cache keying', () {
      test(
          're-fetching the same selection serves from cache; force clears '
          'and refetches', () async {
        controller.selectedFilterUser.value = _user('a@b.com');
        api.listRows['Purchase Order'] = [poRow('PO-0001')];

        controller.selectActionable('Purchase Order');
        await flush();
        expect(
            controller.previewDocs.map((r) => r.name).toList(), ['PO-0001']);
        expect(api.listQueries.length, 1);

        // Change the underlying data and re-fetch without force (mirrors the
        // re-fetch setActionableScope issues for an unchanged selection):
        // served from the cache, so no new query and the stale data change
        // is NOT observed.
        api.listRows['Purchase Order'] = [poRow('PO-9999')];
        await controller.fetchPreviewDocs();
        expect(
            controller.previewDocs.map((r) => r.name).toList(), ['PO-0001'],
            reason: 'served from cache');
        expect(api.listQueries.length, 1, reason: 'no refetch on a cache hit');

        // force=true clears the cache, so the new data lands.
        await controller.fetchPreviewDocs(force: true);
        expect(
            controller.previewDocs.map((r) => r.name).toList(), ['PO-9999']);
        expect(api.listQueries.length, 2);
      });

      test('a different viewed user under mine scope is a cache miss',
          () async {
        controller.actionableScope.value = ActionableScope.mine;
        controller.selectedFilterUser.value = _user('a@b.com');
        api.listRows['Purchase Order'] = [poRow('PO-0001')];

        controller.selectActionable('Purchase Order');
        await flush();
        expect(api.listQueries.length, 1);

        controller.selectedFilterUser.value = _user('c@d.com');
        api.listRows['Purchase Order'] = [poRow('PO-2222')];
        await controller.fetchPreviewDocs();
        expect(
            controller.previewDocs.map((r) => r.name).toList(), ['PO-2222']);
        expect(api.listQueries.length, 2,
            reason: 'different viewed user -> different cache key -> refetch');
      });

      // Fix 1 regression: the early ToDo/null return in fetchPreviewDocs used
      // to run BEFORE the cache clear, so a force refresh while 'ToDo' is
      // selected (exactly what _applyDefaultSelection triggers whenever the
      // default selection resolves to Tasks) never cleared _previewCache.
      // Re-selecting a doctype afterwards would then silently serve stale
      // rows instead of refetching.
      test(
          'a force refresh while ToDo is selected still clears the preview '
          'cache, so re-selecting a doctype refetches', () async {
        controller.selectedFilterUser.value = _user('a@b.com');
        api.listRows['Purchase Order'] = [poRow('PO-0001')];

        // Select and cache Purchase Order's rows.
        controller.selectActionable('Purchase Order');
        await flush();
        expect(
            controller.previewDocs.map((r) => r.name).toList(), ['PO-0001']);
        expect(api.listQueries.length, 1);

        // Return to Tasks — ToDo needs no fetch, so this only clears state.
        controller.selectActionable('ToDo');
        expect(controller.previewDocs, isEmpty);

        // Force-refresh while ToDo is selected — mirrors what
        // _applyDefaultSelection does when the resolved default is 'ToDo'.
        await controller.fetchPreviewDocs(force: true);
        expect(controller.previewDocs, isEmpty);
        expect(api.listQueries.length, 1, reason: 'ToDo issues no doc fetch');

        // Change the underlying data and re-select Purchase Order: if the
        // cache had NOT been cleared, this would silently serve the stale
        // PO-0001 row with no new query.
        api.listRows['Purchase Order'] = [poRow('PO-9999')];
        controller.selectActionable('Purchase Order');
        await flush();
        expect(
            controller.previewDocs.map((r) => r.name).toList(), ['PO-9999']);
        expect(api.listQueries.length, 2,
            reason:
                'cache must have been cleared by the force refresh while ToDo '
                'was selected');
      });
    });

    // Fix 3 regression: on a non-cached fetch, previewDocs was only
    // reassigned on SUCCESS — a thrown getDocumentList left the previously
    // selected doctype's rows on screen under the newly selected chip.
    group('error handling', () {
      test(
          'a thrown fetch clears the previous selection\'s rows instead of '
          'leaving them on screen', () async {
        controller.selectedFilterUser.value = _user('a@b.com');
        api.listRows['Purchase Order'] = [poRow('PO-0001')];
        api.throwingDoctypes.add('Delivery Note');

        // Select Purchase Order — its rows land normally.
        controller.selectActionable('Purchase Order');
        await flush();
        expect(
            controller.previewDocs.map((r) => r.name).toList(), ['PO-0001']);
        expect(controller.isLoadingPreview.value, isFalse);

        // Select Delivery Note — its fetch throws.
        controller.selectActionable('Delivery Note');
        await flush();

        expect(controller.previewDocs, isEmpty,
            reason:
                'a thrown fetch must not leave Purchase Order\'s rows on '
                'screen under the Delivery Note chip');
        expect(controller.isLoadingPreview.value, isFalse);
      });
    });

    test('a fetched row is mapped via docRowFor with an owner label in the subtitle',
        () async {
      controller.selectedFilterUser.value = _user('a@b.com');
      api.listRows['Purchase Order'] =
          [poRow('PO-0001', supplier: 'Acme', owner: 'jawwad@x.com')];

      controller.selectActionable('Purchase Order');
      await flush();

      expect(controller.previewDocs, hasLength(1));
      expect(controller.previewDocs.first.name, 'PO-0001');
      // ownerLabelFor falls back to the email's local part when the owner is
      // not in namesByEmail (userList is empty in this test setup).
      expect(controller.previewDocs.first.subtitle, contains('jawwad'));
    });
  });

  // Fix 2 regression: setActionableScope used to fire fetchActionableCounts +
  // fetchPreviewDocs without re-applying the default selection. If the
  // selected doctype's count dropped to 0 under the new scope, the chip
  // stayed selected while rendering muted/inert, and the preview collapsed
  // to empty with no fallback chip chosen.
  group('setActionableScope', () {
    test(
        're-selects the first chip that still has work when the current '
        'selection drops to zero under the new scope', () async {
      grantAll();
      auth.currentUser.value = _user('me@x.com'); // selectedFilterUser null
      controller.actionableScope.value = ActionableScope.everyone;

      // Under everyone scope only Purchase Order has work.
      for (final c in kActionableDocConfigs) {
        api.everyoneCounts[c.doctype] = 0;
      }
      api.everyoneCounts['Purchase Order'] = 5;
      await controller.fetchActionableCounts(force: true);
      controller.selectActionable('Purchase Order');
      expect(controller.selectedActionable.value, 'Purchase Order');

      // Under mine scope, Purchase Order has zero work, but Delivery Note
      // (later in kActionableDocConfigs) does.
      for (final c in kActionableDocConfigs) {
        api.counts[c.doctype] = 0;
      }
      api.counts['Delivery Note'] = 2;

      await controller.setActionableScope(ActionableScope.mine);

      expect(controller.actionableScope.value, ActionableScope.mine);
      expect(controller.selectedActionable.value, 'Delivery Note',
          reason:
              'Purchase Order has zero work under mine scope; the first '
              'chip that still has work must be selected instead, not left '
              'on the now-zero doctype');
    });

    test('selects null when no chip has work under the new scope', () async {
      grantAll();
      auth.currentUser.value = _user('me@x.com');
      controller.actionableScope.value = ActionableScope.everyone;

      for (final c in kActionableDocConfigs) {
        api.everyoneCounts[c.doctype] = 0;
      }
      api.everyoneCounts['Purchase Order'] = 5;
      await controller.fetchActionableCounts(force: true);
      controller.selectActionable('Purchase Order');
      expect(controller.selectedActionable.value, 'Purchase Order');

      // Nothing has work under mine scope.
      for (final c in kActionableDocConfigs) {
        api.counts[c.doctype] = 0;
      }

      await controller.setActionableScope(ActionableScope.mine);

      expect(controller.selectedActionable.value, isNull);
    });

    // Fix 4 regression: setActionableScope called _applyDefaultSelection()
    // unconditionally after its `await fetchActionableCounts()`, without
    // re-checking that its captured `scope` was still the current one.
    // fetchActionableCounts already guards its OWN count/loading writes
    // against a stale scope landing late (the `scope-flip race guard` tests
    // above) — but that guard doesn't stop setActionableScope's caller-level
    // continuation from running anyway. A stale call (superseded by a second
    // setActionableScope before the first's count fetch resolved) could
    // still apply a default selection from whatever counts happened to be on
    // screen and fire a wasted forced preview fetch. The second (current)
    // call self-heals the final selection, but the wasted fetch — and a
    // transient wrong-chip flash — still happened without a guard here.
    test(
        "a stale scope's post-await continuation does not apply a default "
        'selection or fire an extra preview fetch', () async {
      grantAll();
      auth.currentUser.value = _user('me@x.com'); // selectedFilterUser null

      // Leftover state from before the race starts — simulates whatever was
      // already on screen. Deliberately distinct from the real mine-scope
      // counts set below, so a premature read is distinguishable from a
      // correct one.
      controller.actionableCounts.assignAll({
        'Purchase Order': 0,
        'Purchase Receipt': 0,
        'Stock Entry': 0,
        'Delivery Note': 2,
        'Packing Slip': 0,
      });

      // Everyone-scope counts are irrelevant here: fetchActionableCounts's own
      // guard already drops a stale scope's count write regardless of the fix
      // under test, so C1 never gets to publish these.
      for (final c in kActionableDocConfigs) {
        api.everyoneCounts[c.doctype] = 0;
      }
      // Real mine-scope counts: only Stock Entry has work.
      for (final c in kActionableDocConfigs) {
        api.counts[c.doctype] = 0;
      }
      api.counts['Stock Entry'] = 4;
      api.listRows['Stock Entry'] = [
        {
          'name': 'SE-0001',
          'stock_entry_type': 'Material Issue',
          'posting_date': '2026-07-12',
          'owner': 'me@x.com',
        }
      ];
      api.listRows['Delivery Note'] = [dnRow('DN-0001')];

      api.mineGate = Completer<void>();
      api.everyoneGate = Completer<void>();

      // C1: scope flips mine -> everyone; its count fetch is left in flight.
      final futA = controller.setActionableScope(ActionableScope.everyone);
      // C2: scope flips back everyone -> mine before C1 resolves; also left
      // in flight. Both fetches issued all their count queries synchronously
      // (before suspending on Future.wait), so C1 captured everyone filters
      // and C2 captured mine filters.
      final futB = controller.setActionableScope(ActionableScope.mine);
      expect(controller.actionableScope.value, ActionableScope.mine);

      // C1 (now stale) resolves FIRST.
      api.everyoneGate!.complete();
      await futA;

      // The guard must short-circuit C1's continuation entirely: no default
      // selection applied, no preview fetch fired.
      expect(controller.selectedActionable.value, isNull,
          reason:
              "C1's stale continuation must not select a chip after losing "
              'the scope race');
      expect(api.listQueries, isEmpty,
          reason:
              "C1's stale continuation must not fire a wasted preview fetch");

      // C2 (current) resolves and applies the correct default selection.
      api.mineGate!.complete();
      await futB;

      expect(controller.selectedActionable.value, 'Stock Entry',
          reason: 'the only doctype with work under the final (mine) scope');
      expect(api.listQueries.map((q) => q.doctype).toList(), ['Stock Entry'],
          reason:
              'exactly one preview fetch — C1 must not have queued a second, '
              'wasted one for Delivery Note');
    });
  });
}
