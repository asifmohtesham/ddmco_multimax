import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:get_storage/get_storage.dart';

class DatabaseService extends GetxService {
  late Database _db;
  final GetStorage _box = GetStorage();
  String _dbPath = '';

  // Expose the path for debugging/about screen
  String get dbPath => _dbPath;

  // Configuration Keys
  static const String serverUrlKey = 'server_url';

  Future<DatabaseService> init() async {
    if (kIsWeb) {
      await GetStorage.init();
      _dbPath = 'LocalStorage';
    } else {
      _db = await _initDb();
    }
    return this;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_config.db');
    _dbPath = path; // Store the full path

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Create a generic key-value store for configuration
        await db.execute(
          'CREATE TABLE config(key TEXT PRIMARY KEY, value TEXT)',
        );
      },
    );
  }

  /// Saves a configuration value securely.
  Future<void> saveConfig(String key, String value) async {
    if (kIsWeb) {
      await _box.write(key, value);
    } else {
      await _db.insert(
        'config',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Retrieves a configuration value.
  Future<String?> getConfig(String key) async {
    if (kIsWeb) {
      return _box.read(key);
    } else {
      final List<Map<String, dynamic>> maps = await _db.query(
        'config',
        where: 'key = ?',
        whereArgs: [key],
      );

      if (maps.isNotEmpty) {
        return maps.first['value'] as String;
      }
      return null;
    }
  }

  /// Removes a configuration key (e.g., on logout/reset).
  Future<void> removeConfig(String key) async {
    if (kIsWeb) {
      await _box.remove(key);
    } else {
      await _db.delete('config', where: 'key = ?', whereArgs: [key]);
    }
  }
}
