import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService extends GetxService {
  late Database _db;
  String _dbPath = '';

  // Expose the path for debugging/about screen
  String get dbPath => _dbPath;

  // Configuration Keys
  static const String serverUrlKey = 'server_url';

  Future<DatabaseService> init() async {
    _db = await _initDb();
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

    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return null;
  }

  /// Removes a configuration key (e.g., on logout/reset).
  Future<void> removeConfig(String key) async {
    await _db.delete('config', where: 'key = ?', whereArgs: [key]);
  }
}