import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/models/suppliers_by_item_view.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_fields.dart';

class _MemoryBox extends Fake implements GetStorage {
  final _data = <String, Object?>{};
  final _listeners = <void Function()>{};

  @override
  Map<String, dynamic> changes = {};

  @override
  T? read<T>(String key) => _data[key] as T?;

  @override
  Future<void> write(String key, Object? value) async {
    _data[key] = value;
    changes = {key: value};
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  void Function() listen(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

class _ConfigStore extends Fake implements DatabaseService {
  final records = <String, String>{};
  final writes = <String>[];
  final reads = <String>[];
  final readGates = <String, Completer<void>>{};
  final writeGates = <String, Completer<void>>{};
  final rejectedReads = <String>{};
  final rejectedWrites = <String>{};

  @override
  Future<String?> getConfig(String key) async {
    reads.add(key);
    await readGates[key]?.future;
    if (rejectedReads.contains(key)) throw StateError('read failed');
    return records[key];
  }

  @override
  Future<void> saveConfig(String key, String value) async {
    writes.add(key);
    await writeGates[key]?.future;
    if (rejectedWrites.contains(key)) throw StateError('write failed');
    records[key] = value;
  }
}

class _WatchedViewStorage extends StorageService {
  _WatchedViewStorage(super.box, DatabaseService database)
    : super.withStorage(database: database);

  final activeViewScopes = <SuppliersByItemFieldsScope>[];

  @override
  void Function() watchSuppliersByItemView(
    SuppliersByItemFieldsScope scope,
    void Function(SuppliersByItemViewSnapshot) onChange,
  ) {
    final cancel = super.watchSuppliersByItemView(scope, onChange);
    activeViewScopes.add(scope);
    return () {
      activeViewScopes.remove(scope);
      cancel();
    };
  }
}

class _ReportApi extends Fake implements ApiProvider {
  int runs = 0;

  @override
  bool Function() hasActiveSession = () => false;

  @override
  void Function() onSessionExpired = () {};

  @override
  Future<SuppliersByItemReport> runSuppliersByItemReport(
    SuppliersByItemFilters filters,
  ) async {
    runs++;
    return const SuppliersByItemReport(nodes: []);
  }
}

User _user(String id) =>
    User(id: id, name: id, email: id, roles: const ['Purchase User']);

void main() {
  const site = 'https://erp.example';
  late _MemoryBox box;
  late _ConfigStore database;
  late StorageService storage;
  late _ReportApi api;
  late AuthenticationController authentication;

  SuppliersByItemFieldsScope scope(String user, [String normalized = site]) =>
      (site: normalized, user: user);

  String key(String user, [String normalized = site]) =>
      'suppliers_by_item_fields::${Uri.encodeComponent(normalized)}'
      '::${Uri.encodeComponent(user)}';

  String viewKey(String user, [String normalized = site]) =>
      'suppliers_by_item_view::${Uri.encodeComponent(normalized)}'
      '::${Uri.encodeComponent(user)}';

  String oldKey(String rawUser) => 'suppliers_by_item_fields::$rawUser';

  void seed(String user, Map<String, bool> fields, [String normalized = site]) {
    database.records[key(user, normalized)] = jsonEncode(fields);
  }

  Map<String, bool> read(String user, [String normalized = site]) =>
      storage.getSuppliersByItemFields(scope(user, normalized)).overrides;

  Future<SuppliersByItemController> openReport({
    StorageService? usingStorage,
    FutureOr<String?> Function()? siteResolver,
  }) async {
    final controller = SuppliersByItemController(
      api: api,
      storage: usingStorage ?? storage,
      siteResolver: siteResolver,
    );
    controller.onInit();
    addTearDown(controller.onClose);
    await controller.refreshFieldsScope();
    return controller;
  }

  AuthenticationController setCurrentUser(String id) {
    authentication.currentUser.value = _user(id);
    authentication.isAuthenticated.value = true;
    return authentication;
  }

  Future<void> signIn(String id) async {
    await storage.saveUser(_user(id));
    setCurrentUser(id);
  }

  setUp(() async {
    box = _MemoryBox();
    database = _ConfigStore();
    storage = StorageService.withStorage(box, database: database);
    api = _ReportApi();
    Get.testMode = true;
    Get.put<ApiProvider>(api);
    authentication = Get.put(AuthenticationController());
    await storage.saveBaseUrl(site);
  });
  tearDown(Get.reset);

  test('manufacturing and projected reorder warnings default on', () {
    const visibility = SuppliersByItemFieldVisibility.defaults();
    const manufacturing = SuppliersByItemField.componentManufacturing;
    const reorderWarning = SuppliersByItemField.itemBelowReorder;

    expect(visibility.shows(manufacturing), isTrue);
    expect(manufacturing.label, 'Manufacturing exclusion');
    expect(visibility.shows(reorderWarning), isTrue);
    expect(reorderWarning.label, 'Projected Qty below Reorder Level');
    expect(visibility.shows(SuppliersByItemField.itemProjected), isFalse);
    expect(visibility.shows(SuppliersByItemField.itemReorderLevel), isFalse);
  });

  test('restores separate row field choices for each signed-in user', () async {
    const itemBalance = SuppliersByItemField.itemBalance;
    const componentBalance = SuppliersByItemField.componentBalance;
    const sources = SuppliersByItemField.supplierSources;
    await signIn('buyer-a@example.com');
    final first = await openReport();

    expect(first.fieldVisibility.shows(itemBalance), isTrue);
    expect(first.fieldVisibility.shows(componentBalance), isFalse);
    expect(first.fieldVisibility.shows(sources), isFalse);
    final writes = [
      first.setFieldVisible(itemBalance, false),
      first.setFieldVisible(componentBalance, true),
      first.setFieldVisible(sources, true),
    ];
    expect(first.fieldVisibility.shows(itemBalance), isFalse);
    expect(first.fieldVisibility.shows(componentBalance), isTrue);
    expect(first.fieldVisibility.shows(sources), isTrue);
    expect(api.runs, 1);
    await Future.wait(writes);

    await signIn('buyer-b@example.com');
    final second = await openReport();
    expect(second.fieldVisibility.shows(itemBalance), isTrue);
    expect(second.fieldVisibility.shows(componentBalance), isFalse);
    expect(second.fieldVisibility.shows(sources), isFalse);
    await second.setFieldVisible(SuppliersByItemField.itemProjected, true);

    await signIn('buyer-a@example.com');
    final reopened = await openReport();
    expect(reopened.fieldVisibility.shows(itemBalance), isFalse);
    expect(reopened.fieldVisibility.shows(componentBalance), isTrue);
    expect(reopened.fieldVisibility.shows(sources), isTrue);
    expect(
      reopened.fieldVisibility.shows(SuppliersByItemField.itemProjected),
      isFalse,
    );
    await reopened.resetFields();
    expect(api.runs, 3);

    final reset = await openReport();
    expect(reset.fieldVisibility.shows(itemBalance), isTrue);
    expect(reset.fieldVisibility.shows(componentBalance), isFalse);
    expect(reset.fieldVisibility.shows(sources), isFalse);
    expect(read('buyer-b@example.com'), {'itemProjected': true});
  });

  test('stacked reports share field choices without rerunning', () async {
    const balance = SuppliersByItemField.itemBalance;
    const sources = SuppliersByItemField.supplierSources;
    await signIn('buyer-a@example.com');
    final first = await openReport();
    final second = await openReport();

    await second.setFieldVisible(balance, false);
    expect(first.fieldVisibility.shows(balance), isFalse);
    await first.setFieldVisible(sources, true);
    expect(second.fieldVisibility.shows(sources), isTrue);
    expect(second.fieldVisibility.shows(balance), isFalse);
    await first.resetFields();
    expect(second.fieldVisibility.shows(balance), isTrue);
    expect(second.fieldVisibility.shows(sources), isFalse);
    expect(api.runs, 2);
  });

  test(
    'restores and saves fields for a signed-in user without a cached profile',
    () async {
      const id = 'buyer@example.com';
      setCurrentUser(id);
      expect(storage.getUser(), isNull);
      seed(id, {'itemBalance': false});

      final report = await openReport();
      expect(
        report.fieldVisibility.shows(SuppliersByItemField.itemBalance),
        isFalse,
      );
      await report.setFieldVisible(SuppliersByItemField.supplierSources, true);

      expect(read(id), {'itemBalance': false, 'supplierSources': true});
    },
  );

  test(
    'keeps edits local until the preference owner is synchronized',
    () async {
      const cachedId = 'cached@example.com';
      const signedInId = 'buyer@example.com';
      final auth = setCurrentUser(cachedId);
      await signIn(cachedId);
      seed(cachedId, {'itemBalance': false});
      seed(signedInId, {'itemProjected': true});
      final report = await openReport();

      auth.currentUser.value = _user(signedInId);
      await report.setFieldVisible(SuppliersByItemField.supplierSources, true);
      expect(report.fieldsSessionOnly.value, isTrue);
      expect(database.records[key(signedInId)], '{"itemProjected":true}');
      expect(database.writes, isEmpty);

      await storage.saveUser(_user(signedInId));
      await report.refreshFieldsScope();
      await report.setFieldVisible(SuppliersByItemField.supplierSources, true);

      expect(read(cachedId), {'itemBalance': false});
      expect(read(signedInId), {
        'itemProjected': true,
        'supplierSources': true,
      });
    },
  );

  test(
    'reloads mounted field choices when the signed-in user changes',
    () async {
      const firstId = 'buyer-a@example.com';
      const secondId = 'buyer-b@example.com';
      const balance = SuppliersByItemField.itemBalance;
      const projected = SuppliersByItemField.itemProjected;
      await signIn(firstId);
      seed(firstId, {'itemBalance': false});
      seed(secondId, {'itemProjected': true});
      final report = await openReport();

      expect(report.fieldVisibility.shows(balance), isFalse);
      expect(report.fieldVisibility.shows(projected), isFalse);

      await signIn(secondId);
      await report.refreshFieldsScope();
      expect(report.fieldVisibility.shows(balance), isTrue);
      expect(report.fieldVisibility.shows(projected), isTrue);

      await signIn('buyer-c@example.com');
      await report.refreshFieldsScope();
      expect(report.fieldVisibility.shows(balance), isTrue);
      expect(report.fieldVisibility.shows(projected), isFalse);
      expect(api.runs, 1);
    },
  );

  test(
    'stops watching signed-in user changes when the report closes',
    () async {
      const firstId = 'buyer-a@example.com';
      final auth = setCurrentUser(firstId);
      final userStream = auth.currentUser.subject;
      expect(userStream.length, 0);
      Get.put(SuppliersByItemController(api: api, storage: storage));
      expect(userStream.length, 1);

      expect(await Get.delete<SuppliersByItemController>(), isTrue);
      expect(userStream.length, 0);
    },
  );

  test(
    'falls back to the initial cached profile before the live user arrives',
    () async {
      const cachedId = 'cached@example.com';
      authentication.isAuthenticated.value = true;
      await storage.saveUser(_user(cachedId));
      seed(cachedId, {'itemBalance': false});

      final report = await openReport();
      expect(
        report.fieldVisibility.shows(SuppliersByItemField.itemBalance),
        isFalse,
      );
      await report.resetFields();

      expect(read(cachedId), isEmpty);
      expect(read('  '), isEmpty);
    },
  );

  test('ignores empty and whitespace-only preference owner IDs', () async {
    const saved = {'itemBalance': false};
    setCurrentUser('');
    await storage.saveUser(_user('  '));
    await box.write(oldKey(''), saved);
    await box.write(oldKey('  '), saved);

    final report = await openReport();
    expect(
      report.fieldVisibility.shows(SuppliersByItemField.itemBalance),
      isTrue,
    );
    await report.setFieldVisible(SuppliersByItemField.supplierSources, true);

    expect(
      report.fieldVisibility.shows(SuppliersByItemField.supplierSources),
      isTrue,
    );
    expect(box.read(oldKey('')), saved);
    expect(box.read(oldKey('  ')), saved);
    expect(report.fieldsSessionOnly.value, isTrue);
    expect(database.writes, isEmpty);
  });

  test(
    'preserves retained field IDs and separates Fields and View reset',
    () async {
      const defaults = SuppliersByItemFieldVisibility.defaults();
      const added = {
        'Item rows': [
          'templateVariantCount',
          'itemOpenPoBadge',
          'itemDraftPoBadge',
        ],
        'Supplier rows': [
          'supplierLastBuyColumn',
          'supplierOpenPoBadge',
          'supplierDraftPoBadge',
          'supplierMatchEmphasis',
        ],
        'BOM and tree labels': [
          'bomDefaultMarker',
          'bomDraftBadge',
          'bomComponentCount',
          'treeDepthLabel',
        ],
        'Search': ['searchMatchCount'],
      };
      const previous = [
        'itemName',
        'itemSupplierCount',
        'itemBalance',
        'itemStockUom',
        'itemProjected',
        'itemBelowReorder',
        'itemReorderLevel',
        'itemReorderQty',
        'itemOpenOrders',
        'itemDraftOrders',
        'itemQtyReceived',
        'supplierStatus',
        'supplierOpenOrders',
        'supplierStockUom',
        'supplierDraftOrders',
        'supplierPartNumber',
        'supplierSources',
        'supplierLastPurchase',
        'supplierLastPurchaseReceipt',
        'supplierQtyReceived',
        'supplierLastPo',
        'supplierRate',
        'supplierRateCurrency',
        'supplierRateUom',
        'supplierRateSource',
        'supplierRateDate',
        'supplierRateDocument',
        'supplierLeadTime',
        'supplierLeadTimeReceipts',
        'supplierPoCount',
        'supplierReceiptCount',
        'componentName',
        'componentSupplierCount',
        'componentQtyPerUnit',
        'componentStockUom',
        'componentBalance',
        'componentProjected',
        'componentLastPurchase',
        'componentUsedInBoms',
        'componentManufacturing',
        'componentCycle',
        'componentDepthLimit',
      ];
      const stage2 = {
        'supplierGroupItemCount': 'Supplier rows',
        'supplierGroupComponentCount': 'Supplier rows',
        'componentMatchPath': 'BOM component rows',
      };
      final releasedIds = [
        ...previous,
        ...added.values.expand((ids) => ids),
        ...stage2.keys,
      ];
      // The remaining released IDs defaulted on in b08ea347.
      const releasedDefaultOff = {
        'itemProjected',
        'itemReorderLevel',
        'itemReorderQty',
        'itemOpenOrders',
        'itemDraftOrders',
        'itemQtyReceived',
        'supplierDraftOrders',
        'supplierPartNumber',
        'supplierSources',
        'supplierLastPurchase',
        'supplierLastPurchaseReceipt',
        'supplierQtyReceived',
        'supplierLastPo',
        'supplierRate',
        'supplierRateSource',
        'supplierRateDate',
        'supplierRateDocument',
        'supplierLeadTime',
        'supplierLeadTimeReceipts',
        'supplierPoCount',
        'supplierReceiptCount',
        'componentBalance',
        'componentProjected',
        'componentLastPurchase',
        'componentUsedInBoms',
      };
      final releasedDefaults = {
        for (final id in releasedIds) id: !releasedDefaultOff.contains(id),
      };
      expect(
        SuppliersByItemField.values.map((field) => field.name),
        releasedIds,
      );
      expect(releasedIds, hasLength(57));
      for (final entry in added.entries) {
        for (final id in entry.value) {
          final field = SuppliersByItemField.values.byName(id);
          expect(field.group.label, entry.key);
          expect(defaults.shows(field), isTrue);
        }
      }
      for (final entry in stage2.entries) {
        final field = SuppliersByItemField.values.byName(entry.key);
        expect(field.group.label, entry.value);
        expect(defaults.shows(field), isTrue);
      }

      const protectedIds = {
        'itemName',
        'componentName',
        'supplierStatus',
        'itemBelowReorder',
        'componentManufacturing',
        'componentCycle',
        'componentDepthLimit',
        'componentMatchPath',
        'bomDefaultMarker',
        'bomDraftBadge',
        'treeDepthLabel',
      };
      const viewIds = {
        'componentUsedInBoms',
        'supplierMatchEmphasis',
        'templateVariantCount',
        'supplierGroupItemCount',
        'supplierGroupComponentCount',
        'bomComponentCount',
        'searchMatchCount',
      };
      const user = 'legacy-buyer';
      final overrides = {
        for (final entry in releasedDefaults.entries) entry.key: !entry.value,
      };
      void expectSelection(
        SuppliersByItemFieldVisibility visibility,
        Map<String, bool> expected,
      ) {
        expect({
          for (final field in SuppliersByItemField.values)
            field.name: visibility.shows(field),
        }, expected);
      }

      await signIn('fresh-buyer');
      final fresh = await openReport();
      expectSelection(fresh.fieldVisibility, releasedDefaults);
      expect(database.records[key('fresh-buyer')], isNull);

      final bytes = jsonEncode(overrides);
      database.records[key(user)] = bytes;
      await signIn(user);
      final report = await openReport();
      expect(database.records[key(user)], bytes);
      expect(report.fieldVisibility.overrides, overrides);
      for (final id in releasedIds) {
        final field = SuppliersByItemField.values.byName(id);
        expect(field.fixed, protectedIds.contains(id), reason: id);
        expect(field.movedToView, viewIds.contains(id), reason: id);
        expect(
          report.fieldVisibility.shows(field),
          protectedIds.contains(id) || overrides[id]!,
          reason: id,
        );
      }

      await report.resetFields();
      expect(jsonDecode(database.records[key(user)]!), {
        for (final id in viewIds) id: overrides[id],
      });
      expectSelection(report.fieldVisibility, {
        ...releasedDefaults,
        for (final id in viewIds) id: overrides[id]!,
      });
      await report.setFieldVisible(SuppliersByItemField.itemBalance, false);
      await report.resetViewDisplayOptions();
      expect(jsonDecode(database.records[key(user)]!), {'itemBalance': false});
      expectSelection(report.fieldVisibility, {
        ...releasedDefaults,
        'itemBalance': false,
      });
      await report.resetFields();
      expect(jsonDecode(database.records[key(user)]!), isEmpty);
      expectSelection(report.fieldVisibility, releasedDefaults);
      expect(api.runs, 2);
    },
  );

  test(
    'ignores retired summary and promotion settings and unknown footer keys',
    () async {
      const user = 'buyer';
      seed(user, {
        'summaryItemCount': false,
        'summarySupplierCount': false,
        'summaryNoDirectCount': false,
        'summaryStockByUom': false,
        'itemTemplateContext': false,
        'footerTotals': true,
        'itemBalance': false,
        'templateVariantCount': false,
      });
      await signIn(user);
      final report = await openReport();
      expect(report.fieldsLoadError.value, isNull);
      expect(report.fieldVisibility.overrides, {
        'itemBalance': false,
        'templateVariantCount': false,
      });
      expect(database.writes, isEmpty);

      await report.setFieldVisible(SuppliersByItemField.supplierSources, true);
      expect(jsonDecode(database.records[key(user)]!), {
        'itemBalance': false,
        'templateVariantCount': false,
        'supplierSources': true,
      });
    },
  );

  test(
    'rate format choices survive disabling and re-enabling Supplier rate',
    () async {
      await signIn('buyer');
      final report = await openReport();
      const rate = SuppliersByItemField.supplierRate;
      const currency = SuppliersByItemField.supplierRateCurrency;
      const uom = SuppliersByItemField.supplierRateUom;
      await report.setFieldVisible(rate, true);
      await report.setFieldVisible(currency, false);
      await report.setFieldVisible(uom, false);
      await report.setFieldVisible(rate, false);
      expect(read('buyer'), {
        'supplierRateCurrency': false,
        'supplierRateUom': false,
      });
      await report.setFieldVisible(rate, true);
      expect(report.fieldVisibility.shows(currency), isFalse);
      expect(report.fieldVisibility.shows(uom), isFalse);
      expect(api.runs, 1);
    },
  );

  test(
    'normalizes active site URLs and preserves path and scheme identity',
    () {
      const urls = {
        ' ERP.Example ': 'https://erp.example',
        'LocalHost:8080/Path///': 'https://localhost:8080/Path',
        'HTTPS://ERP.Example:443/Tenant///': 'https://erp.example/Tenant',
        'HTTP://ERP.Example:80/Tenant': 'http://erp.example/Tenant',
        'https://user:pass@ERP.Example:444/tenant%2Fspace?x=1#frag':
            'https://erp.example:444/tenant%2Fspace',
        'https://[::1]:443/Tenant': 'https://[::1]/Tenant',
        'https://ERP.Example/tEnAnT': 'https://erp.example/tEnAnT',
        'https://ERP.Example/Tenant': 'https://erp.example/Tenant',
        'ftp://erp.example': null,
        'https:///tenant': null,
        'erp example': null,
        '': null,
      };
      for (final entry in urls.entries) {
        expect(
          normalizeSuppliersByItemSite(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test(
    'isolates sites and users across fresh services with encoded keys',
    () async {
      const user = 'Buyer::East@example.com';
      const other = 'https://next.example:444/Tenant%2Fdivision';
      await signIn(' $user ');
      final report = await openReport();
      const balance = SuppliersByItemField.itemBalance;
      const projected = SuppliersByItemField.itemProjected;
      await report.setFieldVisible(balance, false);
      await storage.saveBaseUrl(
        'HTTPS://NEXT.example:444/Tenant%2Fdivision///',
      );
      await report.refreshFieldsScope();
      expect(report.fieldVisibility.shows(balance), isTrue);
      await report.setFieldVisible(projected, true);
      expect(database.records[key(user, other)], '{"itemProjected":true}');

      await signIn('Buyer2');
      await report.refreshFieldsScope();
      expect(report.fieldVisibility.shows(projected), isFalse);
      await report.setFieldVisible(balance, false);
      expect(database.records[key('Buyer2', other)], '{"itemBalance":false}');
      await signIn(user);
      await storage.saveBaseUrl(site);
      final fresh = await openReport(
        usingStorage: StorageService.withStorage(box, database: database),
      );
      expect(fresh.fieldVisibility.shows(balance), isFalse);
      expect(fresh.fieldVisibility.shows(projected), isFalse);
      expect(database.records[key(user)], '{"itemBalance":false}');
    },
  );

  test(
    'migrates the exact raw legacy key once and sanitizes map entries',
    () async {
      const user = 'Buyer::East';
      const rawUser = ' Buyer::East ';
      const nextSite = 'https://next.example';
      final legacy = <Object, Object>{
        'itemBalance': false,
        'futureOption': true,
        'itemProjected': 'bad',
        42: true,
      };
      await box.write(oldKey(rawUser), legacy);
      await box.write(oldKey(user), {'itemProjected': true});
      await signIn(rawUser);
      final first = await openReport();

      final claim =
          'suppliers_by_item_fields_legacy_owner::${Uri.encodeComponent(user)}';
      expect(database.records[claim], site);
      expect(database.writes, [claim, key(user)]);
      expect(read(user), {'itemBalance': false, 'futureOption': true});
      expect(box.read(oldKey(rawUser)), same(legacy));

      await storage.saveBaseUrl(nextSite);
      await first.refreshFieldsScope();
      expect(read(user, nextSite), isEmpty);
      expect(database.records, isNot(contains(key(user, nextSite))));
      expect(box.read(oldKey(user)), {'itemProjected': true});
    },
  );

  test(
    'explicit empty scoped records win and still claim legacy ownership',
    () async {
      const user = 'buyer';
      const nextSite = 'https://next.example';
      await box.write(oldKey(user), {'itemBalance': false});
      seed(user, {});
      await signIn(user);
      final report = await openReport();
      expect(report.fieldVisibility.overrides, isEmpty);
      expect(
        database.records['suppliers_by_item_fields_legacy_owner::$user'],
        site,
      );
      expect(database.records[key(user)], '{}');

      await storage.saveBaseUrl(nextSite);
      await report.refreshFieldsScope();
      expect(report.fieldVisibility.overrides, isEmpty);
      expect(database.records, isNot(contains(key(user, nextSite))));
    },
  );

  test('retries interrupted migration only on the claimed site', () async {
    const user = 'buyer';
    const nextSite = 'https://next.example';
    final scoped = key(user);
    final claim = 'suppliers_by_item_fields_legacy_owner::$user';
    await box.write(oldKey(user), {'itemBalance': false});
    await signIn(user);
    database.rejectedWrites.add(scoped);
    final report = await openReport();
    expect(database.records[claim], site);
    expect(database.records, isNot(contains(scoped)));
    expect(report.fieldVisibility.overrides, {'itemBalance': false});
    expect(report.fieldsSaveError.value, startsWith("Couldn't save Fields."));

    await storage.saveBaseUrl(nextSite);
    final fresh = await openReport(
      usingStorage: StorageService.withStorage(box, database: database),
    );
    expect(fresh.fieldVisibility.overrides, isEmpty);
    expect(database.records, isNot(contains(key(user, nextSite))));

    database.rejectedWrites.clear();
    await storage.saveBaseUrl(site);
    await report.retryFields();
    await report.refreshFieldsScope();
    expect(database.records[scoped], '{"itemBalance":false}');
    expect(report.fieldsSaveError.value, isNull);
    expect(database.writes.where((key) => key == claim), hasLength(1));
  });

  test(
    'reserves legacy Fields for the first site when its claim write fails',
    () async {
      const user = 'buyer';
      const nextSite = 'https://next.example';
      const legacy = {'itemBalance': false};
      final scoped = key(user);
      final claim = 'suppliers_by_item_fields_legacy_owner::$user';
      await box.write(oldKey(user), legacy);
      await signIn(user);
      final claimGate = Completer<void>();
      database.writeGates[claim] = claimGate;
      database.rejectedWrites.add(claim);

      final opening = openReport();
      await Future<void>.delayed(Duration.zero);
      expect(database.writes, [claim]);
      expect(read(user), isEmpty);
      claimGate.complete();
      final first = await opening;
      expect(database.records, isNot(contains(claim)));
      expect(database.records, isNot(contains(scoped)));
      expect(first.fieldVisibility.overrides, legacy);
      expect(first.fieldsSaveError.value, startsWith("Couldn't save Fields."));

      database.rejectedWrites.remove(claim);
      final second = await openReport(siteResolver: () => nextSite);
      expect(second.fieldVisibility.overrides, isEmpty);
      expect(database.writes, [claim]);

      await first.retryFields();
      expect(first.fieldVisibility.overrides, legacy);
      expect(first.fieldsSaveError.value, isNull);
      expect(second.fieldVisibility.overrides, isEmpty);
      expect(database.writes, [claim, claim, scoped]);
      expect(database.records[claim], site);
      expect(database.records[scoped], jsonEncode(legacy));
      expect(database.records, isNot(contains(key(user, nextSite))));
    },
  );

  test(
    'uses SQLite fallback for a blank mirror and invalid scopes stay local',
    () async {
      const user = 'buyer';
      const fallback = 'https://erp.example:8443/Tenant';
      await storage.saveBaseUrl('   ');
      database.records[DatabaseService.serverUrlKey] = fallback;
      await signIn(user);
      final report = await openReport();
      await report.setFieldVisible(SuppliersByItemField.itemBalance, false);
      expect(database.records[key(user, fallback)], '{"itemBalance":false}');

      await box.write(oldKey('localBuyer'), {'itemBalance': false});
      await storage.saveBaseUrl('ssh://invalid.example');
      await signIn('localBuyer');
      await report.refreshFieldsScope();
      expect(report.fieldsSessionOnly.value, isTrue);
      expect(report.fieldVisibility.overrides, isEmpty);
      await report.setFieldVisible(SuppliersByItemField.itemProjected, true);
      expect(report.fieldVisibility.overrides, {'itemProjected': true});
      expect(database.writes, [key(user, fallback)]);
    },
  );

  test(
    'a failed read blocks persistence and retry preserves the disk record',
    () async {
      const user = 'buyer';
      final scoped = key(user);
      seed(user, {'itemBalance': false});
      database.rejectedReads.add(scoped);
      await signIn(user);
      final report = await openReport();
      expect(report.fieldsLoadError.value, "Couldn't load settings");
      expect(report.fieldsEditable, isFalse);
      await report.resetFields();
      expect(database.writes, isEmpty);
      database.rejectedReads.clear();
      await report.retryFields();
      expect(report.fieldsLoadError.value, isNull);
      expect(report.fieldVisibility.overrides, {'itemBalance': false});
    },
  );

  test(
    'late reads and old-scope notifications do not affect the new owner',
    () async {
      const firstUser = 'buyer-a';
      const secondUser = 'buyer-b';
      await signIn(firstUser);
      final firstRead = Completer<void>();
      database.readGates[key(firstUser)] = firstRead;
      seed(firstUser, {'itemBalance': false});
      seed(secondUser, {'itemProjected': true});
      final report = SuppliersByItemController(api: api, storage: storage);
      report.onInit();
      addTearDown(report.onClose);
      final firstPending = report.refreshFieldsScope();
      await Future<void>.delayed(Duration.zero);
      expect(
        database.reads,
        unorderedEquals([key(firstUser), viewKey(firstUser)]),
      );
      await signIn(secondUser);
      await report.refreshFieldsScope();
      firstRead.complete();
      await firstPending;

      expect(report.fieldVisibility.overrides, {'itemProjected': true});
      await storage.saveSuppliersByItemFields(scope(firstUser), {
        'itemDraftOrders': true,
      });
      expect(report.fieldVisibility.overrides, {'itemProjected': true});
    },
  );

  test(
    'site resolver rebinds on resume and close removes ownership listeners',
    () async {
      const user = 'buyer';
      const nextSite = 'https://next.example';
      var resolved = site;
      seed(user, {'itemBalance': false});
      seed(user, {'itemProjected': true}, nextSite);
      await signIn(user);
      final report = SuppliersByItemController(
        api: api,
        storage: storage,
        siteResolver: () => resolved,
      );
      report.onInit();
      await report.refreshFieldsScope();
      expect(box._listeners, hasLength(1));
      expect(report.fieldVisibility.overrides, {'itemBalance': false});
      resolved = nextSite;
      await report.refreshFieldsScope();
      expect(report.fieldVisibility.overrides, {'itemProjected': true});
      report.onClose();
      expect(box._listeners, isEmpty);
      await storage.saveSuppliersByItemFields(scope(user, nextSite), {});
      expect(report.fieldVisibility.overrides, {'itemProjected': true});
    },
  );

  test(
    'serializes rapid optimistic edits and reset across stacked routes',
    () async {
      const user = 'buyer';
      final scoped = key(user);
      await signIn(user);
      final first = await openReport();
      final second = await openReport();
      final writeGate = Completer<void>();
      database.writeGates[scoped] = writeGate;
      final writes = [
        first.setFieldVisible(SuppliersByItemField.itemBalance, false),
        second.setFieldVisible(SuppliersByItemField.itemProjected, true),
        first.resetFields(),
        second.setFieldVisible(SuppliersByItemField.supplierSources, true),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(database.writes, [scoped]);
      expect(first.fieldsSaving.value, isTrue);
      expect(second.fieldsSaving.value, isTrue);
      expect(first.fieldVisibility.overrides, {'supplierSources': true});
      expect(first.fieldVisibility.overrides, second.fieldVisibility.overrides);

      writeGate.complete();
      await Future.wait(writes);
      expect(database.writes, List.filled(4, scoped));
      expect(database.records[scoped], '{"supplierSources":true}');
      expect(first.fieldsSaving.value, isFalse);
      expect(second.fieldsSaving.value, isFalse);
      expect(api.runs, 2);
    },
  );

  test('keeps multiple edits in memory when no site is configured', () async {
    await storage.saveBaseUrl('');
    await signIn('buyer');
    await box.write(oldKey('buyer'), {'supplierLeadTime': true});
    final report = await openReport();
    await report.setFieldVisible(SuppliersByItemField.itemBalance, false);
    await report.setFieldVisible(SuppliersByItemField.itemProjected, true);
    await report.refreshFieldsScope();
    expect(report.fieldsSessionOnly.value, isTrue);
    expect(report.fieldVisibility.overrides, {
      'itemBalance': false,
      'itemProjected': true,
    });
    expect(database.writes, isEmpty);
  });

  test(
    'a late failed write cannot disable the same checkbox for another owner',
    () async {
      const oldOwner = 'buyer-a';
      const newOwner = 'buyer-b';
      const balance = SuppliersByItemField.itemBalance;
      await signIn(oldOwner);
      final report = await openReport();
      final oldWrite = Completer<void>();
      final newWrite = Completer<void>();
      database.writeGates[key(oldOwner)] = oldWrite;
      database.writeGates[key(newOwner)] = newWrite;
      database.rejectedWrites.add(key(oldOwner));

      final oldPending = report.setFieldVisible(balance, false);
      expect(report.isSavingField(balance), isTrue);
      await signIn(newOwner);
      await report.refreshFieldsScope();
      expect(report.isSavingField(balance), isFalse);
      final newPending = report.setFieldVisible(balance, false);
      expect(report.isSavingField(balance), isTrue);

      oldWrite.complete();
      await oldPending;
      expect(report.fieldsSaveError.value, isNull);
      expect(report.fieldsSaving.value, isTrue);
      expect(report.isSavingField(balance), isTrue);
      newWrite.complete();
      await newPending;
      expect(report.fieldsSaving.value, isFalse);
      expect(report.isSavingField(balance), isFalse);
      expect(database.records[key(newOwner)], '{"itemBalance":false}');
    },
  );

  test('defaults each missing or corrupt View member independently', () async {
    const user = 'buyer';
    final examples = <String, SuppliersByItemView>{
      '{"group":"other","sortField":"supplierCount","sortDirection":"asc"}':
          const SuppliersByItemView(
            sortField: SuppliersByItemSortField.supplierCount,
            sortDirection: SuppliersByItemSortDirection.asc,
          ),
      '{"group":"supplier","sortField":null,"sortDirection":"asc"}':
          const SuppliersByItemView(
            group: SuppliersByItemGroup.supplier,
            sortDirection: SuppliersByItemSortDirection.asc,
          ),
      '{"group":"supplier","sortField":"lastPurchase"}':
          const SuppliersByItemView(
            group: SuppliersByItemGroup.supplier,
            sortField: SuppliersByItemSortField.lastPurchase,
          ),
      '[]': const SuppliersByItemView(),
      '{': const SuppliersByItemView(),
    };
    for (final entry in examples.entries) {
      database.records[viewKey(user)] = entry.key;
      final fresh = StorageService.withStorage(box, database: database);
      await fresh.loadSuppliersByItemView(scope(user));
      final snapshot = fresh.getSuppliersByItemView(scope(user));
      expect(snapshot.loaded, isTrue);
      expect(snapshot.view, entry.value, reason: entry.key);
    }
    expect(database.writes, isEmpty);
  });

  test(
    'persists View independently from Fields by encoded site and user',
    () async {
      const user = 'Buyer::East';
      const nextSite = 'https://next.example:444/Tenant%2Fdivision';
      await signIn(' $user ');
      final report = await openReport();
      await report.setGroup(SuppliersByItemGroup.supplier);
      await report.setSortField(SuppliersByItemSortField.lastPurchase);
      await report.setSortDirection(SuppliersByItemSortDirection.asc);
      final saved = report.view.value;
      expect(jsonDecode(database.records[viewKey(user)]!), saved.toJson());

      await report.setFieldVisible(SuppliersByItemField.itemBalance, false);
      await report.resetFields();
      expect(database.records[key(user)], '{}');
      expect(jsonDecode(database.records[viewKey(user)]!), saved.toJson());
      await report.setFieldVisible(SuppliersByItemField.itemProjected, true);
      await report.setGroup(SuppliersByItemGroup.template);
      expect(
        report.view.value,
        saved.copyWith(group: SuppliersByItemGroup.template),
      );
      expect(database.records[key(user)], '{"itemProjected":true}');

      await storage.saveBaseUrl(
        'HTTPS://NEXT.example:444/Tenant%2Fdivision///',
      );
      await report.refreshFieldsScope();
      expect(report.view.value, const SuppliersByItemView());
      await report.setGroup(SuppliersByItemGroup.supplier);
      expect(
        jsonDecode(database.records[viewKey(user, nextSite)]!),
        const SuppliersByItemView(
          group: SuppliersByItemGroup.supplier,
        ).toJson(),
      );
      await signIn('different buyer');
      await report.refreshFieldsScope();
      expect(report.view.value, const SuppliersByItemView());
      await report.setSortField(SuppliersByItemSortField.supplierCount);
      expect(
        jsonDecode(database.records[viewKey('different buyer', nextSite)]!),
        const SuppliersByItemView(
          sortField: SuppliersByItemSortField.supplierCount,
        ).toJson(),
      );

      await signIn(user);
      await storage.saveBaseUrl(site);
      final fresh = await openReport(
        usingStorage: StorageService.withStorage(box, database: database),
      );
      expect(
        fresh.view.value,
        saved.copyWith(group: SuppliersByItemGroup.template),
      );
      expect(fresh.fieldVisibility.overrides, {'itemProjected': true});
      expect(api.runs, 2);
    },
  );

  test(
    'shares rapid View edits across routes and serializes complete writes',
    () async {
      const user = 'buyer';
      final scoped = viewKey(user);
      await signIn(user);
      final first = await openReport();
      final second = await openReport();
      final writeGate = Completer<void>();
      database.writeGates[scoped] = writeGate;

      final pending = [
        first.setGroup(SuppliersByItemGroup.supplier),
        second.setSortField(SuppliersByItemSortField.lastPurchase),
        first.setSortDirection(SuppliersByItemSortDirection.asc),
        second.setSortField(SuppliersByItemSortField.lastPurchase),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(database.writes, [scoped]);
      expect(first.viewSaving.value, isTrue);
      expect(second.viewSaving.value, isTrue);
      expect(first.view.value, second.view.value);
      expect(first.view.value.toJson(), {
        'group': 'supplier',
        'sortField': 'lastPurchase',
        'sortDirection': 'asc',
      });

      await first.setFieldVisible(SuppliersByItemField.itemBalance, false);
      expect(database.writes, [scoped, key(user)]);
      writeGate.complete();
      await Future.wait(pending);
      expect(database.writes.where((key) => key == scoped), hasLength(3));
      expect(jsonDecode(database.records[scoped]!), first.view.value.toJson());
      expect(first.viewSaving.value, isFalse);
      expect(second.viewSaving.value, isFalse);
      await first.setSortField(SuppliersByItemSortField.supplierCount);
      expect(first.view.value.sortDirection, SuppliersByItemSortDirection.desc);
      expect(second.view.value, first.view.value);
      expect(api.runs, 2);
    },
  );

  test(
    'keeps failed View choices and retries the latest complete record',
    () async {
      const user = 'buyer';
      final scoped = viewKey(user);
      await signIn(user);
      final first = await openReport();
      final second = await openReport();
      database.rejectedWrites.add(scoped);
      await first.setGroup(SuppliersByItemGroup.supplier);
      await second.setSortDirection(SuppliersByItemSortDirection.asc);
      expect(first.view.value, second.view.value);
      expect(first.view.value.group, SuppliersByItemGroup.supplier);
      expect(first.view.value.sortDirection, SuppliersByItemSortDirection.asc);
      expect(
        first.viewSaveError.value,
        "Couldn't save View. Your choices apply to this session.",
      );
      expect(second.viewSaveError.value, first.viewSaveError.value);
      expect(first.fieldsSaveError.value, isNull);
      expect(database.records.containsKey(scoped), isFalse);

      database.rejectedWrites.clear();
      final gate = Completer<void>();
      database.writeGates[scoped] = gate;
      final retry = second.retryView();
      expect(second.viewRetrying.value, isTrue);
      expect(first.viewSaving.value, isTrue);
      await second.retryView();
      await first.retryView();
      gate.complete();
      await retry;
      expect(database.writes, List.filled(3, scoped));
      expect(jsonDecode(database.records[scoped]!), first.view.value.toJson());
      expect(first.viewSaveError.value, isNull);
      expect(second.viewRetrying.value, isFalse);
    },
  );

  test('an earlier failed View write cannot replace a queued choice', () async {
    const user = 'buyer';
    final scoped = viewKey(user);
    await signIn(user);
    final report = await openReport();
    final firstGate = Completer<void>();
    database.writeGates[scoped] = firstGate;
    final first = report.setGroup(SuppliersByItemGroup.supplier);
    await Future<void>.delayed(Duration.zero);
    expect(database.writes, [scoped]);

    final nextGate = Completer<void>();
    database.writeGates[scoped] = nextGate;
    final next = report.setSortField(SuppliersByItemSortField.lastPurchase);
    final latest = report.view.value;
    firstGate.completeError(StateError('write failed'));
    await first;
    expect(report.view.value, latest);
    expect(report.viewSaveError.value, isNull);
    expect(report.viewSaving.value, isTrue);

    nextGate.complete();
    await next;
    expect(report.viewSaving.value, isFalse);
    expect(jsonDecode(database.records[scoped]!), latest.toJson());
  });

  test(
    'a failed View read blocks edits until the record can be read',
    () async {
      const user = 'buyer';
      const saved = SuppliersByItemView(group: SuppliersByItemGroup.supplier);
      final scoped = viewKey(user);
      await signIn(user);
      database.records[scoped] = jsonEncode(saved.toJson());
      database.rejectedReads.add(scoped);
      final report = await openReport();
      expect(report.viewEditable, isFalse);
      expect(report.viewLoadError.value, "Couldn't load settings");
      expect(report.fieldsEditable, isTrue);
      await report.setSortField(SuppliersByItemSortField.lastPurchase);
      expect(database.writes, isEmpty);
      database.rejectedReads.clear();
      await report.retryView();
      expect(report.viewEditable, isTrue);
      expect(report.viewLoadError.value, isNull);
      expect(report.view.value, saved);
    },
  );

  test(
    'ignores obsolete View reads, writes and listener notifications',
    () async {
      const oldUser = 'buyer-a';
      const newUser = 'buyer-b';
      const nextSite = 'https://next.example';
      final oldKey = viewKey(oldUser);
      final pendingRead = Completer<void>();
      database.readGates[oldKey] = pendingRead;
      database.records[oldKey] = '{"group":"supplier"}';
      final watchedStorage = _WatchedViewStorage(box, database);
      await signIn(oldUser);
      final report = SuppliersByItemController(
        api: api,
        storage: watchedStorage,
      );
      report.onInit();
      final oldLoad = report.refreshFieldsScope();
      await Future<void>.delayed(Duration.zero);
      expect(report.fieldsScopeLoading.value, isTrue);
      expect(watchedStorage.activeViewScopes, [scope(oldUser)]);

      await signIn(newUser);
      await report.refreshFieldsScope();
      expect(watchedStorage.activeViewScopes, [scope(newUser)]);
      final gate = Completer<void>();
      database.writeGates[viewKey(newUser)] = gate;
      database.rejectedWrites.add(viewKey(newUser));
      final obsoleteWrite = report.setGroup(SuppliersByItemGroup.supplier);
      expect(report.viewSaving.value, isTrue);
      await storage.saveBaseUrl(nextSite);
      await report.refreshFieldsScope();
      expect(watchedStorage.activeViewScopes, [scope(newUser, nextSite)]);
      await report.setSortDirection(SuppliersByItemSortDirection.asc);
      final current = report.view.value;

      pendingRead.complete();
      await oldLoad;
      gate.complete();
      await obsoleteWrite;
      expect(report.view.value, current);
      expect(report.viewSaveError.value, isNull);
      expect(report.viewSaving.value, isFalse);
      expect(report.fieldsScopeLoading.value, isFalse);

      report.onClose();
      expect(box._listeners, isEmpty);
      expect(watchedStorage.activeViewScopes, isEmpty);
      await watchedStorage.updateSuppliersByItemView(
        scope(newUser, nextSite),
        (view) => view.copyWith(group: SuppliersByItemGroup.supplier),
      );
      expect(report.view.value, current);
      expect(api.runs, 1);
    },
  );

  test('View choices apply to this session without an owner', () async {
    final report = await openReport();
    expect(report.fieldsSessionOnly.value, isTrue);
    await report.setGroup(SuppliersByItemGroup.supplier);
    await report.setSortDirection(SuppliersByItemSortDirection.asc);
    await report.resetFields();
    await report.refreshFieldsScope();
    expect(
      report.view.value,
      const SuppliersByItemView(
        group: SuppliersByItemGroup.supplier,
        sortDirection: SuppliersByItemSortDirection.asc,
      ),
    );
    expect(database.writes, isEmpty);
  });

  test(
    'signed-in View choices stay in memory without a configured site',
    () async {
      await storage.saveBaseUrl('');
      await signIn('buyer');
      expect(database.records, isNot(contains(DatabaseService.serverUrlKey)));
      final report = await openReport();
      expect(report.fieldsSessionOnly.value, isTrue);
      expect(database.reads, contains(DatabaseService.serverUrlKey));

      await report.setGroup(SuppliersByItemGroup.supplier);
      await report.setSortDirection(SuppliersByItemSortDirection.asc);
      await report.refreshFieldsScope();

      expect(report.fieldsSessionOnly.value, isTrue);
      expect(
        report.view.value,
        const SuppliersByItemView(
          group: SuppliersByItemGroup.supplier,
          sortDirection: SuppliersByItemSortDirection.asc,
        ),
      );
      expect(database.writes, isEmpty);
    },
  );
}
