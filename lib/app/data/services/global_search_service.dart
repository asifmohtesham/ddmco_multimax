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

      // 3. Tokenise. ≤1 token → single-phrase LIKE across all fields (matches
      // code OR name). ≥2 tokens → AND each token on the PRIMARY field
      // server-side (all-words, any order) so genuine matches aren't diluted by
      // an OR-superset.
      final fieldSet = searchTargets.toSet();
      final tokens = searchTokens(query);
      final primaryField = resolvePrimarySearchField(meta, searchTargets);

      if (kDebugMode) {
        print('GlobalSearchService: Searching "$query" $tokens in $doctype '
            'on fields: $searchTargets (primary: $primaryField)');
      }

      // 4. API Call
      final response = tokens.length <= 1
          ? await _apiProvider.getDocumentList(
              doctype,
              orFilters: {
                for (final field in fieldSet) field: ['like', '%$query%'],
              },
              limit: 20,
              fields: selectFields.toSet().toList(),
            )
          : await _apiProvider.getDocumentList(
              doctype,
              filterTuples: [
                for (final token in tokens)
                  [doctype, primaryField, 'like', '%$token%'],
              ],
              limit: 20,
              fields: selectFields.toSet().toList(),
            );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List data = response.data['data'];
        // The AND ran server-side, so the result is authoritative — no filter.
        return data.map((e) => _mapToModel(e, meta)).toList();
      }
    } catch (e) {
      print('GlobalSearchService Error ($doctype): $e');
    }
    return [];
  }

  /// Whitespace-separated, non-empty search tokens from [query]. Pure.
  static List<String> searchTokens(String query) => query
      .trim()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  /// The field to AND multi-word tokens against server-side: the doctype's
  /// [title_field] when it is a non-empty String (e.g. `item_name` for Item),
  /// else the first search target that isn't `name`, else `name`. Pure.
  static String resolvePrimarySearchField(
    Map<String, dynamic>? meta,
    List<String> searchTargets,
  ) {
    final title = meta?['title_field'];
    if (title is String && title.isNotEmpty) return title;
    for (final f in searchTargets) {
      if (f != 'name') return f;
    }
    return 'name';
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

  /// Default-warehouse balances for [itemCodes], aggregated per item code.
  /// Returns an empty map for empty input. Errors propagate to the caller (the
  /// delegate falls back to the chevron). A group warehouse is summed via
  /// [aggregateByItem]. The returned rows are narrowed to [itemCodes] first, so
  /// an older instance that couldn't push a multi-item filter server-side still
  /// yields only the requested items.
  Future<Map<String, WarehouseStockLine>> warehouseBalances(
    List<String> itemCodes,
    String warehouse,
  ) async {
    final codes = itemCodes.where((c) => c.isNotEmpty).toList();
    if (codes.isEmpty) return const {};
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
    return aggregateByItem(rows);
  }

  /// Aggregates Stock Balance report [rows] into one [WarehouseStockLine] per
  /// item code, SUMMING the balance (`bal_qty`, legacy `balance_qty`) across all
  /// rows for that item — so a group warehouse (which the report expands to its
  /// descendant leaf rows) yields the group total. `item_name` / `stock_uom` are
  /// taken from the first row that carries a non-empty value. Blank item codes
  /// are skipped. Pure.
  static Map<String, WarehouseStockLine> aggregateByItem(
    List<Map<String, dynamic>> rows,
  ) {
    final qty = <String, double>{};
    final name = <String, String>{};
    final uom = <String, String>{};
    final order = <String>[];
    for (final r in rows) {
      final code = (r['item_code'] ?? '').toString();
      if (code.isEmpty) continue;
      if (!qty.containsKey(code)) {
        qty[code] = 0;
        name[code] = '';
        uom[code] = '';
        order.add(code);
      }
      qty[code] = qty[code]! + _num(r, const ['bal_qty', 'balance_qty']);
      if (name[code]!.isEmpty) {
        final n = (r['item_name'] ?? '').toString();
        if (n.isNotEmpty) name[code] = n;
      }
      if (uom[code]!.isEmpty) {
        final u = (r['stock_uom'] ?? '').toString();
        if (u.isNotEmpty) uom[code] = u;
      }
    }
    return {
      for (final code in order)
        code: WarehouseStockLine(
          itemCode: code,
          itemName: name[code]!,
          balanceQty: qty[code]!,
          uom: uom[code]!,
        ),
    };
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
  ///
  /// Uses the desk `getdoctype` endpoint (reachable for operators) rather than
  /// `/api/resource/DocType/<name>`, which 403s for non-System-Manager users and
  /// would leave search matching only the document `name` (e.g. item_code), never
  /// descriptive fields like item_name.
  Future<void> _ensureMetadata(String doctype) async {
    if (_metadataCache.containsKey(doctype)) return;

    try {
      final response = await _apiProvider.getDocTypeMeta(doctype);
      final meta = extractDocTypeMeta(response.data, doctype);
      if (meta != null) {
        _metadataCache[doctype] = meta;

        // Parse Field Types
        final Map<String, String> types = {};
        final fields = meta['fields'];
        if (fields is List) {
          for (final field in fields) {
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

  /// The DocType meta doc for [doctype] from a `frappe.desk.form.load.getdoctype`
  /// response — the entry in `docs` with `doctype == 'DocType'` and matching
  /// `name`. Tolerates the `{docs: […]}` and `{message: {docs: […]}}` shapes.
  /// Returns null on any unexpected shape (fail-closed → name-only search). Pure.
  static Map<String, dynamic>? extractDocTypeMeta(
    dynamic data,
    String doctype,
  ) {
    if (data is! Map) return null;
    final docs = data['docs'] ??
        (data['message'] is Map ? data['message']['docs'] : null);
    if (docs is! List) return null;
    for (final doc in docs) {
      if (doc is Map &&
          doc['doctype'] == 'DocType' &&
          doc['name'] == doctype) {
        return doc.cast<String, dynamic>();
      }
    }
    return null;
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