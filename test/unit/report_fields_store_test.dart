import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';

import '../helpers/auth_fakes.dart';

const _alice = (
  scope: (site: 'https://erp.example/Tenant', user: 'Alice@example.com'),
  rawUser: ' Alice@example.com ',
);
const _bob = (
  scope: (site: 'https://erp.example/Tenant', user: 'Bob'),
  rawUser: 'Bob',
);
const _otherSite = (
  scope: (site: 'https://other.example/Tenant', user: 'Alice@example.com'),
  rawUser: 'Alice@example.com',
);

const _definition = ReportFieldsDefinition(
  id: 'report',
  sections: [(id: 'record', title: 'Record')],
  alwaysShown: 'Item always stays visible.',
  fields: [
    ReportField(
      key: 'item_code',
      column: (fieldname: 'item_code', label: 'Item'),
      section: 'record',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'qty',
      column: (fieldname: 'qty', label: 'Quantity'),
      section: 'record',
      defaultVisible: true,
    ),
    ReportField(
      key: 'uom',
      column: (fieldname: 'uom', label: 'Unit'),
      section: 'record',
      defaultVisible: true,
      requiresKey: 'qty',
    ),
  ],
);

class _Config extends DatabaseService {
  final values = <String, String>{};
  Future<void> Function(String)? beforeRead;
  Future<void> Function(String, String)? beforeWrite;
  final reads = <String>[];
  final writes = <(String, String)>[];

  @override
  Future<String?> getConfig(String key) async {
    reads.add(key);
    await beforeRead?.call(key);
    return values[key];
  }

  @override
  Future<void> saveConfig(String key, String value) async {
    writes.add((key, value));
    await beforeWrite?.call(key, value);
    values[key] = value;
  }
}

class _Storage extends StorageService {
  _Storage() : super.withStorage(null);

  final legacy = <String, Object>{};
  final listeners = <void Function()>{};
  String? site;
  User? user;
  Future<void> Function()? removeToken;

  @override
  String? getBaseUrl() => site;

  @override
  User? getUser() => user;

  @override
  Object? readLegacyReportFields(String reportId) => legacy[reportId];

  @override
  Future<void> clearUserData() async {
    user = null;
    notify();
    await removeToken?.call();
  }

  @override
  Unsubscribe watchReportFieldsOwner(void Function() onChange) {
    listeners.add(onChange);
    return () => listeners.remove(onChange);
  }

  void notify() {
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}

class _LegacyBox extends Fake implements GetStorage {
  final values = <String, Object?>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }
}

class _Owner implements ReportOwnerSource {
  _Owner(this.value);

  FieldsOwner? value;
  Future<FieldsOwner?> Function()? resolving;
  final listeners = <void Function()>{};

  @override
  Future<FieldsOwner?> resolve() async {
    final callback = resolving;
    return callback == null ? value : callback();
  }

  @override
  Unsubscribe watch(void Function() onChange) {
    listeners.add(onChange);
    return () => listeners.remove(onChange);
  }

