import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Controller for the "POS and Delivery Note Item Rate" report.
///
/// Status is computed SERVER-SIDE by the script report (including the
/// Item Customer Detail triple check, which 403s for non-System-Manager
/// users when read directly) — the app never re-derives it. Parsing lives
/// in pure static helpers so it can be unit-tested without GetX or the
/// network.
class PosDnItemRateController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // Server-computed status strings (exact).
  static const statusNew        = 'New';
  static const statusMapped     = 'Already mapped';
  static const statusNoDelivery = 'No delivery line';
  static const statusNoCode     = 'No code';

  // ── Server-side filter state ────────────────────────────────────────────
  final posUploads     = <String>[].obs;
  final customers      = <String>[].obs;
  final customerGroups = <String>[].obs;
  final itemGroups     = <String>[].obs;
  final fromDate       = RxnString();
  final toDate         = RxnString();
  final showMapped     = false.obs;
  final onlyCoded      = false.obs;

  // ── Client-side quick filters ───────────────────────────────────────────
  final statusFilter = 'ALL'.obs;
  final searchQuery  = ''.obs;
  void setStatusFilter(String v) => statusFilter.value = v;
  void setSearchQuery(String v)  => searchQuery.value = v;

  // ── Result state ────────────────────────────────────────────────────────
  final reportRows   = <Map<String, dynamic>>[].obs;
  final isRunning    = false.obs;
  final hasRun       = false.obs;
  final errorMessage = RxnString();

  // ── Active-filter chips ─────────────────────────────────────────────────
  final activeFilters = <String, String>{}.obs;

  /// Result rows after the status chip + text search are applied.
  List<Map<String, dynamic>> get filteredRows =>
      applyFilters(reportRows, statusFilter.value, searchQuery.value);

  /// Per-status row counts over the full (unfiltered) result set.
  Map<String, int> get counts => statusCounts(reportRows);

  @override
  void onInit() {
    super.onInit();
    // Default window: the report is ~29k rows unfiltered (MAX_JOIN_SIZE
    // caveat) — never invite a full scan.
    fromDate.value = defaultFromDate(DateTime.now());
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> runReport() async {
    if (isRunning.value) return;
    isRunning.value = true;
    _rebuildActiveFilters();
    try {
      final resp = await _api.runPosDnItemRateReport(
        posUploads:     posUploads.toList(),
        fromDate:       fromDate.value,
        toDate:         toDate.value,
        customers:      customers.toList(),
        customerGroups: customerGroups.toList(),
        itemGroups:     itemGroups.toList(),
        showMapped:     showMapped.value,
        onlyCoded:      onlyCoded.value,
      );
      if (resp.statusCode == 200) {
        var rows = parseRows(resp.data['message']);
        final codes = <String>{
          for (final r in rows)
            if ((r['item_code'] ?? '').toString().isNotEmpty)
              r['item_code'].toString(),
        }.toList();
        if (codes.isNotEmpty) {
          try {
            final imgMap = await _api.getItemImages(codes);
            rows = attachImages(rows, imgMap, _api.baseUrl);
          } catch (_) {
            // Image enrichment is best-effort; rows still render without it.
          }
        }
        reportRows.assignAll(rows);
        hasRun.value = true;
        errorMessage.value = null;
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data?.toString() ?? '';
      errorMessage.value = code == 403
          ? 'You do not have access to this report.'
          : (code == 404 || body.contains('DoesNotExistError'))
              ? 'Report not deployed on this instance.'
              : 'Failed to run report.';
      GlobalSnackbar.error(
          title: 'Report Error', message: errorMessage.value!);
    } catch (e) {
      errorMessage.value = 'Failed to run report.';
      GlobalSnackbar.error(
          title: 'Report Error', message: 'POS & DN Item Rate: $e');
    } finally {
      isRunning.value = false;
    }
  }

  void addTo(RxList<String> list, String value) {
    final v = value.trim();
    if (v.isEmpty || list.contains(v)) return;
    list.add(v);
  }

  void removeFrom(RxList<String> list, String value) => list.remove(value);

  void clearFilters() {
    posUploads.clear();
    customers.clear();
    customerGroups.clear();
    itemGroups.clear();
    fromDate.value = defaultFromDate(DateTime.now());
    toDate.value = null;
    showMapped.value = false;
    onlyCoded.value = false;
    statusFilter.value = 'ALL';
    searchQuery.value = '';
    activeFilters.clear();
  }

  void clearFilter(String key) {
    switch (key) {
      case 'pos_upload':     posUploads.clear();
      case 'from_date':      fromDate.value = null;
      case 'to_date':        toDate.value = null;
      case 'customer':       customers.clear();
      case 'customer_group': customerGroups.clear();
      case 'item_group':     itemGroups.clear();
      case 'show_mapped':    showMapped.value = false;
      case 'only_coded':     onlyCoded.value = false;
    }
    activeFilters.remove(key);
  }

  void _rebuildActiveFilters() {
    final m = <String, String>{};
    if (posUploads.isNotEmpty) m['pos_upload'] = 'POS: ${posUploads.length}';
    if ((fromDate.value ?? '').isNotEmpty) m['from_date'] = 'From ${fromDate.value}';
    if ((toDate.value ?? '').isNotEmpty) m['to_date'] = 'To ${toDate.value}';
    if (customers.isNotEmpty) m['customer'] = 'Customers: ${customers.length}';
    if (customerGroups.isNotEmpty) {
      m['customer_group'] = 'Groups: ${customerGroups.length}';
    }
    if (itemGroups.isNotEmpty) m['item_group'] = 'Item Groups: ${itemGroups.length}';
    if (showMapped.value) m['show_mapped'] = 'Incl. mapped';
    if (onlyCoded.value) m['only_coded'] = 'Only coded';
    activeFilters.assignAll(m);
  }

  // ── Static parsers (pure) ───────────────────────────────────────────────

  /// Rows from a `query_report.run` `message`. Tolerates both row shapes:
  /// keyed maps (this report's normal output) and positional lists (zipped
  /// against `columns[].fieldname`).
  static List<Map<String, dynamic>> parseRows(dynamic message) {
    if (message is! Map) return [];
    final result = message['result'];
    if (result is! List) return [];
    final columns = message['columns'];
    final fieldnames = <String>[
      if (columns is List)
        for (final c in columns.whereType<Map>())
          (c['fieldname'] ?? '').toString(),
    ];
    final rows = <Map<String, dynamic>>[];
    for (final e in result) {
      if (e is Map) {
        rows.add(Map<String, dynamic>.from(e));
      } else if (e is List && fieldnames.isNotEmpty) {
        rows.add({
          for (var i = 0; i < e.length && i < fieldnames.length; i++)
            if (fieldnames[i].isNotEmpty) fieldnames[i]: e[i],
        });
      }
    }
    const known = {statusNew, statusMapped, statusNoDelivery, statusNoCode};
    return rows
        .where((r) => known.contains((r['status'] ?? '').toString()))
        .toList();
  }

  /// Row count per server `status` value.
  static Map<String, int> statusCounts(List<Map<String, dynamic>> rows) {
    final counts = <String, int>{};
    for (final r in rows) {
      final s = (r['status'] ?? '').toString();
      if (s.isEmpty) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// Applies the status chip ('ALL' = no-op) and a case-insensitive text
  /// query over the code / item / customer / voucher fields.
  static List<Map<String, dynamic>> applyFilters(
      List<Map<String, dynamic>> rows, String status, String query) {
    Iterable<Map<String, dynamic>> out = rows;
    if (status != 'ALL') {
      out = out.where((r) => (r['status'] ?? '').toString() == status);
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      const searched = [
        'ref_code', 'item_code', 'dn_item', 'upload_item',
        'customer', 'dn_name', 'pos_upload',
      ];
      out = out.where((r) => searched.any(
          (f) => (r[f] ?? '').toString().toLowerCase().contains(q)));
    }
    return out.toList();
  }

  /// 30 days before [now], formatted yyyy-MM-dd.
  static String defaultFromDate(DateTime now) {
    final d = now.subtract(const Duration(days: 30));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Returns [rows] with an absolute `item_image` URL set from [imgMap]
  /// (keyed by item code). Relative frappe paths are prefixed with [baseUrl]
  /// (one trailing slash trimmed); `http…` values are kept as-is; rows whose
  /// code has no image are left untouched. Mirrors Stock Balance.
  static List<Map<String, dynamic>> attachImages(
    List<Map<String, dynamic>> rows,
    Map<String, String> imgMap,
    String baseUrl,
  ) {
    if (imgMap.isEmpty) return rows;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return rows.map((r) {
      final code = (r['item_code'] ?? '').toString();
      final img = imgMap[code];
      if (img == null || img.isEmpty) return r;
      final url = img.startsWith('http') ? img : '$base$img';
      return {...r, 'item_image': url};
    }).toList();
  }

  /// Row count + summed quantity columns over [rows]. Rate is intentionally
  /// NOT summed (summing rates across items is meaningless). Non-numeric /
  /// null qty values contribute 0.
  static Map<String, num> sumTotals(List<Map<String, dynamic>> rows) {
    num pos = 0, dn = 0;
    for (final r in rows) {
      pos += _numOrZero(r['upload_qty']);
      dn += _numOrZero(r['dn_qty']);
    }
    return {'count': rows.length, 'pos_qty': pos, 'dn_qty': dn};
  }

  static num _numOrZero(dynamic v) =>
      v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);
}
