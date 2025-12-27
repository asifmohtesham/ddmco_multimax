import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class GlobalSearchService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // In-memory cache to prevent redundant metadata calls during a session
  final Map<String, Map<String, dynamic>> _metadataCache = {};
  final Map<String, Map<String, String>> _fieldTypesCache = {};

  /// Performs a robust, contextual search for the given [doctype].
  Future<List<GlobalSearchItem>> search(String doctype, String query) async {
    try {
      // 1. Prepare Metadata (Cached)
      await _ensureMetadata(doctype);
      final meta = _metadataCache[doctype];
      final fieldTypes = _fieldTypesCache[doctype] ?? {};

      // 2. Identify Search & Select Fields
      final List<String> searchTargets = ['name'];
      final List<String> selectFields = ['name'];

      if (meta != null) {
        // A. Contextual Display Fields
        if (meta['title_field'] != null) selectFields.add(meta['title_field']);
        if (meta['image_field'] != null) selectFields.add(meta['image_field']);

        // B. Contextual Search Fields
        if (meta['search_fields'] != null) {
          final String sf = meta['search_fields'];
          final splitFields = sf.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);

          for (final rawField in splitFields) {
            // Validate: Only search if safe
            if (_isTextSearchable(rawField, fieldTypes)) {
              searchTargets.add(rawField);
            }
            // Always Select: For display context
            selectFields.add(rawField);
          }
        }
      }

      // Fallback description
      // if (!selectFields.contains('description')) selectFields.add('description');

      // 3. Construct Query
      final Map<String, dynamic> orFilters = {};
      for (var field in searchTargets.toSet()) {
        orFilters[field] = ['like', '%$query%'];
      }

      // Debug Log
      if (kDebugMode) {
        print('GlobalSearchService: Searching "$query" in $doctype on fields: $searchTargets');
      }

      // 4. API Call
      final response = await _apiProvider.getDocumentList(
        doctype,
        orFilters: orFilters,
        limit: 20,
        fields: selectFields.toSet().toList(),
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List data = response.data['data'];
        // 5. Map to Model
        return data.map((e) => _mapToModel(e, meta)).toList();
      }
    } catch (e) {
      print('GlobalSearchService Error ($doctype): $e');
    }
    return [];
  }

  /// Maps a raw API JSON object to a standardized [GlobalSearchItem].
  GlobalSearchItem _mapToModel(Map<String, dynamic> item, Map<String, dynamic>? meta) {
    final String name = item['name'] ?? '';
    String title = name;
    String? subtitle;
    String? imageUrl;

    if (meta != null) {
      // Resolve Title
      if (meta['title_field'] != null) {
        final tField = meta['title_field'];
        if (item[tField] != null && item[tField].toString().isNotEmpty) {
          title = item[tField].toString();
          if (title != name) subtitle = name;
        }
      }
      // Resolve Image
      if (meta['image_field'] != null) {
        final iField = meta['image_field'];
        if (item[iField] != null) {
          imageUrl = item[iField].toString();
        }
      }
    }

    // Fallback Subtitle Logic
    subtitle ??= item['description'] ?? item['item_name'] ?? item['customer_name'] ?? item['supplier_name'];

    return GlobalSearchItem(
      id: name,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      rawData: item,
    );
  }

  /// Fetches and caches DocType metadata to understand fields and types.
  Future<void> _ensureMetadata(String doctype) async {
    if (_metadataCache.containsKey(doctype)) return;

    try {
      final response = await _apiProvider.getDocument('DocType', doctype);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final meta = response.data['data'];
        _metadataCache[doctype] = meta;

        // Parse Field Types
        final Map<String, String> types = {};
        if (meta['fields'] != null && meta['fields'] is List) {
          for (var field in meta['fields']) {
            if (field is Map) {
              final fname = field['fieldname'];
              final ftype = field['fieldtype'];
              if (fname != null && ftype != null) {
                types[fname.toString().toLowerCase()] = ftype.toString();
              }
            }
          }
        }
        _fieldTypesCache[doctype] = types;
      }
    } catch (e) {
      print('GlobalSearchService: Metadata fetch failed for $doctype: $e');
    }
  }

  /// Validates if a field is safe for text-based searching (LIKE operator).
  bool _isTextSearchable(String fieldname, Map<String, String> types) {
    fieldname = fieldname.toLowerCase();

    // 1. Explicit Blacklist (Dates, Numbers, System fields)
    const blacklist = [
      'creation', 'modified', 'docstatus', 'idx', 'lft', 'rgt',
      'transaction_date', 'posting_date', 'schedule_date', 'delivery_date', 'date',
      'posting_time', 'grand_total', 'total_qty', 'total_amount', 'base_grand_total',
      'naming_series', 'exchange_rate', 'conversion_factor'
    ];
    if (blacklist.contains(fieldname)) return false;

    // 2. Heuristic Blacklist (Suffix Check)
    if (fieldname.endsWith('_date') ||
        fieldname.endsWith('_time') ||
        fieldname.endsWith('_amount') ||
        fieldname.endsWith('_qty') ||
        fieldname.endsWith('_rate')) {
      return false;
    }

    // 3. Explicit Whitelist (Standard safe fields)
    if (['name', 'owner', 'title', '_user_tags', 'item_name', 'customer_name', 'supplier_name', 'description', 'remarks'].contains(fieldname)) return true;

    // 4. Metadata Type Check
    final type = types[fieldname];

    if (type == null) return false; // Paranoid default

    const safeTypes = [
      'Data', 'Text', 'Small Text', 'Long Text', 'Text Editor',
      'Code', 'HTML', 'Markdown Editor', 'Link', 'Dynamic Link',
      'Select', 'Read Only', 'Barcode', 'Phone', 'Email', 'Color'
    ];

    return safeTypes.contains(type);
  }
}