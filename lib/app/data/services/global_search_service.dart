import 'dart:convert';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class GlobalSearchService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Standard Global Search (Awesome Bar)
  Future<List<GlobalSearchItem>> search(String doctype, String query) async {
    // Implementation for global search...
    // For now, redirecting to searchLink as fallback if strictly used for Links
    return searchLink(doctype, query);
  }

  // Specific Search for Link Fields (Supports Filters)
  Future<List<GlobalSearchItem>> searchLink(
      String doctype,
      String query, {
        Map<String, dynamic>? filters,
      }) async {
    try {
      // 1. Construct params conditionally to avoid sending 'filters' as null/empty string
      final Map<String, dynamic> params = {
        'doctype': doctype,
        'txt': query,
        'page_length': 20,
      };

      // Only add filters if they exist
      if (filters != null && filters.isNotEmpty) {
        params['filters'] = jsonEncode(filters);
      }

      final response = await _apiProvider.callMethod(
        'frappe.desk.search.search_link',
        params: params,
      );

      if (response.statusCode == 200) {
        // frappe.desk.search.search_link returns a List of Maps directly
        // usually: [{'value': 'BATCH-001', 'description': '...'}, ...]
        // OR [{'name': 'BATCH-001', ...}] depending on version/setup
        final List<dynamic> results = response.data['message'] ?? [];

        // Explicitly map to GlobalSearchItem to satisfy return type
        return results.map<GlobalSearchItem>((e) {
          final map = e as Map<String, dynamic>;
          // Handle various return formats of search_link
          final String value = map['value'] ?? map['name'] ?? '';
          final String description = map['description'] ?? '';

          return GlobalSearchItem(
            id: value,
            title: value,
            subtitle: description,
            rawData: map,
          );
        }).toList();
      }
    } catch (e) {
      print("GlobalSearchService Error: $e");
    }
    return [];
  }
}