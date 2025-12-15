import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:get/get.dart';

class SearchHelper {
  /// Filters a list of items based on a multi-token query against multiple fields (Client-Side).
  ///
  /// [items]: The list of objects to filter.
  /// [query]: The search string (e.g., "wallet 895").
  /// [searchables]: A function that returns a list of strings to search within for a given item.
  ///
  /// Logic:
  /// 1. Splits [query] into tokens (e.g., ["wallet", "895"]).
  /// 2. For an item to match, *every* token must be found in *at least one* of the [searchables].
  ///    This allows "895 wallet" to match an item with name "Wallet" and code "895".
  static List<T> search<T>(
      List<T> items,
      String query,
      List<String?> Function(T) searchables,
      ) {
    if (query.trim().isEmpty) return items;

    final tokens = query.toLowerCase().trim().split(RegExp(r'\s+'));

    return items.where((item) {
      // Get all searchable values for this item, lowercased and non-null
      final values = searchables(item)
          .where((s) => s != null)
          .map((s) => s!.toLowerCase())
          .toList();

      // Check if ALL tokens have a match in ANY of the values
      return tokens.every((token) {
        return values.any((value) => value.contains(token));
      });
    }).toList();
  }

  /// Queries the API for items matching the [query] across [searchFields] (Server-Side).
  ///
  /// Uses `or_filters` to match the query string against any of the provided fields.
  /// E.g. (Item Name like '%query%' OR Item Code like '%query%').
  ///
  /// [doctype]: The DocType to search (e.g. 'Item').
  /// [query]: The search term.
  /// [searchFields]: List of field names to check (e.g. ['item_name', 'item_code']).
  /// [fromJson]: Factory to convert JSON to Model.
  /// [extraFilters]: Optional strict filters (AND) to apply (e.g. {'disabled': 0}).
  static Future<List<T>> searchApi<T>({
    required String doctype,
    required String query,
    required List<String> searchFields,
    required T Function(Map<String, dynamic>) fromJson,
    List<String>? selectFields,
    Map<String, dynamic>? extraFilters,
    int limit = 20,
  }) async {
    if (query.trim().isEmpty) return [];

    final ApiProvider provider = Get.find<ApiProvider>();

    // Construct or_filters: "field like %query%"
    final Map<String, dynamic> orFilters = {};
    for (var field in searchFields) {
      orFilters[field] = ['like', '%$query%'];
    }

    try {
      final response = await provider.getDocumentList(
        doctype,
        filters: extraFilters,
        orFilters: orFilters,
        fields: selectFields,
        limit: limit,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('SearchHelper API Error ($doctype): $e');
    }
    return [];
  }
}