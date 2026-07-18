import 'package:multimax/app/data/models/user_model.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class StorageService {
  final dynamic _box;

  StorageService() : _box = GetStorage();

  // Internal constructor for testing - allows injection of a custom storage instance
  StorageService.withStorage(this._box);

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
  static const String _sbHideEmptyKey  = 'sb_hide_empty';
  static const String _sbShowImagesKey = 'sb_show_images';

  // Dashboard view preferences
  static const String _dashboardColumnsKey = 'dashboard_columns';
  static const String _dashboardTasksFirstKey = 'dashboard_tasks_first';
  static const _dashboardActionableScopeKey = 'dashboard_actionable_scope';

  // Scheduled digest notification preferences (per user, keyed key::user —
  // same convention as dashboard_tasks_first).
  static const String _digestEnabledKey = 'notif_digest_enabled';
  static const String _digestTimesKey = 'notif_digest_times';
  static const String _digestDaysKey = 'notif_digest_days';
  static const String _digestDoctypesKey = 'notif_digest_doctypes';
  static const String _digestAlarmStyleKey = 'notif_digest_alarm_style';

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

  Future<void> clearUserData() async {
    await _box.remove(_userKey);
    await _box.remove(_tokenKey);
    printInfo(info: "User data cleared from local storage.");
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

  int getAutoSaveDelay() =>
      _box.read<int>(_autoSaveDelayKey) ?? 5;

  // --- Stock Balance view preferences ---
  // Persisted so the "Hide empty" / "Images" toggles survive navigation,
  // mirroring the web report's view preferences.
  Future<void> saveSbHideEmpty(bool value) async =>
      _box.write(_sbHideEmptyKey, value);

  bool getSbHideEmpty() => _box.read<bool>(_sbHideEmptyKey) ?? false;

  Future<void> saveSbShowImages(bool value) async =>
      _box.write(_sbShowImagesKey, value);

  bool getSbShowImages() => _box.read<bool>(_sbShowImagesKey) ?? true;

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

  // Persisted Mine/Everyone choice for the "Upcoming & actionable" strip.
  // Stored as 'mine' | 'everyone'; any other value reads back as 'mine'.
  Future<void> saveDashboardActionableScope(String value) async =>
      _box.write(_dashboardActionableScopeKey, value);

  String getDashboardActionableScope() =>
      _box.read<String>(_dashboardActionableScopeKey) == 'everyone'
          ? 'everyone'
          : 'mine';
}