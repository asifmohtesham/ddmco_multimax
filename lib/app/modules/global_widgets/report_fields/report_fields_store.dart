import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../../data/services/database_service.dart';
import '../../../data/services/storage_service.dart';
import '../../auth/authentication_controller.dart';
import 'report_field.dart';

abstract interface class ReportOwnerSource {
  Future<FieldsOwner?> resolve();
  Unsubscribe watch(void Function() onChange);
}

typedef _OwnerInputs = ({
  bool signedIn,
  bool loggingOut,
  String? current,
  String? stored,
  String? site,
});

class StorageReportOwnerSource implements ReportOwnerSource {
  StorageReportOwnerSource({
    required AuthenticationController auth,
    required StorageService storage,
    DatabaseService? database,
    FutureOr<String?> Function()? siteResolver,
  }) : _auth = auth,
       _storage = storage,
       _database = database,
       _siteResolver = siteResolver;

  final AuthenticationController _auth;
  final StorageService _storage;
  final DatabaseService? _database;
  final FutureOr<String?> Function()? _siteResolver;
  bool _cacheFallbackAllowed = true;
  bool _hadSynchronizedProfile = false;

  String? _cachedUser() {
    try {
      return _storage.getUser()?.id;
    } catch (_) {
      return null;
    }
  }

  _OwnerInputs _inputs() => (
    signedIn: _auth.isAuthenticated.value,
    loggingOut: _auth.isLoggingOut.value,
    current: _auth.currentUser.value?.id,
    stored: _cachedUser(),
    site: _storage.getBaseUrl(),
  );

  String? _verifiedUser(_OwnerInputs inputs) {
    if (inputs.current != null || inputs.loggingOut) {
      _cacheFallbackAllowed = false;
    }
    if (!inputs.signedIn || inputs.loggingOut) return null;
    final rawUser =
        inputs.current ?? (_cacheFallbackAllowed ? inputs.stored : null);
    final user = rawUser?.trim();
    if (rawUser == null ||
        user == null ||
        user.isEmpty ||
        user.toLowerCase() == 'guest' ||
        (inputs.stored == null
            ? _hadSynchronizedProfile
            : inputs.stored!.trim() != user)) {
      return null;
    }
    if (inputs.current != null && inputs.stored != null) {
      _hadSynchronizedProfile = true;
    }
    return rawUser;
  }

