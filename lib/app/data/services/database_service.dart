import 'dart:convert';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService extends GetxService {
  late Database _db;
  String _dbPath = '';

  // Expose the path for debugging/about screen
  String get dbPath => _dbPath;

  // Configuration Keys
  static const String serverUrlKey  = 'server_url';
  static const String serverUrlsKey = 'server_urls'; // JSON list

  /// Maximum number of server URLs to keep in history.
  static const int _maxServerHistory = 10;

  Future<DatabaseService> init() async {
    _db = await _initDb();
    return this;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_config.db');
    _dbPath = path;

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE config(key TEXT PRIMARY KEY, value TEXT)',
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Generic key-value helpers
  // ---------------------------------------------------------------------------

  /// Saves a configuration value.
  Future<void> saveConfig(String key, String value) async {
    await _db.insert(
      'config',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves a configuration value.
  Future<String?> getConfig(String key) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'config',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) return maps.first['value'] as String;
    return null;
  }

  /// Removes a configuration key.
  Future<void> removeConfig(String key) async {
    await _db.delete('config', where: 'key = ?', whereArgs: [key]);
  }

  // ---------------------------------------------------------------------------
  // Server URL history helpers
  // ---------------------------------------------------------------------------

  /// Prepends [url] to the saved server-URL list (most-recent first).
  /// Duplicates are removed and the list is capped at [_maxServerHistory].
  Future<void> saveServerUrl(String url) async {
    final urls = await getServerUrls();
    urls.remove(url);          // remove duplicate if present
    urls.insert(0, url);       // most-recent first
    if (urls.length > _maxServerHistory) urls.removeLast();
    await saveConfig(serverUrlsKey, json.encode(urls));
  }

  /// Returns the list of saved server URLs, most-recent first.
  Future<List<String>> getServerUrls() async {
    final raw = await getConfig(serverUrlsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Removes a specific URL from the history list.
  Future<void> removeServerUrl(String url) async {
    final urls = await getServerUrls();
    urls.remove(url);
    await saveConfig(serverUrlsKey, json.encode(urls));
  }

  /// Clears the entire server-URL history list.
  Future<void> clearServerUrls() async {
    await removeConfig(serverUrlsKey);
  }
}