  void change(FieldsOwner? next) {
    value = next;
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}

void main() {
  late _Config database;
  late _Storage storage;
  late ScopedReportFieldsStore store;
  const configKey = ScopedReportFieldsStore.configKey;
  const variants = 'item_variant_details';
  const variantMarker = 'item_variant_details_fields_legacy_owner';
  const ageing = 'stock_ageing';
  const ageingMarker = 'stock_ageing_fields_legacy_owner';
  const view = ScopedReportFieldsStore.stockAgeingView;

  setUp(() {
    database = _Config();
    storage = _Storage();
    store = ScopedReportFieldsStore(database: database, storage: storage);
  });

  ScopedReportFieldsController controller(
    ReportOwnerSource owner, {
    ReportFieldsDefinition definition = _definition,
  }) {
    final instance = ScopedReportFieldsController(
      definition: definition,
      owner: owner,
      store: store,
    );
    addTearDown(instance.dispose);
    return instance;
  }

  AuthenticationController authentication({ApiProvider? api}) {
    Get.testMode = true;
    addTearDown(Get.reset);
    Get.put<DatabaseService>(database);
    Get.put<ApiProvider>(api ?? FakeApiProvider());
    Get.put<StorageService>(storage);
    return Get.put(AuthenticationController());
  }

  User user(String id) => User(id: id, name: id, email: id, roles: []);

  test('encodes site, user and delimiters independently', () {
    expect(
      configKey(_definition.id, _alice.scope),
      'report_fields::https%3A%2F%2Ferp.example%2FTenant::Alice%40example.com',
    );
    expect(
      configKey('x', (site: 'https://example/T::u', user: 'a::b')),
      'x_fields::https%3A%2F%2Fexample%2FT%3A%3Au::a%3A%3Ab',
    );
    expect(
      configKey('x', _alice.scope),
      isNot(configKey('x', _otherSite.scope)),
    );
    expect(
      configKey('x', _alice.scope),
      isNot(
        configKey('x', (site: _alice.scope.site, user: 'alice@example.com')),
      ),
    );
  });

  test(
    'site and raw authenticated identity are verified independently',
    () async {
      final auth = authentication();
      final owner = StorageReportOwnerSource(
        auth: auth,
        storage: storage,
        database: database,
      );
      storage.user = user(_alice.rawUser);
      database.values[DatabaseService.serverUrlKey] =
          'Erp.Example:443/Tenant///';
      expect(await owner.resolve(), isNull);
      auth.isAuthenticated.value = true;
      expect(await owner.resolve(), _alice);

      var changes = 0;
      final stop = owner.watch(() => changes++);
      addTearDown(stop);
      auth.currentUser.value = user(_alice.rawUser);
      expect(changes, 1);
      storage.site = 'https://un:pw@ERP.EXAMPLE:8443/Tenant/?ignore=123#ignore';
      storage.notify();
      expect(
        (await owner.resolve())?.scope.site,
        'https://erp.example:8443/Tenant',
      );
      auth.currentUser.value = user(_bob.rawUser);
      expect(await owner.resolve(), isNull);
      storage.user = user(_bob.rawUser);
      storage.notify();
      expect((await owner.resolve())?.scope.user, 'Bob');
      auth.currentUser.value = null;
      expect(await owner.resolve(), isNull);
      storage.user = user('Guest');
      auth.currentUser.value = user('Guest');
      expect(await owner.resolve(), isNull);
    },
  );

  test(
    'logout stays session-only through profile removal and failure',
    () async {
      final auth = authentication(api: FakeApiProvider());
      storage.site = _alice.scope.site;
      storage.user = auth.currentUser.value = user(_alice.rawUser);
      auth.isAuthenticated.value = true;
      final fields = controller(
        StorageReportOwnerSource(
          auth: auth,
          storage: storage,
          database: database,
        ),
      );
      final key = configKey(_definition.id, _alice.scope);
      database.values[key] = '{"qty":false}';
      await fields.bind();
      expect(fields.shows('qty'), isFalse);

      final tokenRemoval = Completer<void>();
      final removing = Completer<void>();
      storage.removeToken = () {
        removing.complete();
        return tokenRemoval.future;
      };
      final logout = auth.performLogout();
      expect(fields.scope, isNull);
      await removing.future;
      await fields.bind();
      expect(auth.currentUser.value?.id, _alice.rawUser);
      expect(auth.isAuthenticated.value, isTrue);
      expect(fields.state.value.sessionOnly, isTrue);
      expect(fields.shows('qty'), isTrue);

      tokenRemoval.completeError(StateError('token removal failed'));
      await logout;
      await fields.bind();
      expect(auth.logoutError.value, isNotNull);
      expect(fields.scope, isNull);
      expect(fields.state.value.sessionOnly, isTrue);
      await fields.setVisible('uom', false);
      expect(database.writes, isEmpty);

      storage.user = user(_alice.rawUser);
      storage.notify();
      await fields.bind();
      expect(fields.scope, _alice.scope);
      expect(fields.shows('qty'), isFalse);
      expect(fields.selected('uom'), isTrue);
    },
  );

  test('equivalent site mirror keeps the verified owner generation', () async {
    final auth = authentication();
    storage.site = _alice.scope.site;
    storage.user = auth.currentUser.value = user(_alice.rawUser);
    auth.isAuthenticated.value = true;
    final fields = controller(
      StorageReportOwnerSource(
        auth: auth,
        storage: storage,
        database: database,
      ),
    );
    await fields.bind();
    final generation = fields.ownerGeneration;
    final activeDefinition = _definition.withColumns([
      (fieldname: 'qty', label: 'Quantité'),
    ]);
    fields.replaceDefinition(activeDefinition);
    storage.site = 'https://ERP.EXAMPLE:443/Tenant/';
    storage.notify();
    await fields.bind();
    expect(fields.scope, _alice.scope);
    expect(fields.ownerGeneration, generation);
    expect(fields.state.value.label('qty'), 'Quantité');

    storage.site = 'https://ERP.EXAMPLE:443/tenant/';
    storage.notify();
    expect(fields.scope, isNull);
    expect(fields.ownerGeneration, greaterThan(generation));
    await fields.bind();
    expect(fields.scope?.site, 'https://erp.example/tenant');
  });

  test(
    'single flight loads a sparse immutable selection and merges edits',
    () async {
      final key = configKey(_definition.id, _alice.scope);
      database.values[key] = '{"qty":false,"Future":true,"wrong":2}';
      final first = controller(_Owner(_alice));
      final second = controller(_Owner(_alice));
      await Future.wait([first.bind(), second.bind()]);
      expect(database.reads, [key]);
      expect(first.shows('qty'), isFalse);
      expect(first.selected('uom'), isTrue);
      expect(first.shows('uom'), isFalse);
      expect(first.canEdit('uom'), isFalse);
      expect(
        () => first.state.value.snapshot.overrides['item_code'] = false,
        throwsUnsupportedError,
      );
      await second.setVisible('qty', true);
      expect(first.shows('qty'), isTrue);
      expect(first.shows('uom'), isTrue);
      expect(jsonDecode(database.values[key]!), {'Future': true});
      await first.setVisible('uom', false);
      expect(second.shows('uom'), isFalse);
      await first.resetToDefaults();
      expect(second.shows('uom'), isTrue);
      expect(database.values[key], '{}');
    },
  );

  test('ordered saves retain newer reset and latest error ownership', () async {
    final key = configKey(_definition.id, _alice.scope);
    await store.load(_definition.id, _alice);
    final release = Completer<void>();
    final entered = Completer<void>();
    database.beforeWrite = (_, value) async {
      if (value == '{"qty":false}') {
        entered.complete();
        await release.future;
        throw StateError('older write failed');
      }
    };
    final old = store.edit(_definition.id, _alice.scope, (_) => {'qty': false});
    await entered.future;
    final reset = store.reset(_definition.id, _alice.scope);
    expect(store.snapshot(_definition.id, _alice.scope).overrides, isEmpty);
    expect(store.snapshot(_definition.id, _alice.scope).saving, isTrue);
    release.complete();
    await Future.wait([old, reset]);
    expect(database.values[key], '{}');
    expect(store.snapshot(_definition.id, _alice.scope).failure, isNull);

    database.beforeWrite = (_, _) async =>
        throw StateError('latest write failed');
    await store.edit(_definition.id, _alice.scope, (_) => {'uom': false});
    final failed = store.snapshot(_definition.id, _alice.scope);
    expect(failed.overrides, {'uom': false});
    expect(failed.failure, FieldsFailure.save);
    database.beforeWrite = null;
    await store.retry(_definition.id, _alice);
    expect(store.snapshot(_definition.id, _alice.scope).failure, isNull);
    expect(jsonDecode(database.values[key]!), {'uom': false});
  });

  test('failed read blocks edits and reset until retry', () async {
    final key = configKey(_definition.id, _alice.scope);
    database.values[key] = '{"qty":false}';
    database.beforeRead = (_) async => throw StateError('unavailable');
    final fields = controller(_Owner(_alice));
    await fields.bind();
    expect(fields.state.value.snapshot.failure, FieldsFailure.load);
    expect(fields.canEdit('qty'), isFalse);
    await fields.setVisible('uom', false);
    await fields.resetToDefaults();
    expect(database.writes, isEmpty);
    expect(database.reads, [key]);
    database.beforeRead = null;
    await fields.retry();
    expect(fields.shows('qty'), isFalse);
  });

  test(
    'failed site lookup blocks edits and retries owner resolution',
    () async {
      final auth = authentication();
      storage.user = auth.currentUser.value = user(_alice.rawUser);
      auth.isAuthenticated.value = true;
      database.values[DatabaseService.serverUrlKey] = _alice.scope.site;
      final key = configKey(_definition.id, _alice.scope);
      database.values[key] = '{"qty":false}';
      final fields = controller(
        StorageReportOwnerSource(
          auth: auth,
          storage: storage,
          database: database,
        ),
      );
      database.beforeRead = (key) async {
        if (key == DatabaseService.serverUrlKey) {
          throw StateError('unavailable');
        }
      };
      await fields.bind();
      expect(fields.state.value.sessionOnly, isFalse);
      expect(fields.state.value.snapshot.failure, FieldsFailure.load);
      expect(fields.canEdit('qty'), isFalse);
      await fields.setVisible('qty', false);
      await fields.resetToDefaults();
      expect(database.reads, [DatabaseService.serverUrlKey]);

      database.beforeRead = null;
      await fields.retry();
      expect(fields.scope, _alice.scope);
      expect(fields.shows('qty'), isFalse);

      database.beforeRead = (_) async => throw StateError('unavailable');
      await fields.setVisible('qty', true);
      expect(fields.state.value.snapshot.failure, FieldsFailure.load);
      expect(database.values[key], '{"qty":false}');
      expect(database.writes, isEmpty);

      database.beforeRead = null;
      database.values.remove(DatabaseService.serverUrlKey);
      await fields.retry();
      expect(fields.state.value.snapshot.failure, isNull);
      expect(fields.state.value.sessionOnly, isTrue);
      expect(fields.canEdit('qty'), isTrue);
    },
  );

  test(
    'two mounted controllers order edits before owner verification',
    () async {
      final firstOwner = _Owner(_alice);
      final first = controller(firstOwner);
      final second = controller(_Owner(_alice));
      await Future.wait([first.bind(), second.bind()]);
      final resolving = Completer<FieldsOwner?>();
      final entered = Completer<void>();
      firstOwner.resolving = () {
        entered.complete();
        return resolving.future;
      };
      final toggle = first.setVisible('qty', false);
      await entered.future;
      final reset = second.resetToDefaults();
      await Future<void>.delayed(Duration.zero);
      resolving.complete(_alice);
      await Future.wait([toggle, reset]);
      expect(first.shows('qty'), isTrue);
      expect(second.shows('qty'), isTrue);
      final key = configKey(_definition.id, _alice.scope);
      expect(database.writes, [(key, '{"qty":false}'), (key, '{}')]);
      expect(database.values[key], '{}');
    },
  );

  test(
    'rebinding ignores old writes and isolates users, sites and local edits',
    () async {
      final owner = _Owner(null);
      final fields = controller(owner);
      await fields.bind();
      expect(fields.state.value.sessionOnly, isTrue);
      await fields.setVisible('qty', false);
      expect(fields.shows('qty'), isFalse);
      owner.change(_alice);
      await fields.bind();
      expect(fields.shows('qty'), isTrue);
      final aliceKey = configKey(_definition.id, _alice.scope);
      final entered = Completer<void>();
      final release = Completer<void>();
      database.beforeWrite = (key, _) async {
        if (key != aliceKey) return;
        entered.complete();
        await release.future;
      };
      final write = fields.setVisible('qty', false);
      await entered.future;
      expect(fields.shows('qty'), isFalse);
      final generation = fields.ownerGeneration;
      owner.change(_bob);
      expect(fields.ownerGeneration, greaterThan(generation));
      await fields.bind();
      expect(fields.shows('qty'), isTrue);
      release.complete();
      await write;
      expect(fields.shows('qty'), isTrue);
      expect(database.values[aliceKey], '{"qty":false}');
      owner.change(_otherSite);
      await fields.bind();
      expect(fields.shows('qty'), isTrue);
      owner.change(_alice);
      await fields.bind();
      expect(fields.shows('qty'), isFalse);
    },
  );

  test(
    'old owner resolution and read callbacks cannot replace a new binding',
    () async {
      final aliceKey = configKey(_definition.id, _alice.scope);
      final otherKey = configKey(_definition.id, _otherSite.scope);
      database.values[aliceKey] = '{"qty":false}';
      database.values[otherKey] = '{"uom":false}';
      final owner = _Owner(_alice);
      final resolving = Completer<FieldsOwner?>();
      owner.resolving = () => resolving.future;
      final fields = controller(owner);
      final stale = fields.bind();
      owner.resolving = null;
      owner.change(_bob);
      await fields.bind();
      resolving.complete(_alice);
      await stale;
      expect(fields.scope, _bob.scope);

      final readGate = Completer<void>();
      final entered = Completer<void>();
      database.beforeRead = (key) async {
        if (key != aliceKey) return;
        entered.complete();
        await readGate.future;
      };
      owner.change(_alice);
      final reading = fields.bind();
      await entered.future;
      owner.change(_otherSite);
      await fields.bind();
      expect(fields.selected('qty'), isTrue);
      readGate.complete();
      await reading;
      expect(fields.scope, _otherSite.scope);
      expect(fields.selected('qty'), isTrue);
      expect(fields.selected('uom'), isFalse);
      expect(fields.state.value.snapshot.overrides, {'uom': false});
      expect(database.values, {
        aliceKey: '{"qty":false}',
        otherKey: '{"uom":false}',
      });
      expect(database.writes, isEmpty);
      owner.change(_alice);
      await fields.bind();
      expect(fields.selected('qty'), isFalse);
      expect(fields.state.value.snapshot.overrides, {'qty': false});
    },
  );

  test('a late legacy payload keeps the newly bound owner selection', () async {
    final aliceKey = configKey(variants, _alice.scope);
    final bobKey = configKey(variants, _bob.scope);
    database.values[bobKey] = '{"uom":false}';
    await store.load(variants, _bob);
    storage.legacy[variants] = {'qty': false};
    final entered = Completer<void>();
    final release = Completer<void>();
    database.beforeWrite = (key, _) async {
      if (key == aliceKey) {
        entered.complete();
        await release.future;
      }
    };
    final owner = _Owner(_alice);
    final fields = controller(
      owner,
      definition: ReportFieldsDefinition(
        id: variants,
        sections: _definition.sections,
        fields: _definition.fields,
        alwaysShown: _definition.alwaysShown,
      ),
    );
    final migrating = fields.bind();
    await entered.future;

    owner.change(_bob);
    await fields.bind();
    expect(fields.selected('qty'), isTrue);
    release.complete();
    await migrating;
    expect(fields.scope, _bob.scope);
    expect(fields.selected('qty'), isTrue);
    expect(fields.selected('uom'), isFalse);
    expect(fields.state.value.snapshot.overrides, {'uom': false});
    expect(database.values[aliceKey], '{"qty":false}');
    expect(database.values[bobKey], '{"uom":false}');

    owner.change(_alice);
    await fields.bind();
    expect(fields.scope, _alice.scope);
    expect(fields.selected('qty'), isFalse);
    expect(fields.state.value.snapshot.overrides, {'qty': false});
  });

  test('cold upgrade imports both released GetStorage keys once', () async {
    final box = _LegacyBox()
      ..values['ivd_fields'] = <String, bool>{'Model': false}
      ..values['sa_card_columns'] = <String>['average_age', 'brand'];
    final upgraded = ScopedReportFieldsStore(
      database: database,
      storage: StorageService.withStorage(box),
    );
    for (final id in [variants, ageing, view]) {
      await upgraded.load(id, _alice);
      await upgraded.load(id, _bob);
      expect(upgraded.snapshot(id, _bob.scope).overrides, isEmpty);
      expect(database.values[configKey(id, _bob.scope)], isNull);
    }
    expect(upgraded.snapshot(variants, _alice.scope).overrides, {
      'Model': false,
    });
    expect(upgraded.snapshot(ageing, _alice.scope).overrides, {
      'variant_of': false,
      'item_name': false,
      'warehouse': false,
      'brand': true,
    });
    expect(upgraded.snapshot(view, _alice.scope).overrides, {'ageBar': false});
    await upgraded.edit(variants, _alice.scope, (_) => {'Model': true});
    await upgraded.reset(ageing, _alice.scope);
    expect(
      database.values[configKey(variants, _alice.scope)],
      '{"Model":true}',
    );
    expect(database.values[configKey(ageing, _alice.scope)], '{}');
    expect(box.values, {
      'ivd_fields': {'Model': false},
      'sa_card_columns': ['average_age', 'brand'],
    });
  });

  test(
    'empty variant legacy is authoritative and claims only one scope',
    () async {
      storage.legacy[variants] = <String, bool>{};
      await Future.wait([
        store.load(variants, _alice),
        store.load(variants, _bob),
      ]);
      expect(database.values[configKey(variants, _alice.scope)], '{}');
      expect(database.values[configKey(variants, _bob.scope)], isNull);
      expect(database.values[variantMarker], contains('Alice%40example.com'));
      expect(storage.legacy[variants], isEmpty);
    },
  );

  for (final existing in ['{}', 'bad json']) {
    test(
      'first opener claims legacy while retaining variant $existing',
      () async {
        final aliceKey = configKey(variants, _alice.scope);
        database.values[aliceKey] = existing;
        storage.legacy[variants] = {
          'item_code': false,
          'Future': true,
          'bad': 3,
        };
        await store.load(variants, _alice);
        expect(store.snapshot(variants, _alice.scope).overrides, isEmpty);
        expect(database.values[aliceKey], existing);
        expect(database.values[variantMarker], contains('Alice%40example.com'));
        await store.load(variants, _bob);
        expect(database.values[configKey(variants, _bob.scope)], isNull);
        expect(store.snapshot(variants, _bob.scope).overrides, isEmpty);
      },
    );
  }

  test(
    'first opener claims Ageing with both scoped destinations present',
    () async {
      final fieldsKey = configKey(ageing, _alice.scope);
      final viewKey = configKey(view, _alice.scope);
      database.values[fieldsKey] = '{}';
      database.values[viewKey] = '{"ageBar":true}';
      storage.legacy[ageing] = <String>[];
      await store.load(view, _alice);
      expect(database.values[ageingMarker], contains('Alice%40example.com'));
      await store.load(ageing, _bob);
      await store.load(view, _bob);
      expect(database.values[fieldsKey], '{}');
      expect(database.values[viewKey], '{"ageBar":true}');
      expect(store.snapshot(ageing, _bob.scope).overrides, isEmpty);
      expect(store.snapshot(view, _bob.scope).overrides, isEmpty);
    },
  );

  test(
    'marker-only restart recovers after a different owner read fails',
    () async {
      final aliceKey = configKey(variants, _alice.scope);
      final bobKey = configKey(variants, _bob.scope);
      storage.legacy[variants] = {'Model': false};
      database.beforeWrite = (key, _) async {
        if (key == bobKey) throw StateError('payload write rejected');
      };
      await store.load(variants, _bob);
      expect(database.values[variantMarker], endsWith('::Bob'));
      expect(database.values[bobKey], isNull);

      database.beforeWrite = null;
      database.beforeRead = (key) async {
        if (key == aliceKey) throw StateError('competing read failed');
      };
      final restarted = ScopedReportFieldsStore(
        database: database,
        storage: storage,
      );
      await restarted.load(variants, _alice);
      expect(
        restarted.snapshot(variants, _alice.scope).failure,
        FieldsFailure.load,
      );
      await restarted.load(variants, _bob);
      await restarted.edit(
        variants,
        _bob.scope,
        (latest) => {...latest, 'Other': false},
      );

      final reopened = ScopedReportFieldsStore(
        database: database,
        storage: storage,
      );
      await reopened.load(variants, _bob);
      expect(reopened.snapshot(variants, _bob.scope).overrides, {
        'Model': false,
        'Other': false,
      });
    },
  );

  test('failed legacy claim reserves the same claimant until retry', () async {
    storage.legacy[variants] = {'Model': false};
    database.beforeWrite = (key, _) async {
      if (key == variantMarker) throw StateError('claim rejected');
    };
    await Future.wait([
      store.load(variants, _alice),
      store.load(variants, _bob),
    ]);
    expect(store.snapshot(variants, _alice.scope).failure, FieldsFailure.load);
    expect(store.snapshot(variants, _bob.scope).loaded, isTrue);
    expect(database.values[variantMarker], isNull);
    database.beforeWrite = null;
    await store.retry(variants, _alice);
    expect(store.snapshot(variants, _alice.scope).overrides, {'Model': false});
    expect(database.values[configKey(variants, _bob.scope)], isNull);
  });

  test(
    'Ageing restarts after a partial claim without replacing Fields',
    () async {
      storage.legacy[ageing] = <String>[];
      final fieldsKey = configKey(ageing, _alice.scope);
      final viewKey = configKey(view, _alice.scope);
      database.beforeWrite = (key, _) async {
        if (key == viewKey) throw StateError('view write rejected');
      };
      await store.load(ageing, _alice);
      expect(store.snapshot(ageing, _alice.scope).failure, FieldsFailure.load);
      expect(database.values[ageingMarker], contains('Alice%40example.com'));
      expect(jsonDecode(database.values[fieldsKey]!), {
        'variant_of': false,
        'item_name': false,
        'warehouse': false,
        'average_age': false,
      });
      database.values[fieldsKey] = '{}';
      final writesBeforeRestart = database.writes.length;
      database.beforeWrite = null;
      final reopened = ScopedReportFieldsStore(
        database: database,
        storage: storage,
      );
      await reopened.load(view, _bob);
      expect(database.values[configKey(view, _bob.scope)], isNull);
      await reopened.load(view, _alice);
      expect(database.values[viewKey], '{"ageBar":false}');
      await reopened.load(ageing, _alice);
      expect(reopened.snapshot(ageing, _alice.scope).overrides, isEmpty);
      expect(database.values[fieldsKey], '{}');
      expect(database.writes.skip(writesBeforeRestart), [
        (viewKey, '{"ageBar":false}'),
      ]);
      await reopened.reset(ageing, _alice.scope);
      expect(database.values[fieldsKey], '{}');
      expect(database.values[viewKey], '{"ageBar":false}');
    },
  );

  test(
    'Ageing retains a scoped View and migrates positive dynamic choices',
    () async {
      database.values[configKey(view, _alice.scope)] = '{"ageBar":false}';
      storage.legacy[ageing] = [
        '_age_bar',
        'item_code',
        'average_age',
        'extra',
      ];
      await store.load(ageing, _alice);
      expect(store.snapshot(ageing, _alice.scope).overrides, {
        'variant_of': false,
        'item_name': false,
        'warehouse': false,
        'extra': true,
      });
      expect(
        database.values[configKey(view, _alice.scope)],
        '{"ageBar":false}',
      );
    },
  );

  test('invalid Ageing legacy data never opens a claim', () async {
    storage.legacy[ageing] = [1, false];
    await store.load(ageing, _alice);
    expect(store.snapshot(ageing, _alice.scope).overrides, isEmpty);
    expect(database.writes, isEmpty);
  });

  test('descriptor labels preserve case and positional indices', () {
    final columns = decodeDeskColumns([
      {'fieldname': 'Model', 'label': 'Modèle'},
      null,
      'Balance Qty:Float:120',
      {'fieldname': 'model', 'label': 'Model'},
      '`tabStock Ledger Entry`.item_code',
    ]);
    expect(columns[0], (fieldname: 'Model', label: 'Modèle'));
    expect(columns[2], (fieldname: 'balance_qty', label: 'Balance Qty'));
    expect(columns[4], (fieldname: 'item_code', label: ''));
    expect(decodeDeskRow([1, 'ignored', 0, 3, 'item'], columns), {
      'Model': 1,
      'balance_qty': 0,
      'model': 3,
      'item_code': 'item',
    });
    expect(decodeDeskRow({'Model': 1, 'model': 3}, columns), {
      'Model': 1,
      'model': 3,
    });
    final adapted = _definition.withColumns([
      (fieldname: 'qty', label: 'Quantité'),
    ]);
    expect(adapted.fields.map((field) => field.key), ['item_code', 'qty']);
    expect(adapted.label('qty'), 'Quantité');
    expect(adapted.label('uom'), 'Unit');
  });
}
