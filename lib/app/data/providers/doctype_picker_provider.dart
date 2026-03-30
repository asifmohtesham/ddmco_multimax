import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';

// ────────────────────────────────────────────────────────────────────────────
// DocTypePickerProvider
// ────────────────────────────────────────────────────────────────────────────

/// Provider for generic DocType queries used by DocTypePickerBottomSheet.
///
/// Supports cache-first loading with explicit live refresh for DocType lists
/// filtered by Frappe-style filters and text search.
class DocTypePickerProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final StorageService _storage = Get.find<StorageService>();

  /// In-memory cache keyed by cache key string.
  /// Structure: {cacheKey: {'data': [...], 'timestamp': DateTime}}
  final Map<String, Map<String, dynamic>> _cache = {};

  /// Cache TTL in minutes. Cached results older than this are considered stale.
  static const int cacheTTLMinutes = 15;

  /// Query a DocType with Frappe-style filters and return parsed rows.
  ///
  /// When [forceRefresh] is `false` (default), reads from cache if available
  /// and not stale. When `true` the cache is bypassed and a live API call is
  /// made, updating the cache afterwards.
  ///
  /// Returns `{"data": List<Map<String, dynamic>>}` on success.
  /// Throws Exception on API error or parse failure.
  Future<Map<String, dynamic>> queryDocType({
    required String doctype,
    required List<String> fields,
    List<List<dynamic>>? filters,
    String? searchText,
    String orderBy = '`modified` desc',
    int limit = 50,
    int start = 0,
    String? cacheKey,
    bool forceRefresh = false,
  }) async {
    // 1. Try cache if key provided and not forced refresh
    if (!forceRefresh && cacheKey != null && _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      final timestamp = cached['timestamp'] as DateTime?;
      if (timestamp != null &&
          DateTime.now().difference(timestamp).inMinutes < cacheTTLMinutes) {
        return {'data': cached['data']};
      }
    }

    // 2. Build final filters with search text
    final allFilters = <List<dynamic>>[];
    if (filters != null) allFilters.addAll(filters);

    // Add search filter if text provided
    if (searchText != null && searchText.trim().isNotEmpty) {
      // Frappe name field is always searchable
      allFilters.add([doctype, 'name', 'like', '%$searchText%']);
    }

    // 3. Call ERPNext API via getReportView (same pattern as ItemProvider)
    try {
      final response = await _apiProvider.getReportView(
        doctype,
        start: start,
        pageLength: limit,
        filters: allFilters.isEmpty ? null : allFilters,
        orderBy: orderBy,
        fields: fields.map((f) => '`tab$doctype`.`$f`').toList(),
      );

      if (response.statusCode == 200) {
        if (response.data is Map<String, dynamic>) {
          if (response.data['exc'] != null) {
            throw Exception("Server Error: ${response.data['exc']}");
          }

          final message = response.data['message'];

          // Handle empty list
          if (message is List) {
            final result = {'data': []};
            _updateCache(cacheKey, result);
            return result;
          }

          // Parse standard ReportView keys/values
          if (message != null && message is Map) {
            final List<dynamic> keys = message['keys'] ?? [];
            final List<dynamic> values = message['values'] ?? [];

            final parsedData = values.map((row) {
              final map = <String, dynamic>{};
              if (row is List) {
                for (int i = 0; i < keys.length; i++) {
                  if (i < row.length) {
                    // Clean key (e.g. `tabItem`.`name` -> name)
                    String key = keys[i].toString();
                    if (key.contains('.')) {
                      key = key.split('.').last.replaceAll('`', '');
                    }
                    map[key] = row[i];
                  }
                }
              }
              return map;
            }).toList();

            final result = {'data': parsedData};
            _updateCache(cacheKey, result);
            return result;
          }

          throw Exception("Unexpected Response Format: ${response.data}");
        } else {
          throw Exception(
              "Non-JSON Response: ${response.data.toString().substring(0, 150)}...");
        }
      }

      throw Exception("HTTP Error: ${response.statusCode}");
    } catch (e) {
      rethrow;
    }
  }

  /// Updates cache entry with fresh data and timestamp.
  void _updateCache(String? cacheKey, Map<String, dynamic> result) {
    if (cacheKey != null) {
      _cache[cacheKey] = {
        'data': result['data'],
        'timestamp': DateTime.now(),
      };
    }
  }

  /// Clears cached data for a specific cache key.
  void clearCache(String cacheKey) {
    _cache.remove(cacheKey);
  }

  /// Clears all cached picker data.
  void clearAllCache() {
    _cache.clear();
  }
}
