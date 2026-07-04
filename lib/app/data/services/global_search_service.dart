import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/models/warehouse_stock_line.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';

/// A doctype's search hits, for the grouped Dashboard results.
class GlobalSearchGroup {
  final GlobalSearchTarget target;
  final List<GlobalSearchItem> items;
  const GlobalSearchGroup({required this.target, required this.items});
}

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

  /// Max hits shown per doctype group.
  static const int kGroupCap = 8;

  /// Targets the user is allowed to read. A target is kept unless permission
  /// is explicitly `false`; `null` (cache not yet warm) degrades permissive.
  static List<GlobalSearchTarget> filterPermittedTargets(
    List<GlobalSearchTarget> targets,
    bool? Function(String doctype) canRead,
  ) =>
      targets.where((t) => canRead(t.doctype) != false).toList();

  /// Builds groups in [entries] order, dropping any with no items.
  static List<GlobalSearchGroup> buildGroups(
    List<MapEntry<GlobalSearchTarget, List<GlobalSearchItem>>> entries,
  ) =>
      [
        for (final e in entries)
          if (e.value.isNotEmpty)
            GlobalSearchGroup(target: e.key, items: e.value),
      ];

  /// Pure fan-out: searches every permitted target via [searcher] concurrently,
  /// caps each group at [cap], and groups the results. Injectable for testing.
  static Future<List<GlobalSearchGroup>> runSearchAll({
    required List<GlobalSearchTarget> targets,
    required bool? Function(String doctype) canRead,
    required Future<List<GlobalSearchItem>> Function(String doctype) searcher,
    int cap = kGroupCap,
  }) async {
    final permitted = filterPermittedTargets(targets, canRead);
    final entries = await Future.wait(
      permitted.map((t) async {
        List<GlobalSearchItem> items;
        try {
          items = await searcher(t.doctype);
        } catch (_) {
          items = <GlobalSearchItem>[];
        }
        return MapEntry(t, items.take(cap).toList());
      }),
    );
    return buildGroups(entries);
  }

  /// Searches [query] across every permitted [kGlobalSearchTargets] doctype and
  /// returns the hits grouped by doctype (registry order, empty groups dropped).
  Future<List<GlobalSearchGroup>> searchAll(String query) {
    final permission = Get.find<PermissionService>();
    return runSearchAll(
      targets: kGlobalSearchTargets,
      canRead: (doctype) => permission.hasAccess(doctype),
      searcher: (doctype) => search(doctype, query),
    );
  }

  /// Stock Balance lines for the items matching [query], scoped to [warehouse].
  /// Resolves matching item codes via the existing Item search, then queries
  /// the Stock Balance report for those items in [warehouse] for today. Returns
  /// an empty list when nothing matches. Errors propagate to the caller (the
  /// delegate hides the section on error).
  Future<List<WarehouseStockLine>> stockBalanceForQuery(
    String query,
    String warehouse,
  ) async {
    final codes = itemCodesFrom(await search('Item', query));
    if (codes.isEmpty) return const [];
    final today = _today();
    final result = await _apiProvider.getStockBalanceReport(
      fromDate: today,
      toDate: today,
      itemCodes: codes,
      warehouse: warehouse,
    );
    final allowed = codes.toSet();
    final rows = result.rows
        .where((r) => allowed.contains((r['item_code'] ?? '').toString()))
        .toList();
    return mapStockLines(rows);
  }

  /// Non-blank item codes from [items], capped at [kGroupCap]. Pure.
  static List<String> itemCodesFrom(List<GlobalSearchItem> items) => items
      .map((i) => i.id)
      .where((c) => c.isNotEmpty)
      .take(kGroupCap)
      .toList();

  /// Maps Stock Balance report rows to [WarehouseStockLine]s, reading the
  /// balance from `bal_qty` (falling back to legacy `balance_qty`). Rows with a
  /// blank item code are skipped. Pure.
  static List<WarehouseStockLine> mapStockLines(
    List<Map<String, dynamic>> rows,
  ) {
    final out = <WarehouseStockLine>[];
    for (final r in rows) {
      final code = (r['item_code'] ?? '').toString();
      if (code.isEmpty) continue;
      out.add(WarehouseStockLine(
        itemCode: code,
        itemName: (r['item_name'] ?? '').toString(),
        balanceQty: _num(r, const ['bal_qty', 'balance_qty']),
        uom: (r['stock_uom'] ?? '').toString(),
      ));
    }
    return out;
  }

  static double _num(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final p = double.tryParse(v.toString().trim());
      if (p != null) return p;
    }
    return 0.0;
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
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