import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One default-filter run of Stock Ageing - Custom, as kept on the device.
class StockAgeingSnapshot {
  final DateTime fetchedAt;

  /// `message.columns` as returned by the server.
  final List<dynamic> columns;
  final List<Map<String, dynamic>> rows;

  /// `message.custom_filters`: the report's saved default filters.
  final Map<String, dynamic> defaults;

  const StockAgeingSnapshot({
    required this.fetchedAt,
    required this.columns,
    required this.rows,
    required this.defaults,
  });

  Map<String, dynamic> toJson() => {
        'fetched_at': fetchedAt.toIso8601String(),
        'columns': columns,
        'rows': rows,
        'defaults': defaults,
      };

  static StockAgeingSnapshot fromJson(Map<String, dynamic> j) =>
      StockAgeingSnapshot(
        fetchedAt: DateTime.parse(j['fetched_at'] as String),
        columns: List<dynamic>.from(j['columns'] as List),
        rows: [
          for (final r in j['rows'] as List)
            Map<String, dynamic>.from(r as Map),
        ],
        defaults: Map<String, dynamic>.from(j['defaults'] as Map),
      );
}

/// File-backed cache for the default run (~1 MB of JSON). A plain file is
/// used rather than GetStorage, which holds its whole box in memory and
/// rewrites it on every change.
class StockAgeingCache {
  static const _fileName = 'stock_ageing_custom.json';

  final Future<Directory> Function() _directory;

  StockAgeingCache({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  Future<File> _file() async => File(p.join((await _directory()).path, _fileName));

  /// Returns the cached snapshot, or null when there is none or the file
  /// cannot be decoded (e.g. a write interrupted by the OS).
  Future<StockAgeingSnapshot?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final decoded = json.decode(await f.readAsString());
      return StockAgeingSnapshot.fromJson(
          Map<String, dynamic>.from(decoded as Map));
    } catch (_) {
      return null;
    }
  }

  /// Writes via a temporary file and a rename, so a reader never sees a
  /// half-written cache.
  Future<void> write(StockAgeingSnapshot snapshot) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(json.encode(snapshot.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