  /// Verifies a scope using the live session and URL mirror. If either input
  /// needs a fallback lookup, the caller must use [resolve].
  bool matchesCurrentScope(FieldsScope scope) {
    if (_siteResolver != null) return false;
    try {
      final inputs = _inputs();
      return _verifiedUser(inputs)?.trim() == scope.user &&
          normalizeSuppliersByItemSite(inputs.site) == scope.site;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<FieldsOwner?> resolve() async {
    final inputs = _inputs();
    final rawUser = _verifiedUser(inputs);
    if (rawUser == null) return null;
    var configuredUrl = inputs.site;
    if (_siteResolver case final resolve?) {
      configuredUrl = await resolve();
      if (_inputs() != inputs) return null;
    } else if (configuredUrl == null || configuredUrl.trim().isEmpty) {
      final database = _database;
      configuredUrl = database == null
          ? await _storage.getSuppliersByItemSite()
          : await database.getConfig(DatabaseService.serverUrlKey);
      if (_inputs() != inputs) return null;
    }
    final site = normalizeSuppliersByItemSite(configuredUrl);
    return site == null
        ? null
        : (scope: (site: site, user: rawUser.trim()), rawUser: rawUser);
  }

  @override
  Unsubscribe watch(void Function() onChange) {
    var previous = _inputs();
    _verifiedUser(previous);
    void changed() {
      final next = _inputs();
      if (previous == next) return;
      if (previous.signedIn && !next.signedIn) {
        _cacheFallbackAllowed = false;
      }
      final rawUser = _verifiedUser(next);
      final previousSite = normalizeSuppliersByItemSite(previous.site);
      final sameOwner =
          _siteResolver == null &&
          previous.signedIn == next.signedIn &&
          previous.loggingOut == next.loggingOut &&
          previous.current == next.current &&
          previous.stored == next.stored &&
          rawUser != null &&
          previousSite != null &&
          previousSite == normalizeSuppliersByItemSite(next.site);
      previous = next;
      if (!sameOwner) onChange();
    }

    final user = ever(_auth.currentUser, (_) => changed());
    final signedIn = ever(_auth.isAuthenticated, (_) => changed());
    final loggingOut = ever(_auth.isLoggingOut, (_) => changed());
    final storage = _storage.watchReportFieldsOwner(changed);
    return () {
      user.dispose();
      signedIn.dispose();
      loggingOut.dispose();
      storage();
    };
  }
}

abstract interface class ReportFieldsStore {
  Future<void> load(String id, FieldsOwner owner);
  FieldsSnapshot snapshot(String id, FieldsScope scope);
  Unsubscribe watch(
    String id,
    FieldsScope scope,
    void Function(FieldsSnapshot) listener,
  );
  Future<void> edit(String id, FieldsScope scope, EditFields apply);
  Future<void> reset(String id, FieldsScope scope);
  Future<void> retry(String id, FieldsOwner owner);
  Future<void> sequenceEdit(
    String id,
    FieldsScope scope,
    Future<bool> Function() verify,
    Future<void> Function() apply,
  );
}

class _FieldsRecord {
  Map<String, bool> overrides = const {};
  int revision = 0;
  int writeRevision = 0;
  bool loaded = false;
  int pendingWrites = 0;
  FieldsFailure? failure;
  Future<void>? loading;
  Future<void> edits = Future.value();
  Future<void> writes = Future.value();
  final listeners = <void Function(FieldsSnapshot)>{};

  FieldsSnapshot get snapshot => (
    overrides: overrides,
    revision: revision,
    loaded: loaded,
    saving: pendingWrites > 0,
    failure: failure,
  );

  void publish() {
    revision++;
    final current = snapshot;
    for (final listener in listeners.toList()) {
      if (listeners.contains(listener)) listener(current);
    }
  }
}

class _LegacyClaim {
  Future<void> operation = Future.value();
  String? pendingOwner;
}

class ScopedReportFieldsStore implements ReportFieldsStore {
  ScopedReportFieldsStore({
    required DatabaseService database,
    required StorageService storage,
  }) : _database = database,
       _storage = storage;

  /// Stock Ageing's independent View setting uses the same load/save queue
  /// and owner binding as Fields, with its own durable config key.
  static const stockAgeingView = 'stock_ageing_view';
  static const _stockAgeing = 'stock_ageing';
  static const _itemVariants = 'item_variant_details';

  final DatabaseService _database;
  final StorageService _storage;
  final _records = <(String, FieldsScope), _FieldsRecord>{};
  final _claims = <String, _LegacyClaim>{};

  static String _ownerKey(FieldsScope scope) =>
      '${Uri.encodeComponent(scope.site)}::${Uri.encodeComponent(scope.user)}';

  static String configKey(String id, FieldsScope scope) {
    final prefix = id == stockAgeingView ? id : '${id}_fields';
    return '$prefix::${_ownerKey(scope)}';
  }

  _FieldsRecord _record(String id, FieldsScope scope) =>
      _records.putIfAbsent((id, scope), _FieldsRecord.new);

  @override
  FieldsSnapshot snapshot(String id, FieldsScope scope) =>
      _record(id, scope).snapshot;

  @override
  Unsubscribe watch(
    String id,
    FieldsScope scope,
    void Function(FieldsSnapshot) listener,
  ) {
    final listeners = _record(id, scope).listeners;
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  Future<void> load(String id, FieldsOwner owner) {
    final record = _record(id, owner.scope);
    if (record.loaded || record.failure == FieldsFailure.load) {
      return Future.value();
    }
    return _startLoad(id, owner, record);
  }

  Future<void> _startLoad(String id, FieldsOwner owner, _FieldsRecord record) =>
      record.loading ??= _read(id, owner, record).whenComplete(() {
        record.loading = null;
      });

  Future<void> _read(String id, FieldsOwner owner, _FieldsRecord record) async {
    try {
      final String? stored;
      if (id == _itemVariants || id == _stockAgeing || id == stockAgeingView) {
        stored = await _readWithLegacy(id, owner.scope);
      } else {
        stored = await _database.getConfig(configKey(id, owner.scope));
      }
      record.overrides = _decode(stored);
      record.loaded = true;
      record.failure = null;
    } catch (_) {
      record.failure = FieldsFailure.load;
    }
    record.publish();
  }

  Future<String?> _readWithLegacy(String id, FieldsScope scope) {
    final source = id == stockAgeingView ? _stockAgeing : id;
    final claim = _claims.putIfAbsent(source, _LegacyClaim.new);
    final result = claim.operation.then(
      (_) => _migrate(source, id, scope, claim),
    );
    claim.operation = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String?> _migrate(
    String source,
    String id,
    FieldsScope scope,
    _LegacyClaim claim,
  ) async {
    final key = configKey(id, scope);
    final fieldsKey = configKey(source, scope);
    final viewKey = source == _stockAgeing
        ? configKey(stockAgeingView, scope)
        : null;
    final ownerKey = _ownerKey(scope);
    final markerKey = '${source}_fields_legacy_owner';
    final payload = _legacyPayload(source);
    if (payload == null) return _database.getConfig(key);

    // Reserve the first opener through failures before a durable claim.
    final reserved = claim.pendingOwner ??= ownerKey;
    final marker = await _database.getConfig(markerKey);
    if (marker != null) claim.pendingOwner = null;
    if ((marker ?? reserved) != ownerKey) return _database.getConfig(key);
    final fields = await _database.getConfig(fieldsKey);
    final view = viewKey == null ? null : await _database.getConfig(viewKey);
    if (marker == null) await _database.saveConfig(markerKey, ownerKey);
    if (fields == null) await _database.saveConfig(fieldsKey, payload.fields);
    if (viewKey != null && view == null) {
      await _database.saveConfig(viewKey, payload.view!);
    }
    claim.pendingOwner = null;
    return id == stockAgeingView
        ? view ?? payload.view
        : fields ?? payload.fields;
  }

  ({String fields, String? view})? _legacyPayload(String source) {
    final raw = _storage.readLegacyReportFields(source);
    if (source == _itemVariants) {
      return raw is Map
          ? (fields: jsonEncode(_booleans(raw)), view: null)
          : null;
    }
    if (raw is! List || raw.any((value) => value is! String)) return null;
    const previousDefaults = {
      'variant_of',
      'item_name',
      'warehouse',
      'average_age',
    };
    const previouslyFixed = {'item_code', 'qty', 'uom', '_age_bar'};
    final selected = raw.cast<String>().toSet();
    return (
      fields: jsonEncode({
        for (final key in previousDefaults.difference(selected)) key: false,
        for (final key
            in selected
                .difference(previousDefaults)
                .difference(previouslyFixed))
          key: true,
      }),
      view: jsonEncode({'ageBar': selected.contains('_age_bar')}),
    );
  }

  static Map<String, bool> _booleans(Map values) => Map.unmodifiable({
    for (final entry in values.entries)
      if (entry.key is String && entry.value is bool)
        entry.key as String: entry.value as bool,
  });

  static Map<String, bool> _decode(String? stored) {
    if (stored == null) return const {};
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map ? _booleans(decoded) : const {};
    } on FormatException {
      return const {};
    }
  }

  @override
  Future<void> edit(String id, FieldsScope scope, EditFields apply) {
    final record = _record(id, scope);
    if (!record.loaded) return Future.value();
    final next = apply(record.overrides);
    return next == null ? Future.value() : _save(id, scope, record, next);
  }

  @override
  Future<void> reset(String id, FieldsScope scope) {
    final record = _record(id, scope);
    return record.loaded ? _save(id, scope, record, const {}) : Future.value();
  }

  @override
  Future<void> sequenceEdit(
    String id,
    FieldsScope scope,
    Future<bool> Function() verify,
    Future<void> Function() apply,
  ) {
    final record = _record(id, scope);
    Future<void>? write;
    final dispatch = record.edits.then((_) async {
      if (await verify()) write = apply();
    });
    // Dispatch the next verified edit without waiting for disk. The write
    // queue persists their optimistic snapshots in the same order.
    record.edits = dispatch.then((_) {}, onError: (Object _) {});
    return dispatch.then((_) => write);
  }

  @override
  Future<void> retry(String id, FieldsOwner owner) {
    final record = _record(id, owner.scope);
    return switch (record.failure) {
      FieldsFailure.load => _startLoad(id, owner, record),
      FieldsFailure.save when record.pendingWrites == 0 => _save(
        id,
        owner.scope,
        record,
        record.overrides,
      ),
      _ => Future.value(),
    };
  }

  Future<void> _save(
    String id,
    FieldsScope scope,
    _FieldsRecord record,
    Map<String, bool> values,
  ) {
    final overrides = Map<String, bool>.unmodifiable(values);
    final writeRevision = ++record.writeRevision;
    record.overrides = overrides;
    record.pendingWrites++;
    final write = record.writes.then((_) async {
      try {
        await _database.saveConfig(configKey(id, scope), jsonEncode(overrides));
        if (writeRevision == record.writeRevision) record.failure = null;
      } catch (_) {
        if (writeRevision == record.writeRevision) {
          record.failure = FieldsFailure.save;
        }
      } finally {
        record.pendingWrites--;
        record.publish();
      }
    });
    record.writes = write;
    record.publish();
    return write;
  }
}
