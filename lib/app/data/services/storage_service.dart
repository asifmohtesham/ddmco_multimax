import 'dart:convert';

import 'package:multimax/app/data/models/suppliers_by_item_view.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/recent_searches.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

typedef SuppliersByItemFieldsScope = ({String site, String user});

enum SuppliersByItemFieldsFailure { load, save }

class SuppliersByItemFieldsSnapshot {
  const SuppliersByItemFieldsSnapshot({
    required this.overrides,
    required this.revision,
    required this.loaded,
    required this.saving,
    required this.failure,
  });

  final Map<String, bool> overrides;
  final int revision;
  final bool loaded;
  final bool saving;
  final SuppliersByItemFieldsFailure? failure;
}

class SuppliersByItemViewSnapshot {
  const SuppliersByItemViewSnapshot({
    required this.view,
    required this.revision,
    required this.loaded,
    required this.saving,
    required this.failure,
  });

  final SuppliersByItemView view;
  final int revision;
  final bool loaded;
  final bool saving;
  final SuppliersByItemFieldsFailure? failure;
}

/// Produces the active ERP site identity used in preference keys.
String? normalizeSuppliersByItemSite(String? configuredUrl) {
  final value = configuredUrl?.trim() ?? '';
  if (value.isEmpty) return null;
  final hasScheme = RegExp(r'^[a-z][a-z\d+.-]*:', caseSensitive: false);
  final isHostWithPort = RegExp(r'^[^:/?#]+:\d+(?:[/#?]|$)');
  final isWebUrl = RegExp(r'^https?://', caseSensitive: false);
  if (hasScheme.hasMatch(value) &&
      !isWebUrl.hasMatch(value) &&
      !isHostWithPort.hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(isWebUrl.hasMatch(value) ? value : 'https://$value');
  if (uri == null || uri.host.isEmpty || uri.host.contains('%')) return null;
  final origin = uri.origin;
  return origin + uri.path.replaceFirst(RegExp(r'/+$'), '');
}

abstract class _SuppliersByItemRecord<T, S> {
  _SuppliersByItemRecord(this.value);

  T value;
  int revision = 0;
  int writeRevision = 0;
  bool loaded = false;
  int pendingWrites = 0;
  SuppliersByItemFieldsFailure? failure;
  Future<void>? loading;
  Future<void> writes = Future.value();
  final listeners = <void Function(S)>{};

  S get snapshot;

  void publish() {
    revision++;
    final current = snapshot;
    for (final listener in listeners.toList()) {
      listener(current);
    }
  }

  void Function() watch(void Function(S) onChange) {
    listeners.add(onChange);
    return () => listeners.remove(onChange);
  }

  Future<void> save(T next, Future<void> Function() writeValue) async {
    final revision = ++writeRevision;
    value = next;
    pendingWrites++;
    final write = writes.then((_) async {
      try {
        await writeValue();
        if (revision == writeRevision) failure = null;
      } catch (_) {
        if (revision == writeRevision) {
          failure = SuppliersByItemFieldsFailure.save;
        }
        rethrow;
      } finally {
        pendingWrites--;
        publish();
      }
    });
    writes = write.then((_) {}, onError: (Object _) {});
    publish();
    await write;
  }
}

class _SuppliersByItemFieldsRecord
    extends
        _SuppliersByItemRecord<
          Map<String, bool>,
          SuppliersByItemFieldsSnapshot
        > {
  _SuppliersByItemFieldsRecord() : super(const {});

  @override
  SuppliersByItemFieldsSnapshot get snapshot => SuppliersByItemFieldsSnapshot(
    overrides: value,
    revision: revision,
    loaded: loaded,
    saving: pendingWrites > 0,
    failure: failure,
  );
}

class _SuppliersByItemViewRecord
    extends
        _SuppliersByItemRecord<
          SuppliersByItemView,
          SuppliersByItemViewSnapshot
        > {
  _SuppliersByItemViewRecord() : super(const SuppliersByItemView());

  @override
  SuppliersByItemViewSnapshot get snapshot => SuppliersByItemViewSnapshot(
    view: value,
    revision: revision,
    loaded: loaded,
    saving: pendingWrites > 0,
    failure: failure,
  );
}

class _SuppliersByItemMigration {
  Future<void> operation = Future.value();
  String? pendingClaimSite;
}

class StorageService {
  final dynamic _box;
  final DatabaseService? _database;
  final _suppliersByItemFields =
      <SuppliersByItemFieldsScope, _SuppliersByItemFieldsRecord>{};
  final _suppliersByItemViews =
      <SuppliersByItemFieldsScope, _SuppliersByItemViewRecord>{};
  final _suppliersByItemMigrations = <String, _SuppliersByItemMigration>{};

  StorageService({DatabaseService? database})
    : _box = GetStorage(),
      _database = database;

  // Internal constructor for testing - allows injection of a custom storage instance
  StorageService.withStorage(this._box, {DatabaseService? database})
    : _database = database;

  DatabaseService? get _configStore =>
      _database ??
      (Get.isRegistered<DatabaseService>()
          ? Get.find<DatabaseService>()
          : null);

  // Keys
  static const String _userKey = 'currentUser';
  static const String _tokenKey = 'apiToken';
  static const String _baseUrlKey = 'baseUrl';

  // Session Defaults Keys
  static const String _companyKey = 'session_company';

  // Auto Submit Keys
  static const String _autoSubmitEnabledKey = 'auto_submit_enabled';
  static const String _autoSubmitDelayKey = 'auto_submit_delay';

  // Auto Save Keys
  static const String _autoSaveDelayKey = 'auto_save_delay';

  // Default Warehouse (optional; unset = no Stock Balance search shortcut)
  static const String _defaultWarehouseKey = 'session_default_warehouse';

  // Stock Balance view preferences
  static const String _sbHideEmptyKey = 'sb_hide_empty';
  static const String _sbShowImagesKey = 'sb_show_images';
  static const String _saCardFieldsKey = 'sa_card_columns';
  static const String _suppliersByItemFieldsKey = 'suppliers_by_item_fields';
  static const String _suppliersByItemViewKey = 'suppliers_by_item_view';

  // Dashboard view preferences
  static const String _dashboardColumnsKey = 'dashboard_columns';
  static const String _dashboardTasksFirstKey = 'dashboard_tasks_first';
  static const _dashboardActionableScopeKey = 'dashboard_actionable_scope';

  // Last drawer layout built from the user's Frappe workspaces, per user.
  static const String _navMenuKey = 'nav_menu';

  // Scheduled digest notification preferences (per user, keyed key::user —
  // same convention as dashboard_tasks_first).
  static const String _digestEnabledKey = 'notif_digest_enabled';
  static const String _digestTimesKey = 'notif_digest_times';
  static const String _digestDaysKey = 'notif_digest_days';
  static const String _digestDoctypesKey = 'notif_digest_doctypes';
  static const String _digestAlarmStyleKey = 'notif_digest_alarm_style';

  // Attendance notification preferences (#2b), per user. Absent = on.
  static const String _attEnabledKey = 'notif_att_enabled';
  static const String _attTerminalKey = 'notif_att_terminal';
  static const String _attPromptedKey = 'notif_att_prompted';

  // Sales Order: last selling price list this user saved an order with
  // (smoke-fix-1, Ruling 9 fallback (b)), per user.
  static const String _soLastPriceListKey = 'so_last_selling_price_list';

  // Stock sheet: the file format of the last Make sheet
  // ('excel' | 'pdf' | 'both').
  static const String _itemsFromPhotosFormatKey = 'stock_sheet_last_format';

  // --- User Data ---
  Future<void> saveUser(User user) async {
    await _box.write(_userKey, user.toJson());
  }

  User? getUser() {
    final userJson = _box.read<Map<String, dynamic>>(_userKey);
    if (userJson != null) {
      return User.fromJson(userJson);
    }
    return null;
  }

  Future<void> clearCachedUser() async {
    await _box.remove(_userKey);
  }

  Future<void> clearUserData() async {
    await clearCachedUser();
    await _box.remove(_tokenKey);
    printInfo(info: "User data cleared from local storage.");
  }

  String _recentSearchesKey(String context, String user) =>
      'recent_searches::$context::$user';

  List<String> getRecentSearches(String context, String user) {
    final raw = _box.read<Object>(_recentSearchesKey(context, user));
    return raw is List ? raw.whereType<String>().toList() : const [];
  }

  Future<void> addRecentSearch(
    String context,
    String user,
    String query, {
    int minLength = 1,
  }) async {
    final current = getRecentSearches(context, user);
    final next = RecentSearches.add(current, query, minLength: minLength);
    if (!identical(current, next)) {
      await _box.write(_recentSearchesKey(context, user), next);
    }
  }

  Future<void> removeRecentSearch(
    String context,
    String user,
    String query,
  ) async {
    final next = RecentSearches.remove(getRecentSearches(context, user), query);
    await _box.write(_recentSearchesKey(context, user), next);
  }

  Future<void> clearRecentSearches(String context, String user) async {
    await _box.write(_recentSearchesKey(context, user), RecentSearches.clear());
  }

  // --- Token ---
  Future<void> saveToken(String token) async {
    await _box.write(_tokenKey, token);
  }

  String? getToken() {
    return _box.read<String>(_tokenKey);
  }

  // --- Server URL ---
  Future<void> saveBaseUrl(String url) async {
    await _box.write(_baseUrlKey, url);
  }

  String? getBaseUrl() {
    return _box.read<String>(_baseUrlKey);
  }

  // --- Session Defaults ---
  Future<void> saveSessionDefaults(String company) async {
    await _box.write(_companyKey, company);
  }

  String getCompany() {
    return _box.read<String>(_companyKey) ?? 'Multimax'; // Default fallback
  }

  bool hasSessionDefaults() {
    return _box.hasData(_companyKey);
  }

  // --- Default Warehouse (optional) ---
  Future<void> saveDefaultWarehouse(String? warehouse) async {
    final w = warehouse?.trim() ?? '';
    if (w.isEmpty) {
      await _box.remove(_defaultWarehouseKey);
    } else {
      await _box.write(_defaultWarehouseKey, w);
    }
  }

  String? getDefaultWarehouse() {
    final w = _box.read<String>(_defaultWarehouseKey);
    return (w == null || w.isEmpty) ? null : w;
  }

  // --- Auto Submit Settings ---
  Future<void> saveAutoSubmitSettings(bool enabled, int delaySeconds) async {
    await _box.write(_autoSubmitEnabledKey, enabled);
    await _box.write(_autoSubmitDelayKey, delaySeconds);
  }

  bool getAutoSubmitEnabled() {
    return _box.read<bool>(_autoSubmitEnabledKey) ?? true; // Default to true
  }

  int getAutoSubmitDelay() {
    return _box.read<int>(_autoSubmitDelayKey) ?? 1; // Default 1 second
  }

  // --- Auto Save Settings ---
  Future<void> saveAutoSaveDelay(int seconds) async =>
      _box.write(_autoSaveDelayKey, seconds);

  int getAutoSaveDelay() => _box.read<int>(_autoSaveDelayKey) ?? 5;

  // --- Stock Balance view preferences ---
  // Persisted so the "Hide empty" / "Images" toggles survive navigation,
  // mirroring the web report's view preferences.
  Future<void> saveSbHideEmpty(bool value) async =>
      _box.write(_sbHideEmptyKey, value);

  bool getSbHideEmpty() => _box.read<bool>(_sbHideEmptyKey) ?? false;

  Future<void> saveSbShowImages(bool value) async =>
      _box.write(_sbShowImagesKey, value);

  bool getSbShowImages() => _box.read<bool>(_sbShowImagesKey) ?? true;

  // --- Stock Ageing report: fields shown on each row card ---
  // Null until the user changes the selection, so the default set applies.
  Future<void> saveStockAgeingCardFields(List<String> fields) async =>
      _box.write(_saCardFieldsKey, fields);

  List<String>? getStockAgeingCardFields() {
    final v = _box.read(_saCardFieldsKey);
    return v is List ? v.map((e) => e.toString()).toList() : null;
  }

  Map<String, bool> _readFieldOverrides(String key) {
    return _fieldOverrides(_box.read(key));
  }

  Map<String, bool> _fieldOverrides(Object? saved) {
    if (saved is! Map) return {};
    return {
      for (final entry in saved.entries)
        if (entry.key is String && entry.value is bool)
          entry.key as String: entry.value as bool,
    };
  }

  Map<String, bool> getItemVariantFields() => _readFieldOverrides('ivd_fields');

  Future<void> saveItemVariantFields(Map<String, bool> fields) async =>
      _box.write('ivd_fields', fields);

  // --- Suppliers by Item report: optional row fields, per site and user ---
  bool get hasSuppliersByItemFieldsStore => _configStore != null;

  Future<String?> getSuppliersByItemSite() async {
    final mirror = getBaseUrl();
    if (mirror != null && mirror.trim().isNotEmpty) return mirror;
    return _configStore?.getConfig(DatabaseService.serverUrlKey);
  }

  void Function()? watchSuppliersByItemFieldsOwner(void Function() onChange) {
    final box = _box;
    if (box is! GetStorage) return null;
    return box.listen(() {
      if (box.changes.containsKey(_baseUrlKey) ||
          box.changes.containsKey(_userKey)) {
        onChange();
      }
    });
  }

  String _scopedSuppliersByItemKey(
    String prefix,
    SuppliersByItemFieldsScope scope,
  ) =>
      '$prefix::${Uri.encodeComponent(scope.site)}'
      '::${Uri.encodeComponent(scope.user)}';

  _SuppliersByItemFieldsRecord _fieldsRecord(
    SuppliersByItemFieldsScope scope,
  ) => _suppliersByItemFields.putIfAbsent(
    scope,
    _SuppliersByItemFieldsRecord.new,
  );

  SuppliersByItemFieldsSnapshot getSuppliersByItemFields(
    SuppliersByItemFieldsScope scope,
  ) => _fieldsRecord(scope).snapshot;

  /// Route controllers on the same scope receive optimistic edits immediately.
  void Function() watchSuppliersByItemFields(
    SuppliersByItemFieldsScope scope,
    void Function(SuppliersByItemFieldsSnapshot) onChange,
  ) => _fieldsRecord(scope).watch(onChange);

  Future<void> loadSuppliersByItemFields(
    SuppliersByItemFieldsScope scope, {
    required String rawUser,
  }) {
    final record = _fieldsRecord(scope);
    if (record.loaded) return Future.value();
    final pending = record.loading;
    if (pending != null) return pending;

    final migration = _suppliersByItemMigrations.putIfAbsent(
      scope.user,
      _SuppliersByItemMigration.new,
    );
    final operation = migration.operation.then(
      (_) => _loadFields(scope, rawUser, record, migration),
    );
    late final Future<void> cleanup;
    cleanup = operation.whenComplete(() {
      record.loading = null;
      if (identical(migration.operation, cleanup) &&
          migration.pendingClaimSite == null) {
        _suppliersByItemMigrations.remove(scope.user);
      }
    });
    record.loading = cleanup;
    migration.operation = cleanup;
    return cleanup;
  }

  Future<void> _loadFields(
    SuppliersByItemFieldsScope scope,
    String rawUser,
    _SuppliersByItemFieldsRecord record,
    _SuppliersByItemMigration migration,
  ) async {
    final database = _configStore!;
    final key = _scopedSuppliersByItemKey(_suppliersByItemFieldsKey, scope);
    final claimKey =
        '${_suppliersByItemFieldsKey}_legacy_owner::${Uri.encodeComponent(scope.user)}';
    String? stored;
    String? claim;
    Object? legacy;
    try {
      stored = await database.getConfig(key);
      legacy = _box.read<Object>('$_suppliersByItemFieldsKey::$rawUser');
      if (legacy is Map) claim = await database.getConfig(claimKey);
    } catch (_) {
      record.failure = SuppliersByItemFieldsFailure.load;
      record.publish();
      return;
    }

    if (claim != null) migration.pendingClaimSite = null;
    final owner = claim ?? migration.pendingClaimSite;
    final eligible = legacy is Map && (owner == null || owner == scope.site);
    final overrides = stored == null && eligible
        ? _fieldOverrides(legacy)
        : _decodeFields(stored);
    try {
      if (eligible && claim == null) {
        // Keep this site eligible for retry even if storage rejects the claim.
        migration.pendingClaimSite = scope.site;
        await database.saveConfig(claimKey, scope.site);
        migration.pendingClaimSite = null;
      }
      if (eligible && stored == null) {
        await database.saveConfig(key, jsonEncode(overrides));
      }
      record.loaded = true;
      record.failure = null;
    } catch (_) {
      record.failure = SuppliersByItemFieldsFailure.save;
    }
    record.value = Map.unmodifiable(overrides);
    record.publish();
  }

  Map<String, bool> _decodeFields(String? stored) {
    if (stored == null) return const {};
    try {
      return _fieldOverrides(jsonDecode(stored));
    } on FormatException {
      return const {};
    }
  }

  /// Merge an edit into the newest optimistic snapshot before enqueueing its
  /// acknowledged write. A reset replaces that snapshot with an empty map.
  Future<void> updateSuppliersByItemFields(
    SuppliersByItemFieldsScope scope,
    Map<String, bool>? Function(Map<String, bool>) edit,
  ) {
    final updated = edit(_fieldsRecord(scope).value);
    return updated == null
        ? Future.value()
        : saveSuppliersByItemFields(scope, updated);
  }

  Future<void> saveSuppliersByItemFields(
    SuppliersByItemFieldsScope scope,
    Map<String, bool> fields,
  ) async {
    final record = _fieldsRecord(scope);
    if (!record.loaded) throw StateError('Fields have not loaded');
    final database = _configStore!;
    final key = _scopedSuppliersByItemKey(_suppliersByItemFieldsKey, scope);
    final overrides = Map<String, bool>.unmodifiable(fields);
    await record.save(
      overrides,
      () => database.saveConfig(key, jsonEncode(overrides)),
    );
  }

  // --- Suppliers by Item report: independent grouping and sort preferences ---
  _SuppliersByItemViewRecord _viewRecord(SuppliersByItemFieldsScope scope) =>
      _suppliersByItemViews.putIfAbsent(scope, _SuppliersByItemViewRecord.new);

  SuppliersByItemViewSnapshot getSuppliersByItemView(
    SuppliersByItemFieldsScope scope,
  ) => _viewRecord(scope).snapshot;

  void Function() watchSuppliersByItemView(
    SuppliersByItemFieldsScope scope,
    void Function(SuppliersByItemViewSnapshot) onChange,
  ) => _viewRecord(scope).watch(onChange);

  Future<void> loadSuppliersByItemView(SuppliersByItemFieldsScope scope) {
    final record = _viewRecord(scope);
    if (record.loaded) return Future.value();
    return record.loading ??= _loadView(scope, record).whenComplete(() {
      record.loading = null;
    });
  }

  Future<void> _loadView(
    SuppliersByItemFieldsScope scope,
    _SuppliersByItemViewRecord record,
  ) async {
    final key = _scopedSuppliersByItemKey(_suppliersByItemViewKey, scope);
    try {
      final stored = await _configStore!.getConfig(key);
      record.value = _decodeView(stored);
      record.loaded = true;
      record.failure = null;
    } catch (_) {
      record.failure = SuppliersByItemFieldsFailure.load;
    }
    record.publish();
  }

  SuppliersByItemView _decodeView(String? stored) {
    if (stored == null) return const SuppliersByItemView();
    try {
      return SuppliersByItemView.fromJson(jsonDecode(stored));
    } on FormatException {
      return const SuppliersByItemView();
    }
  }

  Future<void> updateSuppliersByItemView(
    SuppliersByItemFieldsScope scope,
    SuppliersByItemView? Function(SuppliersByItemView) edit,
  ) {
    final next = edit(_viewRecord(scope).value);
    return next == null ? Future.value() : saveSuppliersByItemView(scope, next);
  }

  Future<void> saveSuppliersByItemView(
    SuppliersByItemFieldsScope scope,
    SuppliersByItemView view,
  ) async {
    final record = _viewRecord(scope);
    if (!record.loaded) throw StateError('View has not loaded');
    final database = _configStore!;
    final key = _scopedSuppliersByItemKey(_suppliersByItemViewKey, scope);
    await record.save(
      view,
      () => database.saveConfig(key, jsonEncode(view.toJson())),
    );
  }

  // --- Dashboard view preferences ---
  // Quick Create card layout: 1 or 2 columns. Anything else clamps to the
  // 1-column default so a stale/corrupt value can never break the grid.
  Future<void> saveDashboardColumns(int value) async =>
      _box.write(_dashboardColumnsKey, value);

  int getDashboardColumns() =>
      _box.read<int>(_dashboardColumnsKey) == 2 ? 2 : 1;

  // Last computed "Upcoming tasks lead" verdict, PER USER, so the initial
  // dashboard build matches the previous session instead of reflowing when
  // the async ToDo fetch lands. Missing key = false (operator layout).
  Future<void> saveDashboardTasksFirst(String user, bool value) async =>
      _box.write('$_dashboardTasksFirstKey::$user', value);

  bool getDashboardTasksFirst(String user) =>
      _box.read<bool>('$_dashboardTasksFirstKey::$user') ?? false;

  // --- Scheduled digest notification preferences ---
  Future<void> saveDigestEnabled(String user, bool value) async =>
      _box.write('$_digestEnabledKey::$user', value);

  bool getDigestEnabled(String user) =>
      _box.read<bool>('$_digestEnabledKey::$user') ?? false;

  Future<void> saveDigestTimes(String user, List<String> times) async =>
      _box.write('$_digestTimesKey::$user', times);

  List<String> getDigestTimes(String user) {
    final raw = _box.read<List<dynamic>>('$_digestTimesKey::$user');
    return raw == null ? const ['09:00'] : raw.cast<String>();
  }

  Future<void> saveDigestDays(String user, List<int> days) async =>
      _box.write('$_digestDaysKey::$user', days);

  List<int> getDigestDays(String user) {
    final raw = _box.read<List<dynamic>>('$_digestDaysKey::$user');
    return raw == null ? const [1, 2, 3, 4, 5, 6, 7] : raw.cast<int>();
  }

  Future<void> saveDigestDoctypes(String user, List<String> keys) async =>
      _box.write('$_digestDoctypesKey::$user', keys);

  List<String> getDigestDoctypes(String user) {
    final raw = _box.read<List<dynamic>>('$_digestDoctypesKey::$user');
    return raw == null
        ? const [
            'purchase_order',
            'sales_order',
            'purchase_receipt',
            'delivery_note',
            'stock_entry',
            'pos_upload',
          ]
        : raw.cast<String>();
  }

  Future<void> saveDigestAlarmStyle(String user, String style) async =>
      _box.write('$_digestAlarmStyleKey::$user', style);

  /// 'alarm' (insistent) or 'standard' (single sound + vibration). Default
  /// 'standard' — least-surprising for existing enabled managers.
  String getDigestAlarmStyle(String user) =>
      _box.read<String>('$_digestAlarmStyleKey::$user') ?? 'standard';

  // --- Drawer layout (per user) ---
  Future<void> saveNavMenu(
    String user,
    List<Map<String, dynamic>> menu,
  ) async => _box.write('$_navMenuKey::$user', menu);

  List<dynamic>? getNavMenu(String user) =>
      _box.read<List<dynamic>>('$_navMenuKey::$user');

  // Persisted Mine/Everyone choice for the "Upcoming & actionable" strip.
  // Stored as 'mine' | 'everyone'; any other value reads back as 'mine'.
  Future<void> saveDashboardActionableScope(String value) async =>
      _box.write(_dashboardActionableScopeKey, value);

  String getDashboardActionableScope() =>
      _box.read<String>(_dashboardActionableScopeKey) == 'everyone'
      ? 'everyone'
      : 'mine';

  // --- Attendance notification preferences ---
  Future<void> saveAttendanceRemindersEnabled(String user, bool value) async =>
      _box.write('$_attEnabledKey::$user', value);

  /// Attendance reminders are on by default for linked employees.
  bool getAttendanceRemindersEnabled(String user) =>
      _box.read<bool>('$_attEnabledKey::$user') ?? true;

  Future<void> saveAttendanceTerminalAlerts(String user, bool value) async =>
      _box.write('$_attTerminalKey::$user', value);

  /// Terminal quiet/back alerts are on by default for System Managers.
  bool getAttendanceTerminalAlerts(String user) =>
      _box.read<bool>('$_attTerminalKey::$user') ?? true;

  /// Written by the main isolate once the Dashboard has asked for
  /// notification permission, so the prompt never repeats.
  Future<void> saveAttendancePermissionPrompted(String user) async =>
      _box.write('$_attPromptedKey::$user', true);

  bool getAttendancePermissionPrompted(String user) =>
      _box.read<bool>('$_attPromptedKey::$user') ?? false;

  // --- Sales Order last-used price list (per user) ---
  Future<void> saveSoLastSellingPriceList(String user, String value) async =>
      _box.write('$_soLastPriceListKey::$user', value);

  String? getSoLastSellingPriceList(String user) =>
      _box.read<String>('$_soLastPriceListKey::$user');

  // --- Stock sheet: last file format ---
  Future<void> saveItemsFromPhotosFormat(String value) async =>
      _box.write(_itemsFromPhotosFormatKey, value);

  /// Null until the first Make sheet.
  String? getItemsFromPhotosFormat() =>
      _box.read<String>(_itemsFromPhotosFormatKey);
}
