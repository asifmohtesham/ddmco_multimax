import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// A global search delegate that performs contextual server-side searches for a specific DocType.
///
/// It first fetches the DocType metadata to identify:
/// - [search_fields]: Which fields to query against (e.g. item_name, barcode).
/// - [title_field]: Which field to display as the main title.
/// - [image_field]: Which field contains the image URL.
class GlobalSearchDelegate extends SearchDelegate {
  final String doctype;
  final String targetRoute;
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Cache metadata to avoid repeated calls during the session
  Map<String, dynamic>? _meta;

  GlobalSearchDelegate({
    required this.doctype,
    required this.targetRoute,
  });

  @override
  String? get searchFieldLabel => 'Search $doctype...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.trim().length < 3) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              "Type at least 3 characters to search",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return FutureBuilder(
      future: _searchApi(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: LinearProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Search failed: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final results = snapshot.data as List<dynamic>? ?? [];

        if (results.isEmpty) {
          return Center(
            child: Text(
              'No $doctype found matching "$query"',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final item = results[index];
            return _buildListItem(context, item);
          },
        );
      },
    );
  }

  Widget _buildListItem(BuildContext context, Map<String, dynamic> item) {
    // Determine display fields based on metadata
    final String name = item['name'] ?? '';

    String title = name;
    String? subtitle;
    String? imageUrl;

    if (_meta != null) {
      // Resolve Title
      if (_meta!['title_field'] != null) {
        final tField = _meta!['title_field'];
        if (item[tField] != null && item[tField].toString().isNotEmpty) {
          title = item[tField].toString();
          // If title is different from name, show name as subtitle
          if (title != name) {
            subtitle = name;
          }
        }
      }

      // Resolve Image
      if (_meta!['image_field'] != null) {
        final iField = _meta!['image_field'];
        if (item[iField] != null) {
          imageUrl = item[iField].toString();
        }
      }
    }

    // Fallback subtitle if empty
    subtitle ??= item['description'] ?? item['item_name'] ?? item['customer_name'] ?? item['supplier_name'];

    return ListTile(
      leading: _buildLeadingIcon(imageUrl),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle != null ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        close(context, null);
        Get.toNamed(targetRoute, arguments: name); // Always pass ID (name)
      },
    );
  }

  Widget _buildLeadingIcon(String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final baseUrl = _apiProvider.baseUrl;
      final fullUrl = imageUrl.startsWith('http') ? imageUrl : '$baseUrl$imageUrl';

      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          fullUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultIcon(),
        ),
      );
    }
    return _defaultIcon();
  }

  Widget _defaultIcon() {
    return CircleAvatar(
      backgroundColor: Colors.blueGrey.shade100,
      foregroundColor: Colors.blueGrey.shade700,
      child: const Icon(Icons.description, size: 20),
    );
  }

  Future<List<dynamic>> _searchApi() async {
    try {
      // 1. Ensure Metadata is loaded to identify fields
      await _ensureMetadata();

      // 2. Determine Search Fields
      final List<String> searchTargetFields = ['name'];
      final List<String> selectFields = ['name'];

      if (_meta != null) {
        // Add Title Field
        if (_meta!['title_field'] != null) {
          selectFields.add(_meta!['title_field']);
        }
        // Add Image Field
        if (_meta!['image_field'] != null) {
          selectFields.add(_meta!['image_field']);
        }
        // Parse and Add Search Fields
        if (_meta!['search_fields'] != null) {
          final String sf = _meta!['search_fields'];
          final splitFields = sf.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
          searchTargetFields.addAll(splitFields);
          selectFields.addAll(splitFields); // Fetch them too for context if needed
        }
      }

      // Ensure 'description' is fetched if we don't have good metadata, as a fallback
      if (!selectFields.contains('description')) selectFields.add('description');

      // 3. Construct OR Filters
      // Query: (name LIKE %q% OR field1 LIKE %q% OR field2 LIKE %q%)
      final Map<String, dynamic> orFilters = {};
      for (var field in searchTargetFields.toSet()) { // toSet to remove duplicates
        orFilters[field] = ['like', '%$query%'];
      }

      // 4. Execute Search
      final response = await _apiProvider.getDocumentList(
        doctype,
        orFilters: orFilters,
        limit: 20,
        fields: selectFields.toSet().toList(),
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      debugPrint('GlobalSearchDelegate Error ($doctype): $e');
    }
    return [];
  }

  Future<void> _ensureMetadata() async {
    if (_meta != null) return;
    try {
      // Fetch DocType definition to get metadata
      final response = await _apiProvider.getDocument('DocType', doctype);
      if (response.statusCode == 200 && response.data['data'] != null) {
        _meta = response.data['data'];
      }
    } catch (e) {
      debugPrint('Failed to load metadata for $doctype. Using defaults. Error: $e');
    }
  }
}