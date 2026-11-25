import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, FileSystemException, PathNotFoundException;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/batch_wise_balance_row.dart';
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/safe_log_interceptor.dart';
import 'package:multimax/app/data/providers/session_expiry_interceptor.dart';
import 'package:multimax/app/data/providers/csrf_interceptor.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/session_cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/data/services/link_title_cache.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

typedef BatchWiseBalanceResult = ({
  List<DeskColumn>? columns,
  List<Map<String, dynamic>> rows,
});

typedef StockLedgerReportResult = ({
  List<DeskColumn> columns,
  List<Map<String, dynamic>> rows,
});

typedef ItemVariantDetailsResult = ({
  List<Map<String, dynamic>> columns,
  List<Map<String, dynamic>> rows,
});

typedef RackStockBalanceResult = ({
  List<DeskColumn> columns,
  List<Map<String, dynamic>> rows,
});

class ApiProvider {
  static const String defaultBaseUrl = "https://erp.domain.com";
  static const stockBalancePositionalRowKey = '#stock_balance_positional_row';

  bool _dioInitialised = false;
  Future<void>? _dioInitialization;
  Future<void>? _cookieCleanup;
  final PersistCookieJar Function(String directory) _createCookieJar;
  late Dio _dio;
  late String _cookiePath;
  late CookieManager _cookieManager;
  String _baseUrl = defaultBaseUrl;

  String get baseUrl => _baseUrl;

  // Invalidates authenticated rack master reads when the login or site changes.
  int _rackWarehouseSession = 0;
  int get rackWarehouseSession => _rackWarehouseSession;

  /// Session hooks, set by AuthenticationController. ApiProvider is created
  /// first, so it cannot look the controller up itself.
  bool Function() hasActiveSession = () => false;
  void Function() onSessionExpired = () {};

  // Expose for providers that need raw Dio access (e.g. makeJobCard form-post)
  bool get isDioInitialised => _dioInitialised;
  Dio get dio => _dio;
  Future<void> initDio() => _initDio();

  // ── Stock Balance filter compatibility (v15.72.0 breaking change) ──────────
  // ERPNext v15.72.0 changed `item_code` from a single Link to a
  // MultiSelectList. The report now calls PyPika's .isin() on the filter
  // value, which iterates a bare string character-by-character and matches
  // nothing. Versions ≥ 15.72 need a list; older versions need a plain string.
  bool? _stockBalanceUsesListFilters;
  String? _erpNextVersion;

  Future<bool> _getStockBalanceUsesListFilters() async {
    if (_stockBalanceUsesListFilters != null) return _stockBalanceUsesListFilters!;
    try {
      if (!_dioInitialised) await _initDio();
      _erpNextVersion = await _fetchErpNextVersion();
      _stockBalanceUsesListFilters =
          stockBalanceUsesListFilters(_erpNextVersion);
    } catch (_) {
      _stockBalanceUsesListFilters = true;
    }
    return _stockBalanceUsesListFilters!;
  }

  /// Whether ERPNext [version]'s Stock Balance report needs `item_code` as a
  /// list: true from v15.72.0 on — including every v16+, whatever its minor
  /// (the old minor-only check sent v16.26 a string and the report 500'd).
  /// Unknown/unparsable versions assume the current (list) behaviour.
  static bool stockBalanceUsesListFilters(String? version) {
    final m = RegExp(r'^(\d+)\.(\d+)').firstMatch(version?.trim() ?? '');
    if (m == null) return true;
    final major = int.parse(m.group(1)!);
    final minor = int.parse(m.group(2)!);
    if (major != 15) return major > 15;
    return minor >= 72;
  }

  /// Tries two endpoints to obtain the ERPNext version string.
  /// Primary: get_versions (may crash on some builds due to a server-side bug).
  /// Fallback: get_change_log (different code path, reads markdown files).
  Future<String?> _fetchErpNextVersion() async {
    try {
      final r = await _dio.get('/api/method/frappe.utils.change_log.get_versions');
      final msg = r.data['message'] as Map<String, dynamic>?;
      final v = (msg?['erpnext'] as Map<String, dynamic>?)?['version'] as String?;
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    try {
      final r = await _dio.get('/api/method/frappe.utils.change_log.get_change_log');
      final entries = r.data['message'];
      if (entries is List) {
        for (final e in entries) {
          if (e is Map && (e['title'] as String?)?.contains('ERPNext') == true) {
            final v = e['version'] as String?;
            if (v != null && v.isNotEmpty) return v;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Returns the cached ERPNext version string, fetching it if needed.
  Future<String?> getErpNextVersion() async {
    if (_erpNextVersion != null || _stockBalanceUsesListFilters != null) {
      return _erpNextVersion;
    }
    await _getStockBalanceUsesListFilters();
    return _erpNextVersion;
  }

  /// Returns [itemCode] as a list on ERPNext ≥ v15.72.0, or as a plain string
  /// on older versions, to match the Stock Balance `item_code` filter type.
  Future<dynamic> stockBalanceItemCodeFilter(String itemCode) async {
    return (await _getStockBalanceUsesListFilters()) ? [itemCode] : itemCode;
  }

  /// Resolves a Customer Code to the parent Item codes that carry it.
  ///
  /// The Stock Balance report has no customer filter; "Customer Code" lives in
  /// the Item's `customer_items` child (Item Customer Detail) `ref_code` field.
  /// Returns the distinct parent item codes whose `ref_code` contains [code]
  /// (case-insensitive substring, mirroring the web grid's "like" filter).
  Future<List<String>> resolveItemsByCustomerCode(String code) async {
    final query = code.trim();
    if (query.isEmpty) return <String>[];
    // List Item (which the user can read) and join-filter on the child table
    // — querying /api/resource/Item Customer Detail directly returns 403.
    final rows = await getList(
      null,
      doctype:       'Item',
      fields:        ['name'],
      filters:       {'ref_code': ['like', '%$query%']},
      filterDoctype: 'Item Customer Detail',
      limit:         0, // 0 = no page limit (all matches)
      orderBy:       'name asc',
    );
    return rows
        .map((r) => (r['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  /// Fetches the Customer Code (Item `customer_code` field) for [itemCodes].
  ///
  /// The Stock Balance report response omits this column, so we read it the
  /// same way the web report's "Add Column" feature does, via
  /// `query_report.get_data_for_custom_field`. Returns a map of item code →
  /// customer code; empty on any failure (display-only enrichment).
  Future<Map<String, String>> getItemCustomerCodes(List<String> itemCodes) async {
    final names = itemCodes.where((c) => c.isNotEmpty).toSet().toList();
    if (names.isEmpty) return <String, String>{};
    if (!_dioInitialised) await _initDio();
    try {
      final response = await _dio.post(
        '/api/method/frappe.desk.query_report.get_data_for_custom_field',
        data: {
          'doctype': 'Item',
          'field'  : 'customer_code',
          'names'  : json.encode(names),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final message = response.data['message'];
      if (message is Map) {
        return message.map(
          (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
        );
      }
    } catch (_) {
      // Enrichment only — never block the report on this.
    }
    return <String, String>{};
  }
  // ──────────────────────────────────────────────────────────────────────────

  ApiProvider({PersistCookieJar Function(String directory)? cookieJarFactory})
      : _createCookieJar = cookieJarFactory ?? createSessionCookieJar {
    // Prewarm the client. A request awaiting initialization still receives
    // any local error and can retry.
    unawaited(_initDio().catchError((Object _) {}));
  }

  void setBaseUrl(String url) {
    _rackWarehouseSession++;
    _baseUrl = url;
    _stockBalanceUsesListFilters = null;
    _erpNextVersion = null;
    clearDeskHtml();
    if (_dioInitialised) {
      _dio.options.baseUrl = _baseUrl;
    }
  }

  Future<void> _initDio() async {
    if (_dioInitialised) return;
    await (_dioInitialization ??=
        _createDio().whenComplete(() => _dioInitialization = null));
  }

  Future<void> _createDio() async {
    // Load URL from SQLite Database
    if (Get.isRegistered<DatabaseService>()) {
      final dbService = Get.find<DatabaseService>();
      final storedUrl = await dbService.getConfig(DatabaseService.serverUrlKey);
      if (storedUrl != null && storedUrl.isNotEmpty) {
        _baseUrl = storedUrl;
      }
    }

    if (Get.isRegistered<StorageService>()) {
      final storedUrl = Get.find<StorageService>().getBaseUrl();
      if (storedUrl != null && storedUrl.isNotEmpty) {
        _baseUrl = storedUrl;
      }
    }
    final appSupportDir = await getApplicationSupportDirectory();
    _cookiePath = p.join(appSupportDir.path, '.cookies');
    _cookieManager = CookieManager(_createCookieJar(_cookiePath));
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
    _dio.interceptors.add(_cookieManager);
    _dio.interceptors.add(CsrfInterceptor(dio: _dio));
    _dio.interceptors.add(SessionExpiryInterceptor(
      dio: _dio,
      hasActiveSession: () => hasActiveSession(),
      onSessionExpired: () => onSessionExpired(),
    ));
    // Debug builds only: release builds skip the formatting work as well.
    if (kDebugMode) {
      _dio.interceptors.add(SafeLogInterceptor());
    }
    _dioInitialised = true;
  }

  // ---------------------------------------------------------------------------
  // GENERIC METHODS
  // ---------------------------------------------------------------------------

  Future<Response> getDocumentList(String doctype, {
    int limit = 20,
    int limitStart = 0,
    List<String>? fields,
    String? groupBy = '',
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
    Map<String, dynamic>? orFilters,
    List<List<dynamic>>? orFilterTuples,
    String orderBy = 'modified desc',
  }) async {
    if (!_dioInitialised) await _initDio();

    final String endpoint = '/api/resource/$doctype';
    final queryParameters = {
      'limit_page_length': limit,
      'limit_start': limitStart,
      'order_by': orderBy,
      if (groupBy!.isNotEmpty) 'group_by': groupBy,
    };

    if (fields != null) {
      queryParameters['fields'] = json.encode(fields);
    }

    // Process Standard Filters (AND). An explicit pre-built tuple list (each
    // entry a complete Frappe [doctype, field, op, value]) wins; otherwise
    // expand the Map form.
    if (filterTuples != null && filterTuples.isNotEmpty) {
      queryParameters['filters'] = json.encode(filterTuples);
    } else if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        final val = entry.value;
        if (val is List) {
          // 4-element: already a complete Frappe tuple — pass through as-is.
          // Used for child-table filters: ["Job Card Time Log","employee","=","HR-EMP-00013"]
          if (val.length == 4) return List<dynamic>.from(val);
          // 3-element: child-table filter stored as [childDoctype, field, op, value]
          // where key == childDoctype. Expand to full 4-element tuple.
          if (val.length == 3) return [entry.key, val[0], val[1], val[2]];
          // 2-element: standard [operator, value] tuple — prepend doctype + key.
          if (val.length == 2) return [doctype, entry.key, val[0], val[1]];
        }
        // Plain scalar value — equality filter.
        return [doctype, entry.key, '=', val];
      }).toList();

      queryParameters['filters'] = json.encode(filterList);
    }

    // Process OR Filters. An explicit pre-built tuple list (each entry a complete
    // Frappe [doctype, field, op, value]) wins; otherwise expand the Map form.
    if (orFilterTuples != null && orFilterTuples.isNotEmpty) {
      queryParameters['or_filters'] = json.encode(orFilterTuples);
    } else if (orFilters != null && orFilters.isNotEmpty) {
      final List<List<dynamic>> orFilterList = orFilters.entries.map((entry) {
        final val = entry.value;
        if (val is List) {
          if (val.length == 4) return List<dynamic>.from(val);
          if (val.length == 3) return [entry.key, val[0], val[1], val[2]];
          if (val.length == 2) return [doctype, entry.key, val[0], val[1]];
        }
        return [doctype, entry.key, '=', val];
      }).toList();

      queryParameters['or_filters'] = json.encode(orFilterList);
    }

    try {
      return await _dio.get(endpoint, queryParameters: queryParameters);
    } on DioException {
      rethrow;
    }
  }

  // Support for Frappe Desk Report View (allows advanced joins/filtering)
  Future<Response> getReportView(String doctype, {
    int start = 0,
    int pageLength = 20,
    List<String>? fields,
    List<List<dynamic>>? filters,
    String orderBy = 'modified desc',
  }) async {
    if (!_dioInitialised) await _initDio();

    final data = {
      'doctype': doctype,
      'fields': json.encode(fields ?? ['`tab$doctype`.`name`']),
      'filters': json.encode(filters ?? []),
      'order_by': orderBy,
      'start': start,
      'page_length': pageLength,
      'view': 'List',
      'group_by': '`tab$doctype`.`name`',
      'with_comment_count': 1
    };

    // Using POST as per standard ReportView usage
    return await _dio.post('/api/method/frappe.desk.reportview.get',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType)
    );
  }

  Future<Response> getDocument(String doctype, String name) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/resource/$doctype/$name');
  }

  Future<Response> createDocument(String doctype, Map<String, dynamic> data) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post('/api/resource/$doctype', data: data);
  }

  Future<Response> updateDocument(String doctype, String name, Map<String, dynamic> data) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.put('/api/resource/$doctype/$name', data: data);
  }

  Future<Response> deleteDocument(String doctype, String name) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.delete('/api/resource/$doctype/$name');
  }

  /// Submit a document (change docstatus from 0 to 1) in ERP.
  Future<Response> submitDocument(String doctype, String name) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.put('/api/resource/$doctype/$name', data: {'docstatus': 1});
  }

  /// Call a Frappe whitelisted method via GET with query parameters.
  Future<Response> callMethod(String method, {Map<String, dynamic>? params}) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/method/$method', queryParameters: params);
  }

  /// Call a Frappe whitelisted method via POST with a form-urlencoded body.
  Future<Response> callMethodPost(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post(
      '/api/method/$method',
      data: params,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  /// Probes whether the current session user can list [doctype].
  ///
  /// Uses `frappe.client.get_list` with `limit=1` as a permission probe:
  /// HTTP 200 (even empty list) → has access; HTTP 403 → denied.
  /// `frappe.client.has_permission` requires a `docname` positional arg in
  /// Frappe v15 and cannot check DocType-level access without it.
  /// [permType] is accepted for API compatibility but not sent to the server —
  /// list access is the binding check for both read and report in standard ERPNext.
  Future<Response> hasPermission(String doctype, String permType) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get(
      '/api/method/frappe.client.get_list',
      queryParameters: {
        'doctype': doctype,
        'limit_page_length': 1,
        'fields': '["name"]',
      },
    );
  }

  /// Parses a `frappe.client.get_list` permission-probe response into a [bool].
  ///
  /// Expected shape: `{"message": [...]}` — a List (possibly empty) means
  /// the user has access; anything else (null, non-Map, missing key) means denied.
  /// HTTP 403 is handled upstream as a [DioException]; this method only sees
  /// the successful-200 body.
  /// Exposed as a public static method so unit tests can exercise this
  /// logic without a live HTTP connection.
  static bool parseHasPermissionResponse(dynamic data) {
    if (data is! Map) return false;
    return data['message'] is List;
  }

  /// Checks whether the current session user has [ptype] permission on the
  /// specific document [name] of [doctype], via `frappe.client.has_permission`.
  ///
  /// Frappe v15 requires a docname for this method, so it is only meaningful
  /// for already-saved documents (e.g. submitting a saved draft).
  Future<Response> hasDocPermission(
      String doctype, String name, String ptype) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get(
      '/api/method/frappe.client.has_permission',
      queryParameters: {
        'doctype':   doctype,
        'docname':   name,
        'perm_type': ptype,
      },
    );
  }

  /// Checks whether the current session user holds [ptype] on [doctype] as a
  /// whole, via `frappe.client.has_permission`.
  ///
  /// The method's `docname` argument is mandatory, but an empty value makes
  /// Frappe (v15 and v16) skip the per-document check and evaluate the
  /// DocType-level permission. Parse with [parseHasDocPermissionResponse].
  Future<Response> hasDocTypePermission(String doctype, String ptype) =>
      hasDocPermission(doctype, '', ptype);

  /// Parses a `frappe.client.has_permission` response into a [bool].
  ///
  /// Expected shape: `{"message": {"has_permission": 1|true}}`.
  /// Anything else (null, non-Map, missing keys, falsy value) → `false`
  /// (fail-closed). Exposed as a public static method so unit tests can
  /// exercise it without a live HTTP connection.
  static bool parseHasDocPermissionResponse(dynamic data) {
    if (data is! Map) return false;
    final message = data['message'];
    if (message is! Map) return false;
    final value = message['has_permission'];
    return value == true || value == 1;
  }

  /// Fetches the DocPerm rows for [doctype] and returns the sets of roles that
  /// hold `create` and `write` at permlevel 0 — used to gate create/edit UI.
  ///
  /// Sourced from `frappe.desk.form.load.getdoctype` (the endpoint the desk
  /// itself uses to render forms) rather than `/api/resource/DocType/<name>`.
  /// The resource endpoint requires read access on the `DocType` doctype and
  /// returns 403 for ordinary operators (e.g. Stock User), which would leave
  /// the role sets empty and wrongly hide their create/edit buttons; getdoctype
  /// is gated on the target doctype instead, so those users get the rows.
  Future<({Set<String> create, Set<String> write, String? module})>
      fetchDocTypeRoles(
      String doctype) async {
    final response = await callMethod(
      'frappe.desk.form.load.getdoctype',
      params: {'doctype': doctype, 'with_parent': 1},
    );
    return (
      create: rolesWithPermission(response.data, doctype, 'create'),
      write: rolesWithPermission(response.data, doctype, 'write'),
      module: docTypeModule(response.data, doctype),
    );
  }

  /// DocType metadata via the desk `getdoctype` endpoint — reachable for
  /// ordinary operators, unlike `/api/resource/DocType/<name>` (which 403s
  /// without read access on the DocType doctype). Returns the raw method
  /// response; callers pull the target doc from `data['docs']`.
  Future<Response> getDocTypeMeta(String doctype) => callMethod(
        'frappe.desk.form.load.getdoctype',
        params: {'doctype': doctype, 'with_parent': 1},
      );

  /// Extracts the roles granting [permKey] (`create`, `write`, …) at
  /// [permlevel] (default 0) for [doctype] from a `getdoctype` response.
  ///
  /// getdoctype returns `{"docs": [<DocType meta>, …]}` (unwrapped); this also
  /// tolerates a `{"message": {"docs": …}}` shape defensively. Fail-closed:
  /// any unexpected shape yields an empty set. Exposed as a public static
  /// method so unit tests can exercise it without a live HTTP connection.
  static Set<String> rolesWithPermission(
      dynamic data, String doctype, String permKey,
      {int permlevel = 0}) {
    final roles = <String>{};
    final meta = _docTypeMeta(data, doctype);
    final perms = meta?['permissions'];
    if (perms is! List) return roles;
    for (final p in perms) {
      if (p is! Map) continue;
      // Frappe omits permlevel on some rows; an absent value means level 0.
      final lvl = p['permlevel'] ?? 0;
      if (lvl == permlevel && p[permKey] == 1) {
        final role = p['role'];
        if (role is String && role.isNotEmpty) roles.add(role);
      }
    }
    return roles;
  }

  /// The `permlevel` of [fieldname] on [doctype] from a `getdoctype`
  /// response, or `null` when the meta or field cannot be found (callers
  /// should fail closed on `null`). A field present without an explicit
  /// `permlevel` is level 0 — Frappe's default.
  static int? fieldPermlevel(dynamic data, String doctype, String fieldname) {
    final meta = _docTypeMeta(data, doctype);
    final fields = meta?['fields'];
    if (fields is! List) return null;
    for (final f in fields) {
      if (f is! Map || f['fieldname'] != fieldname) continue;
      final lvl = f['permlevel'];
      return lvl is int ? lvl : 0;
    }
    return null;
  }

  /// Whether [userRoles] may write [fieldname] of [doctype] per a
  /// `getdoctype` response. Fields at permlevel 0 are governed by the
  /// doc-level write permission (checked separately by callers), so they
  /// pass here; higher-permlevel fields need a DocPerm `write` rule at that
  /// level for one of the user's roles. `System Manager` bypasses, mirroring
  /// [PermissionService.roleGrants]. Fail-closed: unparseable meta or a
  /// missing field denies.
  static bool fieldWriteGranted(
      dynamic data, String doctype, String fieldname, Set<String> userRoles) {
    final permlevel = fieldPermlevel(data, doctype, fieldname);
    if (permlevel == null) return false;
    if (permlevel == 0) return true;
    if (userRoles.contains('System Manager')) return true;
    final writers =
        rolesWithPermission(data, doctype, 'write', permlevel: permlevel);
    return writers.any(userRoles.contains);
  }

  /// The Frappe module of [doctype] from a `getdoctype` response, or `null`.
  static String? docTypeModule(dynamic data, String doctype) {
    final module = _docTypeMeta(data, doctype)?['module'];
    return module is String && module.isNotEmpty ? module : null;
  }

  /// The DocType meta map for [doctype] inside a `getdoctype` response,
  /// or `null` when the shape is unexpected.
  static Map? _docTypeMeta(dynamic data, String doctype) {
    if (data is! Map) return null;
    final docs = data['docs'] ??
        (data['message'] is Map ? data['message']['docs'] : null);
    if (docs is! List) return null;
    for (final doc in docs) {
      if (doc is! Map) continue;
      if (doc['doctype'] == 'DocType' && doc['name'] == doctype) return doc;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // REPORT & LIST HELPERS
  // ---------------------------------------------------------------------------

  /// Named-param version used by [ItemSheetControllerBase.validateBatch] and
  /// any other caller that needs to filter by fields.
  ///
  /// Returns a [List<Map<String, dynamic>>] of matching document rows so
  /// callers can read individual field values (e.g. expiry_date).
  ///
  /// [positional] is an OPTIONAL positional kept for backwards compat with
  /// any legacy call-site that still passes the doctype positionally.
  /// New call-sites should use the named [doctype] parameter instead:
  ///
  ///   ApiProvider().getList(doctype: 'Batch', filters: {...}, fields: [...])
  ///
  /// Group D fix: the param was previously declared as a required positional
  /// (String? positional) with no default — callers that omitted it (i.e.
  /// all named-only call-sites) produced a compile error.  Wrapping in
  /// square brackets makes it an optional positional with an implicit null
  /// default, so both calling styles compile correctly.
  Future<List<Map<String, dynamic>>> getList(
    String? positional, {
    String? doctype,
    Map<String, dynamic>? filters,
    List<String>? fields,
    int limit = 20,
    String orderBy = 'modified desc',
    String? groupBy = '',
    String? filterDoctype,
  }) async {
    final dt = positional ?? doctype;
    if (dt == null) return [];

    // Frappe supports filtering a parent doctype by a child-table field by
    // setting the filter's doctype to the CHILD doctype while listing the
    // parent (a join filter). [filterDoctype] overrides the doctype used in
    // each filter tuple; it defaults to the listed doctype [dt].
    final filterDt = filterDoctype ?? dt;

    try {
      if (!_dioInitialised) await _initDio();
      final response = await _dio.get('/api/resource/$dt', queryParameters: {
        if (fields != null) 'fields': json.encode(fields)
        else 'fields': json.encode(['name']),
        'limit_page_length': limit,
        'order_by': orderBy,
        if (groupBy!.isNotEmpty) 'group_by': groupBy,
        if (filters != null && filters.isNotEmpty)
          'filters': json.encode(
            filters.entries.map((e) {
              if (e.value is List && (e.value as List).length == 2) {
                return [filterDt, e.key, e.value[0], e.value[1]];
              }
              return [filterDt, e.key, '=', e.value];
            }).toList(),
          ),
      });
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching list for $dt: $e');
    }
    return [];
  }

  /// Legacy positional convenience; returns names only.
  /// Prefer [getList] with named params for any new call-sites.
  Future<List<String>> getListSimple(String doctype) async {
    try {
      if (!_dioInitialised) await _initDio();
      final response = await _dio.get('/api/resource/$doctype', queryParameters: {
        'fields': json.encode(['name']),
        'limit_page_length': 0,
        'order_by': 'name asc'
      });
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      debugPrint('Error fetching list for $doctype: $e');
    }
    return [];
  }

  /// Parses a Frappe `/api/resource/Rack` response into rack name strings.
  ///
  /// Expects `data['data']` to be a `List` of maps each with a `'name'` key.
  /// Skips null entries, non-Map entries, and entries with a null or empty name.
  /// Returns an empty list on any shape mismatch or null input.
  static List<String> parseRacksByWarehouseResponse(dynamic data) {
    if (data == null) return [];
    final rawList = data['data'];
    if (rawList is! List) return [];
    final result = <String>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final name = item['name'];
      if (name is String && name.isNotEmpty) {
        result.add(name);
      }
    }
    return result;
  }

  /// Fetches every Rack name linked to the exact [warehouse].
  Future<List<String>> getRacksByWarehouse(String warehouse) async {
    if (warehouse.isEmpty) return [];
    try {
      const pageSize = 100;
      final racks = <String>[];
      for (var start = 0; ; start += pageSize) {
        final response = await getDocumentList(
          'Rack',
          fields: ['name'],
          filters: {'warehouse': warehouse},
          limit: pageSize,
          limitStart: start,
          orderBy: 'name asc',
        );
        final data = response.data;
        if (data is! Map || data['data'] is! List) return [];
        racks.addAll(parseRacksByWarehouseResponse(data));
        if ((data['data'] as List).length < pageSize) return racks;
      }
    } catch (_) {
      return [];
    }
  }

  /// Extracts the `warehouse` link from a `GET /api/resource/Rack/{name}`
  /// response body. Returns null on any shape mismatch or empty value.
  static String? parseRackWarehouseResponse(dynamic data) {
    if (data is! Map) return null;
    final doc = data['data'];
    if (doc is! Map) return null;
    final wh = doc['warehouse'];
    return (wh is String && wh.isNotEmpty) ? wh : null;
  }

  /// Distinguishes an existing Rack with an absent link from 404 and failures.
  static RackWarehouseLookup parseRackLookupResponse(Object? data) {
    if (data is! Map || data['data'] is! Map) {
      return const RackWarehouseLookup.error();
    }
    final doc = data['data'] as Map;
    final name = doc['name'];
    final warehouse = doc['warehouse'];
    if (name is! String || name.trim().isEmpty ||
        (warehouse != null && warehouse is! String)) {
      return const RackWarehouseLookup.error();
    }
    return RackWarehouseLookup.found(
      parseRackWarehouseResponse(data),
      name: name,
    );
  }

  Future<RackWarehouseLookup> getRackWarehouse(String rack) async {
    if (rack.isEmpty) return const RackWarehouseLookup.notFound();
    try {
      final response = await getDocument('Rack', Uri.encodeComponent(rack));
      if (response.statusCode == 200) {
        return parseRackLookupResponse(response.data);
      }
      if (response.statusCode == 404) {
        return const RackWarehouseLookup.notFound();
      }
      return const RackWarehouseLookup.error();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const RackWarehouseLookup.notFound();
      }
      return const RackWarehouseLookup.error();
    } catch (_) {
      return const RackWarehouseLookup.error();
    }
  }

  Future<Response> getReport(String reportName, {Map<String, dynamic>? filters}) async {
    if (!_dioInitialised) await _initDio();

    return await _dio.get('/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name': reportName,
          'filters': json.encode(filters ?? {}),
          'ignore_prepared_report': 'true',
          '_': DateTime.now().millisecondsSinceEpoch
        }
    );
  }

  Future<Response> getStockBalance({
    required String itemCode,
    String? warehouse,
    String? batchNo,
    String? rack,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final String company = storage.getCompany();
    final String? targetWarehouse = warehouse;

    if (targetWarehouse == null || targetWarehouse.isEmpty) {
      throw Exception('Warehouse is required to check stock balance.');
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final Map<String, dynamic> filters = {
      "company": company,
      "from_date": today,
      "to_date": today,
      "item_code": await stockBalanceItemCodeFilter(itemCode),
      "valuation_field_type": "Currency",
      "rack": rack != null && rack.isNotEmpty ? [rack] : [],
      "show_variant_attributes": 1,
      "show_dimension_wise_stock": 1
    };

    if (batchNo != null && batchNo.isNotEmpty) {
      filters["batch_no"] = batchNo;
    }

    return await _dio.get('/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name': 'Stock Balance',
          'filters': json.encode(filters),
          'ignore_prepared_report': 'true',
          '_': DateTime.now().millisecondsSinceEpoch
        }
    );
  }

  /// Builds the `filters` payload for the Stock Balance report. Pure, so the
  /// filter contract is unit-testable; [itemCodeFilter] is the already
  /// version-resolved value (scalar or list) or null to omit.
  ///
  /// Mirrors the v15 desk report (`stock_balance.js`):
  ///   • `warehouse` is a MultiSelectList server-side (list → `lft/rgt`
  ///     range per entry); a single warehouse is still sent as a scalar, the
  ///     path every instance version honours.
  ///   • `warehouse_type` only applies when no warehouse is chosen.
  ///   • `rack` is an Inventory Dimension filter — always a list (`.isin`).
  ///   • `include_uom` adds `<col>_alt` converted columns.
  ///   • Check filters are sent as `1` only when on (omitted = 0).
  static Map<String, dynamic> buildStockBalanceFilters({
    required String company,
    required String fromDate,
    required String toDate,
    dynamic itemCodeFilter,
    List<String>? warehouses,
    String? itemGroup,
    String? warehouseType,
    String? rack,
    String? includeUom,
    bool showDimensionWise      = false,
    bool showVariantAttributes  = false,
    bool showStockAgeing        = false,
    bool ignoreClosingBalance   = false,
    bool includeZeroStockItems  = false,
  }) {
    final warehouseFilter = _stockBalanceWarehouseFilter(warehouses);
    return <String, dynamic>{
      'company'             : company,
      'from_date'           : fromDate,
      'to_date'             : toDate,
      'valuation_field_type': 'Currency',
      if (itemCodeFilter != null)
        'item_code'         : itemCodeFilter,
      if (warehouseFilter != null) 'warehouse': warehouseFilter,
      if (itemGroup != null && itemGroup.isNotEmpty)
        'item_group'        : itemGroup,
      if (warehouseType != null && warehouseType.isNotEmpty)
        'warehouse_type'    : warehouseType,
      if (rack != null && rack.isNotEmpty)
        'rack'              : [rack],
      if (includeUom != null && includeUom.isNotEmpty)
        'include_uom'       : includeUom,
      if (showDimensionWise)     'show_dimension_wise_stock': 1,
      if (showVariantAttributes) 'show_variant_attributes'  : 1,
      if (showStockAgeing)       'show_stock_ageing_data'   : 1,
      if (ignoreClosingBalance)  'ignore_closing_balance'   : 1,
      if (includeZeroStockItems) 'include_zero_stock_items' : 1,
    };
  }

  static Object? _stockBalanceWarehouseFilter(List<String>? warehouses) {
    final selected = warehouses?.where((w) => w.trim().isNotEmpty).toList();
    if (selected == null || selected.isEmpty) return null;
    return selected.length == 1 ? selected.single : selected;
  }

  Future<({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})>
      getStockBalanceReport({
    required String fromDate,
    required String toDate,
    List<String>? itemCodes,
    List<String>? warehouses,
    String? itemGroup,
    String? warehouseType,
    String? rack,
    String? includeUom,
    bool showDimensionWise      = false,
    bool showVariantAttributes  = false,
    bool showStockAgeing        = false,
    bool ignoreClosingBalance   = false,
    bool includeZeroStockItems  = false,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();

    // The Stock Balance report's item_code filter is a single SQL scalar on
    // older instances (≤ v15.71) and a proper list on v15.72+. Push the
    // restriction server-side only when the instance can honour it:
    //   • a single item works on every version;
    //   • multiple items are sent as a list only on v15.72+.
    // When a multi-item restriction can't be sent, item_code is omitted and
    // the caller narrows the rows client-side.
    final items = itemCodes?.where((c) => c.isNotEmpty).toList() ?? const [];
    dynamic itemCodeFilter;
    if (items.length == 1) {
      itemCodeFilter = await stockBalanceItemCodeFilter(items.first);
    } else if (items.length > 1 && await _getStockBalanceUsesListFilters()) {
      itemCodeFilter = items;
    }

    final filters = buildStockBalanceFilters(
      company:               storage.getCompany(),
      fromDate:              fromDate,
      toDate:                toDate,
      itemCodeFilter:        itemCodeFilter,
      warehouses:            warehouses,
      itemGroup:             itemGroup,
      warehouseType:         warehouseType,
      rack:                  rack,
      includeUom:            includeUom,
      showDimensionWise:     showDimensionWise,
      showVariantAttributes: showVariantAttributes,
      showStockAgeing:       showStockAgeing,
      ignoreClosingBalance:  ignoreClosingBalance,
      includeZeroStockItems: includeZeroStockItems,
    );

    late final Response response;
    try {
      response = await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'           : 'Stock Balance',
          'filters'               : json.encode(filters),
          'ignore_prepared_report': 'true',
          '_'                     : DateTime.now().millisecondsSinceEpoch,
        },
      );
    } on DioException {
      rethrow;
    } catch (_) {
      rethrow;
    }

    if (response.statusCode != 200) {
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 0,
        requestOptions: response.requestOptions,
        response: response,
      );
    }

    final data = response.data;
    final message = data is Map ? data['message'] : null;
    if (message is! Map<String, dynamic> || message['result'] is! List) {
      throw const FormatException('Stock Balance response has no result list');
    }
    return parseStockBalanceResponse(message);
  }

  // ---------------------------------------------------------------------------
  // getBatchWiseBalance
  //
  // All-named params, optional batchNo (omit = fetch all batches for item+wh).
  // Used by ItemSheetControllerBase.fetchBatchBalance,
  // StockEntryItemFormController.fetchBatchWiseHistory and the Batch-Wise
  // Balance History report screen (the only caller that passes dates).
  // ---------------------------------------------------------------------------

  /// Fetch Batch-Wise Balance History rows for [itemCode].
  ///
  /// [batchNo] is optional — omit to fetch all in-stock batches for the item
  /// (used by BatchPickerSheet pre-fetch / fetchBatchWiseHistory).
  ///
  /// [fromDate] / [toDate] are `yyyy-MM-dd`; each defaults to today when null
  /// or blank. The report's opening balance is everything before [fromDate]
  /// and its balance is as of [toDate], so a today–today window gives the
  /// current balance. Same filter names on ERPNext v15 and v16.
  ///
  /// Both Map rows (key-based) and List rows (positional) are normalised to
  /// a consistent shape: {'batch_no': String, 'qty': double, ...} so that
  /// [ItemSheetControllerBase.fetchBatchBalance] can always read r['qty']
  /// regardless of the ERP response format.
  Future<List<Map<String, dynamic>>> getBatchWiseBalance({
    required String itemCode,
    String? batchNo,
    String? warehouse,
    String? fromDate,
    String? toDate,
  }) async {
    if (!_dioInitialised) await _initDio();

    final company = Get.find<StorageService>().getCompany();
    late final Response response;
    try {
      response = await _requestBatchWiseBalance(
        company: company,
        itemCode: itemCode,
        batchNo: batchNo,
        warehouse: warehouse,
        fromDate: fromDate,
        toDate: toDate,
      );
    } catch (_) {
      return [];
    }

    if (response.statusCode != 200) return [];

    try {
      final message = response.data['message'] as Map<String, dynamic>?;
      if (message == null) return [];
      final rawRows = message['result'] as List<dynamic>?;
      if (rawRows == null) return [];

      final firstRow = rawRows.firstWhere((r) => r != null, orElse: () => null);

      if (firstRow is Map) {
        // Item sheets and forms use 'qty', including on older report shapes.
        return rawRows.whereType<Map>().map((r) {
          final m = Map<String, dynamic>.from(r);
          m['qty'] ??= _toDouble(
            m['balance_qty'] ?? m['bal_qty'] ?? m['balance'],
          );
          return m;
        }).toList();
      }

      final rawColumns = message['columns'] as List<dynamic>?;
      if (rawColumns == null) return [];

      String fn(dynamic col) {
        if (col is Map) return (col['fieldname'] as String? ?? '').toLowerCase();
        final s = col.toString().toLowerCase();
        final lastDot = s.lastIndexOf('.');
        return lastDot >= 0
            ? s.substring(lastDot + 1).replaceAll('`', '')
            : s;
      }

      final cols      = rawColumns.map(fn).toList();
      final batchIdx  = cols.indexWhere((c) => c.contains('batch'));
      final balIdx    = cols.indexWhere((c) => c.contains('balance'));
      final whIdx     = cols.indexWhere((c) => c.contains('warehouse'));
      final expiryIdx = cols.indexWhere((c) => c.contains('expiry') || c.contains('expiration'));

      if (batchIdx == -1 || balIdx == -1) return [];

      return rawRows
          .whereType<List>()
          .where((r) => r.isNotEmpty)
          .map((r) {
            final row = <String, dynamic>{};
            if (batchIdx < r.length) row['batch_no']   = r[batchIdx]?.toString() ?? '';
            if (balIdx   < r.length) row['qty']        = _toDouble(r[balIdx]);
            if (whIdx >= 0 && whIdx < r.length) row['warehouse'] = r[whIdx]?.toString() ?? '';
            if (expiryIdx >= 0 && expiryIdx < r.length) row['expiry_date'] = r[expiryIdx]?.toString();
            return row;
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<BatchWiseBalanceResult> getBatchWiseBalanceReport({
    required String itemCode,
    String? batchNo,
    String? warehouse,
    String? fromDate,
    String? toDate,
  }) async {
    if (!_dioInitialised) await _initDio();
    final response = await _requestBatchWiseBalance(
      company: Get.find<StorageService>().getCompany(),
      itemCode: itemCode,
      batchNo: batchNo,
      warehouse: warehouse,
      fromDate: fromDate,
      toDate: toDate,
    );
    if (response.statusCode != 200 || response.data is! Map) {
      throw const FormatException('Batch-Wise Balance History response');
    }
    return parseBatchWiseBalanceReport(response.data['message']);
  }

  static BatchWiseBalanceResult parseBatchWiseBalanceReport(Object? message) {
    if (message is! Map || message['result'] is! List) {
      throw const FormatException('Batch-Wise Balance History results');
    }
    final rawColumns = message['columns'];
    final sourceColumns = decodeDeskColumns(rawColumns);
    final columns = rawColumns is List
        ? _batchReportColumns(rawColumns, sourceColumns)
        : null;
    final renamed = [
      if (columns != null)
        for (final (index, column) in columns.indexed)
          if (sourceColumns[index].fieldname != column.fieldname)
            (sourceColumns[index].fieldname, column.fieldname),
    ];
    final rows = <Map<String, dynamic>>[];
    const identities = ['item', 'item_name', 'warehouse', 'batch', 'batch_no'];
    final result = message['result'] as List;
    final hasAppendedTotal = _stockReportAddsTotal(message);
    for (final (index, raw) in result.indexed) {
      final row = decodeDeskRow(raw, sourceColumns);
      if (row == null || row.isEmpty) continue;
      for (final (sourceKey, key) in renamed) {
        if (row.containsKey(sourceKey)) {
          row.putIfAbsent(key, () => row[sourceKey]);
        }
      }
      if (row['_is_total'] == true || row['is_total_row'] == true) continue;
      final identity = [
        for (final key in identities)
          if (row[key]?.toString().trim() case final value? when value.isNotEmpty)
            value,
      ];
      final first = raw is List && raw.isNotEmpty
          ? raw.first
          : row['item'] ?? row['item_name'];
      final firstLabel = first?.toString().trim().toLowerCase();
      if ((firstLabel == 'total' ||
              firstLabel == 'grand total' ||
              hasAppendedTotal && raw is List && index == result.length - 1) &&
          (identity.isEmpty ||
              identity.every((value) => value == first?.toString().trim()))) {
        continue;
      }
      if (!row.containsKey('batch') && row.containsKey('batch_no')) {
        row['batch'] = row['batch_no'];
      }
      for (final alias in ['bal_qty', 'balance']) {
        if (row.containsKey(alias)) row.putIfAbsent('balance_qty', () => row[alias]);
      }
      rows.add(Map.unmodifiable(row));
    }
    return (columns: columns, rows: List.unmodifiable(rows));
  }

  static List<DeskColumn> _batchReportColumns(
    List rawColumns,
    List<DeskColumn> columns,
  ) {
    // Desk derives fieldnames from the translated legacy headers. The three
    // Link targets and remaining types identify the standard report layout.
    const standard = [
      ('item', 'Link', 'Item'),
      ('item_name', 'Data', ''),
      ('description', 'Data', ''),
      ('warehouse', 'Link', 'Warehouse'),
      ('batch', 'Link', 'Batch'),
      ('opening_qty', 'Float', ''),
      ('in_qty', 'Float', ''),
      ('out_qty', 'Float', ''),
      ('balance_qty', 'Float', ''),
      ('valuation_rate', 'Float', ''),
      ('balance_value', 'Currency', ''),
      ('uom', 'Data', ''),
    ];
    const aliases = {
      'item_code': 'item',
      'batch_no': 'batch',
      'bal_qty': 'balance_qty',
      'balance': 'balance_qty',
      'val_rate': 'valuation_rate',
      'bal_val': 'balance_value',
      'stock_uom': 'uom',
    };
    final known = {for (final (key, _, _) in standard) key};
    final sourceKeys = columns.map((column) => column.fieldname).toSet();
    final stableKeys = [
      for (final column in columns)
        if (aliases[column.fieldname] case final alias?
            when !sourceKeys.contains(alias))
          alias
        else
          column.fieldname,
    ];
    final standardLayout =
        columns.length == standard.length &&
        sourceKeys.length == columns.length &&
        columns.indexed.every((entry) {
          final (index, column) = entry;
          final (key, type, target) = standard[index];
          final raw = rawColumns[index];
          final legacy = raw is String
              ? raw.split(':').elementAtOrNull(1)?.split('/')
              : null;
          final fieldtype = raw is Map ? raw['fieldtype'] : legacy?.firstOrNull;
          final options = raw is Map ? raw['options'] : legacy?.elementAtOrNull(1);
          final stable = stableKeys[index];
          return column.fieldname.isNotEmpty &&
              (!known.contains(stable) || key == stable) &&
              (fieldtype == type ||
                  type == 'Data' && (fieldtype == null || fieldtype == '')) &&
              (target.isEmpty || options == target);
        });
    return List.unmodifiable([
      for (final (index, column) in columns.indexed)
        (
          fieldname: standardLayout ? standard[index].$1 : stableKeys[index],
          label: column.label,
        ),
    ]);
  }

  Future<Response> _requestBatchWiseBalance({
    required String company,
    required String itemCode,
    String? batchNo,
    String? warehouse,
    String? fromDate,
    String? toDate,
  }) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String dateOrToday(String? d) =>
        (d == null || d.trim().isEmpty) ? today : d.trim();

    final Map<String, dynamic> filters = {
      "company"   : company,
      "from_date" : dateOrToday(fromDate),
      "to_date"   : dateOrToday(toDate),
      "item_code" : itemCode,
    };

    if (batchNo   != null && batchNo.isNotEmpty)   filters["batch_no"]  = batchNo;
    if (warehouse != null && warehouse.isNotEmpty) filters["warehouse"] = warehouse;

    return _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'           : 'Batch-Wise Balance History',
          'filters'               : json.encode(filters),
          'ignore_prepared_report': 'true',
          'are_default_filters'   : 'false',
          '_'                     : DateTime.now().millisecondsSinceEpoch,
        },
    );
  }

  // ---------------------------------------------------------------------------
  // getItemVariantDetails
  // ---------------------------------------------------------------------------

  Future<ItemVariantDetailsResult> getItemVariantDetails({
    List<String> items = const [],
    List<String> itemGroups = const [],
    List<String> warehouses = const [],
  }) async {
    if (!_dioInitialised) await _initDio();

    return requestItemVariantDetails(
      items: items,
      itemGroups: itemGroups,
      warehouses: warehouses,
      request: (filters) async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/method/frappe.desk.query_report.run',
          queryParameters: {
            'report_name': 'Item Variant Details',
            'filters': json.encode(filters),
            'ignore_prepared_report': 'true',
            '_': DateTime.now().millisecondsSinceEpoch,
          },
        );
        final message = response.data?['message'];
        if (message is! Map<String, dynamic> ||
            message['columns'] is! List || message['result'] is! List) {
          throw const FormatException('The server returned an invalid report.');
        }
        return parseItemVariantDetailsResponse(message);
      },
    );
  }

  static Map<String, dynamic> itemVariantDetailsFilters({
    List<String> items = const [],
    List<String> itemGroups = const [],
    List<String> warehouses = const [],
  }) => {
    if (items.isNotEmpty) 'item': items.length == 1 ? items.single : items,
    if (itemGroups.isNotEmpty) 'item_group': itemGroups,
    if (warehouses.isNotEmpty) 'warehouse': warehouses,
  };

  static Future<ItemVariantDetailsResult> requestItemVariantDetails({
    required List<String> items,
    required List<String> itemGroups,
    required List<String> warehouses,
    required Future<ItemVariantDetailsResult> Function(Map<String, dynamic>)
        request,
  }) async {
    final filters = itemVariantDetailsFilters(
      items: items,
      itemGroups: itemGroups,
      warehouses: warehouses,
    );
    final hasExtraFilters = itemGroups.isNotEmpty || warehouses.isNotEmpty;
    final canSplit = items.length > 1 && itemGroups.isEmpty;
    const unsupportedFilters = FormatException(
      'This server cannot apply Item Groups or Warehouses in this report. '
      'Clear those filters and select Items.',
    );
    bool supportsFilters(ItemVariantDetailsResult result) {
      // The legacy report has neither of these Link columns. Its dynamic
      // attributes can have the same fieldnames but are Data columns.
      final links = {
        for (final column in result.columns)
          if (column['fieldtype'] == 'Link')
            (column['fieldname'], column['options']),
      };
      return links.containsAll({('item_group', 'Item Group'), ('stock_uom', 'UOM')});
    }

    try {
      final result = await request(filters);
      if (supportsFilters(result)) return result;
      if (hasExtraFilters) throw unsupportedFilters;
      if (!canSplit) return result;
    } on DioException catch (error) {
      final data = error.response?.data;
      final errorType = data is Map ? data['exc_type'] : null;
      // Frappe may hide tracebacks. Match the exception types raised by the
      // legacy document lookup, without retrying network or permission errors.
      final rejectedItem = switch (error.response?.statusCode) {
        404 => errorType == 'DoesNotExistError',
        417 => errorType == 'ValidationError',
        500 => {'TypeError', 'ValueError', 'AttributeError'}.contains(errorType),
        _ => false,
      };
      if (!rejectedItem) rethrow;
      if (hasExtraFilters && items.isEmpty) {
        throw const FormatException(
          'The server could not run this filter combination. '
          'Try selecting Items without Item Groups or Warehouses.',
        );
      }
      if (!canSplit) rethrow;
    }

    final columns = <Object?, Map<String, dynamic>>{};
    final rows = <Map<String, dynamic>>[];
    for (final item in items) {
      final result = await request({...filters, 'item': item});
      if (hasExtraFilters && !supportsFilters(result)) throw unsupportedFilters;
      for (final column in result.columns) {
        columns.putIfAbsent(column['fieldname'], () => column);
      }
      rows.addAll(result.rows);
    }
    return (columns: columns.values.toList(), rows: rows);
  }

  /// Exposed as a public static method so unit tests can exercise the parsing
  /// logic without a live HTTP connection or GetX service registration.
  static ItemVariantDetailsResult parseItemVariantDetailsResponse(Map<String, dynamic>? message) {
    const empty = (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    if (message == null) return empty;
    try {
      final rawCols = message['columns'] as List<dynamic>? ?? [];
      final rawRows = message['result']  as List<dynamic>? ?? [];
      final descriptors = decodeDeskColumns(rawCols);
      final columns = [
        for (final (index, raw) in rawCols.indexed)
          if (descriptors[index].fieldname.isNotEmpty)
            {
              if (raw is Map) ...Map<String, dynamic>.from(raw),
              'fieldname': descriptors[index].fieldname,
              'label': descriptors[index].label,
              if (raw is String && raw.split(':').length > 1) ...{
                'fieldtype': raw.split(':')[1].split('/').first,
                if (raw.split(':')[1].contains('/'))
                  'options': raw.split(':')[1].split('/').last,
              },
            },
      ];
      final addsTotal = _stockReportAddsTotal(message);
      final rows = [
        for (final (index, raw) in rawRows.indexed)
          if (!(addsTotal && raw is List && index == rawRows.length - 1))
            if (decodeDeskRow(raw, descriptors) case final row?
                when !_stockReportFlag(row['is_total_row']))
              row,
      ];
      return (columns: columns, rows: rows);
    } catch (_) {
      return empty;
    }
  }

  static ({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})
      parseStockBalanceResponse(Map<String, dynamic>? message) {
    final columnsValue = message?['columns'];
    final rawColumns = columnsValue is List ? columnsValue : const [];
    final columns = decodeDeskColumns(rawColumns);
    final rowsValue = message?['result'];
    final rawRows = rowsValue is List ? rowsValue : const [];
    final rows = <Map<String, dynamic>>[];
    final mapKeys = <Object?>{};
    var positional = false;
    for (final (index, raw) in rawRows.indexed) {
      final row = decodeDeskRow(raw, columns);
      if (row == null || row.isEmpty || _stockReportFlag(row['is_total_row'])) {
        continue;
      }
      // The first cell holds Frappe's translated caption, even when the
      // requested column order puts a detail identity in that position.
      if (raw is List &&
          index == rawRows.length - 1 &&
          !_stockReportFlag(message?['skip_total_row']) &&
          (_stockReportAddsTotal(message) || raw.firstOrNull == 'Total') &&
          ['warehouse', 'item_code', 'item', 'item_name', 'stock_uom'].every(
            (key) =>
                key == columns.firstOrNull?.fieldname ||
                row[key]?.toString().trim().isNotEmpty != true,
          )) {
        continue;
      }
      if (raw is List) {
        positional = true;
        row[stockBalancePositionalRowKey] = true;
      } else if (raw is Map) {
        mapKeys.addAll(raw.keys);
      }
      // The legacy string header Item yields the slug `item`.
      if (row['item_code'] == null && row.containsKey('item')) {
        row['item_code'] = row['item'];
      }
      rows.add(Map.unmodifiable(row));
    }
    final exactKeys = {for (final column in columns) column.fieldname};
    return (
      columns: List.unmodifiable([
        for (final (index, column) in columns.indexed)
          _stockBalanceColumn(rawColumns[index], column, exactKeys, mapKeys,
              positional),
      ]),
      rows: List.unmodifiable(rows),
    );
  }

  static bool _stockReportFlag(Object? flag) =>
      flag == true || flag == 1 || flag == '1';

  static bool _stockReportAddsTotal(Map? message) =>
      _stockReportFlag(message?['add_total_row']) &&
      !_stockReportFlag(message?['skip_total_row']);

  static Map<String, dynamic> _stockBalanceColumn(
    Object? raw,
    DeskColumn column,
    Set<String> exactKeys,
    Set<Object?> mapKeys,
    bool positional,
  ) {
    final legacy = column.fieldname.toLowerCase();
    final useLegacy = legacy != column.fieldname && !exactKeys.contains(legacy);
    final legacyType = raw is String ? raw.split(':').elementAtOrNull(1) : null;
    final typeParts = legacyType?.split('/');
    return Map.unmodifiable({
      if (raw is Map)
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
      if (typeParts?.firstOrNull case final type?) 'fieldtype': type,
      if (typeParts?.elementAtOrNull(1) case final options?) 'options': options,
      'fieldname': column.fieldname,
      'label': column.label,
      'legacy_fieldname': legacy,
      'legacy_fallback': useLegacy,
      'legacy_visible': legacy == column.fieldname || positional ||
          (useLegacy && mapKeys.contains(legacy)),
    });
  }

  /// Exposed as a public static method so unit tests can exercise the parsing
  /// logic without a live HTTP connection.
  static String? parseUploadFileResponse(Map<String, dynamic>? data) {
    if (data == null) return null;
    final message = data['message'];
    if (message is! Map) return null;
    final fileUrl = message['file_url'];
    return fileUrl is String ? fileUrl : null;
  }

  // ---------------------------------------------------------------------------
  // FILE UPLOAD
  // ---------------------------------------------------------------------------

  /// Uploads [filePath] to Frappe and links it to [fieldname] on
  /// [doctype]/[docname].
  ///
  /// Returns the relative file_url (e.g. "/files/image.jpg") on success.
  /// Throws [DioException] on HTTP error; throws [Exception] when the server
  /// response does not contain a file_url (malformed response).
  Future<String> uploadFile({
    required String filePath,
    required String doctype,
    required String docname,
    required String fieldname,
    bool isPrivate = false,
  }) async {
    if (!_dioInitialised) await _initDio();
    final formData = FormData.fromMap({
      'file'      : await MultipartFile.fromFile(filePath, filename: p.basename(filePath)),
      'doctype'   : doctype,
      'docname'   : docname,
      'fieldname' : fieldname,
      'is_private': isPrivate ? '1' : '0',
      'folder'    : 'Home/Attachments',
    });
    final response = await _dio.post('/api/method/upload_file', data: formData);
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Upload failed with status ${response.statusCode}',
      );
    }
    final fileUrl = parseUploadFileResponse(
      response.data as Map<String, dynamic>?,
    );
    if (fileUrl == null || fileUrl.isEmpty) {
      throw Exception('Server returned no file_url');
    }
    return fileUrl;
  }

  /// The bytes of the file at [url] — a site-relative file URL such as
  /// "/files/foo.jpg" (private files included, through the session cookie)
  /// or an absolute URL. Throws [DioException] on an HTTP or network error.
  Future<Uint8List> getFileBytes(String url) async {
    if (!_dioInitialised) await _initDio();
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) throw const FormatException('Empty file response');
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  // ---------------------------------------------------------------------------
  // getItemDetails — Item Variant Details tile helper
  // ---------------------------------------------------------------------------

  /// Reads names for the report's exact item codes with normal Item permissions.
  Future<Map<String, String>> getItemNames(
    List<String> itemCodes, {
    CancelToken? cancelToken,
  }) async {
    if (itemCodes.isEmpty) return {};
    if (!_dioInitialised) await _initDio();
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/method/frappe.client.get_list',
      data: {
        'doctype': 'Item',
        'fields': ['name', 'item_name'],
        'filters': [
          ['name', 'in', itemCodes],
        ],
        'limit_page_length': itemCodes.length,
      },
      cancelToken: cancelToken,
    );
    return {
      for (final row in response.data!['message'] as List)
        if (row['item_name'] is String)
          row['name'] as String: row['item_name'] as String,
    };
  }

  /// Batch-fetches item_name, item_group, and image for [itemCodes].
  /// Returns a map of item code → {item_name, item_group, image?}.
  /// The image value is null when the field is unset.
  Future<Map<String, Map<String, dynamic>>> getItemDetails(
      List<String> itemCodes) async {
    if (itemCodes.isEmpty) return {};
    try {
      final rows = await getList(
        null,
        doctype: 'Item',
        fields:  ['name', 'item_name', 'item_group', 'image'],
        filters: {'name': ['in', itemCodes]},
        limit:   itemCodes.length + 1,
        orderBy: 'name asc',
      );
      return {
        for (final r in rows)
          r['name'].toString(): {
            'item_name':  r['item_name']?.toString()  ?? '',
            'item_group': r['item_group']?.toString() ?? '',
            'image': (r['image']?.toString().isNotEmpty ?? false)
                ? r['image'].toString()
                : null,
          },
      };
    } catch (_) {
      return {};
    }
  }

  /// Batch-fetches the `image` field for [itemCodes].
  ///
  /// Returns a map of item code → image path (relative frappe file URL, e.g.
  /// "/files/foo.jpg") for items that have one; items without an image are
  /// omitted. Used to surface item thumbnails on the Stock Balance tiles, whose
  /// report response does not include the image (mirrors the customer_code
  /// enrichment).
  Future<Map<String, String>> getItemImages(List<String> itemCodes) async {
    if (itemCodes.isEmpty) return {};
    try {
      final rows = await getList(
        null,
        doctype: 'Item',
        fields:  ['name', 'image'],
        filters: {'name': ['in', itemCodes]},
        limit:   itemCodes.length + 1,
        orderBy: 'name asc',
      );
      return {
        for (final r in rows)
          if (r['image']?.toString().trim().isNotEmpty ?? false)
            r['name'].toString(): r['image'].toString(),
      };
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // getStockBalanceWithDimension
  //
  // Used by:
  //   • DeliveryNoteItemFormController.preloadRackStockMap
  //   • StockEntryItemFormController.validateRack fallback
  //   • ItemSheetControllerBase.fetchRackBalance
  //   • RackPickerController.load  (Browse Rack sheet)
  // ---------------------------------------------------------------------------

  /// Fetch per-rack stock balance rows for [itemCode], optionally scoped to
  /// [warehouse] or [warehouses] and filtered by [batchNo]. A non-empty
  /// [warehouses] selection takes precedence over [warehouse].
  ///
  /// Always sends `show_variant_attributes=1` and
  /// `show_dimension_wise_stock=1` so the Stock Balance report expands
  /// rows by rack dimension.
  ///
  /// Both Map rows (key-based) and List rows (positional) are handled.
  /// Each row supplies `rack` and `qty`, plus `warehouse` when present.
  Future<List<Map<String, dynamic>>> getStockBalanceWithDimension({
    required String itemCode,
    String? warehouse,
    List<String> warehouses = const [],
    String? batchNo,
  }) async => (
    await _queryStockBalanceDimension(
      itemCode: itemCode,
      warehouse: warehouse,
      warehouses: warehouses,
      batchNo: batchNo,
      reportErrors: false,
    )
  ).rows;

  /// The Item Variant Details check distinguishes a rejected lookup from empty
  /// stock and uses the Stock Balance caption from the same report response.
  Future<RackStockBalanceResult> getStockBalanceDimensionResult({
    required String itemCode,
    List<String> warehouses = const [],
  }) => _queryStockBalanceDimension(
    itemCode: itemCode,
    warehouses: warehouses,
    reportErrors: true,
  );

  Future<RackStockBalanceResult> _queryStockBalanceDimension({
    required String itemCode,
    required List<String> warehouses,
    required bool reportErrors,
    String? warehouse,
    String? batchNo,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final company = storage.getCompany();
    final today   = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final warehouseFilter = _stockBalanceWarehouseFilter(warehouses) ??
        (warehouse?.isNotEmpty == true ? warehouse : null);

    final filters = <String, dynamic>{
      'company'                  : company,
      'from_date'                : today,
      'to_date'                  : today,
      'item_code'                : await stockBalanceItemCodeFilter(itemCode),
      'show_variant_attributes'  : 1,
      'show_dimension_wise_stock': 1,
      if (warehouseFilter != null) 'warehouse': warehouseFilter,
    };
    if (batchNo   != null && batchNo.isNotEmpty)   filters['batch_no']  = batchNo;

    late final Response response;
    try {
      response = await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'           : 'Stock Balance',
          'filters'               : json.encode(filters),
          'ignore_prepared_report': 'true',
          'are_default_filters'   : 'false',
          '_'                     : DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (_) {
      if (reportErrors) rethrow;
      return (columns: const <DeskColumn>[], rows: const <Map<String, dynamic>>[]);
    }

    if (reportErrors) {
      final message = response.data is Map ? response.data['message'] : null;
      if (response.statusCode != 200 || message is! Map || message['result'] is! List) {
        throw const FormatException('The server returned an invalid stock report.');
      }
      return parseRackStockBalanceResult(message);
    }
    if (response.statusCode != 200) {
      return (columns: const <DeskColumn>[], rows: const <Map<String, dynamic>>[]);
    }
    return (
      columns: const <DeskColumn>[],
      rows: _parseLegacyStockBalanceDimension(response.data),
    );
  }

  static RackStockBalanceResult parseRackStockBalanceResult(Map message) {
    final columns = decodeDeskColumns(message['columns']);
    final rawRows = message['result'];
    if (rawRows is! List) {
      throw const FormatException('The server returned an invalid stock report.');
    }
    final rows = <Map<String, dynamic>>[];
    for (final raw in rawRows) {
      final row = decodeDeskRow(raw, columns);
      if (row == null) continue;
      final rack = row['rack']?.toString().trim() ?? '';
      if (rack.isEmpty) continue;
      final qty = _stockReportNumber(
        row['bal_qty'] ?? row['balance_qty'] ?? row['qty'],
      );
      if (qty == null) {
        throw const FormatException(
          'The server returned a rack without a balance quantity.',
        );
      }
      rows.add({
        'rack': rack,
        'qty': qty,
        if (row['warehouse'] is String) 'warehouse': row['warehouse'],
      });
    }
    return (columns: columns, rows: rows);
  }

  static List<Map<String, dynamic>> _parseLegacyStockBalanceDimension(
    dynamic response,
  ) {
    try {
      final message = response['message'] as Map<String, dynamic>?;
      if (message == null) return [];
      final rawRows = message['result'] as List<dynamic>?;
      if (rawRows == null || rawRows.isEmpty) return [];

      final firstDataRow = rawRows.firstWhere((r) => r != null, orElse: () => null);

      // ── Fix 2a: Map rows (key-based) ──────────────────────────────────────
      // Accept both 'rack' key spellings for resilience.
      // Balance field is 'bal_qty' from Stock Balance report; fall back to
      // 'qty' / 'balance_qty' for any variant report configurations.
      if (firstDataRow is Map) {
        return rawRows
            .whereType<Map>()
            .map((r) {
              final rack = (r['rack'] ?? '').toString().trim();
              final qty  = _toDouble(r['bal_qty'] ?? r['qty'] ?? r['balance_qty']);
              return <String, dynamic>{
                'rack': rack,
                'qty': qty,
                if (r['warehouse'] is String) 'warehouse': r['warehouse'],
              };
            })
            .where((r) => (r['rack'] as String).isNotEmpty)
            .toList();
      }

      // ── Fix 2b: List rows (positional) ────────────────────────────────────
      // The previous implementation discarded all List rows via
      // whereType<Map>() with no fallback, silently returning [] when
      // ERP sends positional arrays.  Resolve column indices and map
      // to the same normalised shape as the Map branch above.
      final rawColumns = message['columns'] as List<dynamic>?;
      if (rawColumns == null) return [];

      String fn(dynamic col) {
        if (col is Map) return (col['fieldname'] as String? ?? '').toLowerCase();
        final s = col.toString().toLowerCase();
        final lastDot = s.lastIndexOf('.');
        return lastDot >= 0
            ? s.substring(lastDot + 1).replaceAll('`', '')
            : s;
      }

      final cols    = rawColumns.map(fn).toList();
      final rackIdx = cols.indexWhere((c) => c == 'rack');
      final warehouseIdx = cols.indexOf('warehouse');

      // Prefer exact 'bal_qty' column; fall back to any column containing
      // 'balance' or the generic 'qty' column.
      int balIdx = cols.indexWhere((c) => c == 'bal_qty');
      if (balIdx == -1) {
        balIdx = cols.indexWhere((c) => c.contains('balance') || c == 'qty');
      }

      if (rackIdx == -1 || balIdx == -1) return [];

      return rawRows
          .whereType<List>()
          .where((r) => r.length > rackIdx && r.length > balIdx)
          .map((r) {
            final rack = r[rackIdx]?.toString().trim() ?? '';
            final qty  = _toDouble(r[balIdx]);
            return <String, dynamic>{
              'rack': rack,
              'qty': qty,
              if (warehouseIdx >= 0 && warehouseIdx < r.length &&
                  r[warehouseIdx] is String)
                'warehouse': r[warehouseIdx],
            };
          })
          .where((r) => (r['rack'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch all available batches for [itemCode] in [warehouse] from the
  /// Batch-Wise Balance History report, returning only rows where balance > 0.
  Future<List<BatchWiseBalanceRow>> fetchBatchesForItem(
    String itemCode, {
    String? warehouse,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final company = storage.getCompany();
    final today   = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final filters = <String, dynamic>{
      'company'   : company,
      'from_date' : today,
      'to_date'   : today,
      'item_code' : itemCode,
    };
    if (warehouse != null && warehouse.isNotEmpty) {
      filters['warehouse'] = warehouse;
    }

    late final Response response;
    try {
      response = await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'           : 'Batch-Wise Balance History',
          'filters'               : json.encode(filters),
          'ignore_prepared_report': 'true',
          'are_default_filters'   : 'false',
          '_'                     : DateTime.now().millisecondsSinceEpoch,
        },
      );
    } on DioException {
      return [];
    } catch (_) {
      return [];
    }

    if (response.statusCode != 200) return [];

    try {
      final message = response.data['message'] as Map<String, dynamic>?;
      if (message == null) return [];

      final rawRows = message['result'] as List<dynamic>?;
      if (rawRows == null || rawRows.isEmpty) return [];

      final rows = <BatchWiseBalanceRow>[];

      final firstDataRow = rawRows.firstWhere(
        (r) => r != null,
        orElse: () => null,
      );

      if (firstDataRow is Map) {
        for (final row in rawRows) {
          if (row is! Map) continue;

          final batchNo    = (row['batch'] ?? row['batch_no'] ?? row['batch_id'] ?? '').toString().trim();
          final balanceQty = _toDouble(row['balance_qty'] ?? row['bal_qty'] ?? row['balance']);

          if (batchNo.isEmpty || balanceQty <= 0) continue;

          final warehouseVal = (row['warehouse'] ?? '').toString().trim();

          DateTime? expiryDate;
          final expiryRaw = row['expiry_date'] ?? row['expiration_date'];
          if (expiryRaw != null && expiryRaw.toString().isNotEmpty) {
            expiryDate = DateTime.tryParse(expiryRaw.toString());
          }

          final packagingQty = _toDouble(
            row['custom_packaging_qty'] ?? row['packaging_qty'],
          );

          rows.add(BatchWiseBalanceRow(
            batchNo      : batchNo,
            balanceQty   : balanceQty,
            warehouse    : warehouseVal,
            expiryDate   : expiryDate,
            packagingQty : packagingQty,
          ));
        }
      } else {
        final rawColumns = message['columns'] as List<dynamic>?;
        if (rawColumns == null) return [];

        String innerFn(dynamic col) {
          if (col is Map) return (col['fieldname'] as String? ?? '').toLowerCase();
          final s = col.toString().toLowerCase();
          final lastDot = s.lastIndexOf('.');
          return lastDot >= 0
              ? s.substring(lastDot + 1).replaceAll('`', '')
              : s;
        }

        final cols         = rawColumns.map(innerFn).toList();
        final batchIdx     = cols.indexWhere((c) => c.contains('batch'));
        final expiryIdx    = cols.indexWhere((c) => c.contains('expiry') || c.contains('expiration'));
        final whIdx        = cols.indexWhere((c) => c.contains('warehouse'));
        final balIdx       = cols.indexWhere((c) => c.contains('balance'));
        final packagingIdx = cols.indexWhere((c) => c.contains('packaging'));

        if (batchIdx == -1 || balIdx == -1) return [];

        for (final row in rawRows) {
          if (row is! List || row.isEmpty) continue;
          final parsed = BatchWiseBalanceRow.fromReportRow(
            row,
            batchIdx    : batchIdx,
            balanceIdx  : balIdx,
            warehouseIdx: whIdx >= 0 ? whIdx : 0,
            expiryIdx   : expiryIdx >= 0 ? expiryIdx : 0,
            packagingIdx: packagingIdx,
          );
          if (parsed.batchNo.isNotEmpty && parsed.balanceQty > 0) {
            rows.add(parsed);
          }
        }
      }

      rows.sort((a, b) => b.balanceQty.compareTo(a.balanceQty));
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// Coerce a dynamic value to [double]. Returns 0.0 for null / unparseable.
  static double _toDouble(dynamic v) => switch (v) {
    final num n    => n.toDouble(),
    final String s => double.tryParse(s) ?? 0.0,
    _              => 0.0,
  };

  // ---------------------------------------------------------------------------
  // BOM SEARCH
  // ---------------------------------------------------------------------------

  Future<Response> searchBom({
    String? item,
    String? bom,
    String? item1,
    String? item2,
    String? item3,
    String? item4,
    String? item5,
  }) async {
    if (!_dioInitialised) await _initDio();

    final filters = <String, dynamic>{};
    if (item?.isNotEmpty  == true) filters['item']   = item;
    if (bom?.isNotEmpty   == true) filters['bom']    = bom;
    if (item1?.isNotEmpty == true) filters['item1']  = item1;
    if (item2?.isNotEmpty == true) filters['item2']  = item2;
    if (item3?.isNotEmpty == true) filters['item3']  = item3;
    if (item4?.isNotEmpty == true) filters['item4']  = item4;
    if (item5?.isNotEmpty == true) filters['item5']  = item5;

    return await _dio.get(
      '/api/method/frappe.desk.query_report.run',
      queryParameters: {
        'report_name'          : 'BOM Search',
        'filters'              : json.encode(filters),
        'ignore_prepared_report': 'true',
        'are_default_filters'  : 'false',
        '_'                    : DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SUPPLIERS BY ITEM
  // ---------------------------------------------------------------------------

  /// Runs the read-only Suppliers by Item script report.
  Future<List<SuppliersByItemNode>> runSuppliersByItem(
    SuppliersByItemFilters filters,
  ) async => (await runSuppliersByItemReport(filters)).nodes;

  Future<SuppliersByItemReport> runSuppliersByItemReport(
    SuppliersByItemFilters filters,
  ) async {
    if (!_dioInitialised) await _initDio();

    late final Response<dynamic> response;
    try {
      response = await _dio.post(
        '/api/method/frappe.desk.query_report.run',
        data: {
          'report_name': 'Suppliers by Item',
          'filters': json.encode(filters.toJson()),
          'ignore_prepared_report': 'true',
          'are_default_filters': 'false',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 403 || _isSuppliersByItemPermissionError(e.response?.data)) {
        throw _suppliersByItemPermissionDenied;
      }
      throw SuppliersByItemReportException(
        status == null
            ? 'Could not reach the report server. Try again.'
            : 'The server could not run Suppliers by Item (HTTP $status).',
      );
    }

    final data = response.data;
    if (_isSuppliersByItemPermissionError(data)) {
      throw _suppliersByItemPermissionDenied;
    }
    final message = data is Map ? data['message'] : null;
    if (message is! Map) {
      throw const SuppliersByItemReportException(
        'The server returned an invalid Suppliers by Item response.',
      );
    }
    return SuppliersByItemReport.fromMessage(message);
  }

  static const _suppliersByItemPermissionDenied =
      SuppliersByItemReportException(
        SuppliersByItemReportException.denied,
        permissionDenied: true,
      );

  static bool _isSuppliersByItemPermissionError(Object? data) =>
      data is Map &&
      (data['exc_type'] == 'PermissionError' ||
          (data['exception']?.toString().contains('PermissionError') ?? false));

  // ---------------------------------------------------------------------------
  // STOCK AGEING - CUSTOM
  // ---------------------------------------------------------------------------

  /// Name of the Frappe Custom Report (a saved view over core Stock Ageing).
  static const kStockAgeingReport = 'Stock Ageing - Custom';

  /// Builds the `filters` payload for a user-filtered Stock Ageing run.
  /// Mirrors the desk report (`stock_ageing.js`): `company`, `to_date` and
  /// `range` are mandatory server-side; blank optionals are omitted and the
  /// Check filter is sent as `1` only when on.
  static Map<String, dynamic> buildStockAgeingFilters({
    required String company,
    required String toDate,
    required String range,
    String? warehouseType,
    String? warehouse,
    String? itemCode,
    String? brand,
    bool showWarehouseWiseStock = false,
  }) {
    final f = <String, dynamic>{
      'company': company,
      'to_date': toDate,
      'range': range,
    };
    void put(String key, String? v) {
      if (v != null && v.trim().isNotEmpty) f[key] = v.trim();
    }

    put('warehouse_type', warehouseType);
    put('warehouse', warehouse);
    put('item_code', itemCode);
    put('brand', brand);
    if (showWarehouseWiseStock) f['show_warehouse_wise_stock'] = 1;
    return f;
  }

  /// Query parameters for `query_report.run` (without the cache-buster).
  ///
  /// [filters] null → a default run: empty filters and **no**
  /// `are_default_filters`, so the server applies the report's saved filters
  /// (and echoes them back as `message.custom_filters`), exactly as the Desk
  /// does on first load. Non-null → the caller's filters with
  /// `are_default_filters=false`, as the Desk does once a filter is changed.
  static Map<String, dynamic> stockAgeingQuery({Map<String, dynamic>? filters}) {
    return {
      'report_name': kStockAgeingReport,
      'filters': json.encode(filters ?? const <String, dynamic>{}),
      'ignore_prepared_report': 'true',
      if (filters != null) 'are_default_filters': 'false',
    };
  }

  /// Runs "Stock Ageing - Custom". Returns the raw [Response]; the caller
  /// parses `message.columns`, `message.result` and `message.custom_filters`.
  /// The default run takes ~20 s on a full warehouse group, hence the longer
  /// receive timeout.
  Future<Response> runStockAgeingCustom({Map<String, dynamic>? filters}) async {
    if (!_dioInitialised) await _initDio();

    return await _dio.get(
      '/api/method/frappe.desk.query_report.run',
      queryParameters: {
        ...stockAgeingQuery(filters: filters),
        '_': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
  }

  // ---------------------------------------------------------------------------
  // BOM STOCK WITH CUSTOMER CODE
  // ---------------------------------------------------------------------------

  /// Builds the `frappe.desk.query_report.run` filter map for the
  /// "BOM Stock with Customer Code" report. Empty/false filters are omitted so
  /// the report applies its own defaults. Checkboxes are encoded as `1` when on.
  static Map<String, dynamic> buildBomStockFilters({
    String? customer,
    List<String> customerCodes = const [],
    List<String> warehouses = const [],
    String? posUpload,
    bool showExplodedView = false,
    bool hideOutOfStock = false,
  }) {
    final f = <String, dynamic>{};
    if (customer != null && customer.trim().isNotEmpty) {
      f['customer'] = customer.trim();
    }
    if (customerCodes.isNotEmpty) f['customer_code'] = customerCodes;
    if (warehouses.isNotEmpty) f['warehouse'] = warehouses;
    if (posUpload != null && posUpload.trim().isNotEmpty) {
      f['pos_upload'] = posUpload.trim();
    }
    if (showExplodedView) f['show_exploded_view'] = 1;
    if (hideOutOfStock) f['hide_out_of_stock'] = 1;
    return f;
  }

  /// Runs the "BOM Stock with Customer Code" scripted report.
  ///
  /// Returns the raw [Response] so the controller can parse
  /// `message.result` (a List of row dicts; the last row is the appended
  /// `add_total_row` total).
  Future<Response> runBomStockWithCustomerCode({
    String? customer,
    List<String> customerCodes = const [],
    List<String> warehouses = const [],
    String? posUpload,
    bool showExplodedView = false,
    bool hideOutOfStock = false,
  }) async {
    if (!_dioInitialised) await _initDio();

    final filters = buildBomStockFilters(
      customer: customer,
      customerCodes: customerCodes,
      warehouses: warehouses,
      posUpload: posUpload,
      showExplodedView: showExplodedView,
      hideOutOfStock: hideOutOfStock,
    );

    return await _dio.get(
      '/api/method/frappe.desk.query_report.run',
      queryParameters: {
        'report_name'           : 'BOM Stock with Customer Code',
        'filters'               : json.encode(filters),
        'ignore_prepared_report': 'true',
        'are_default_filters'   : 'false',
        '_'                     : DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Parses the distinct, non-empty `ref_code` values out of a
  /// `GET /api/resource/POS Upload/{name}` response body (`data.items[]`).
  static List<String> parsePosUploadRefCodes(dynamic docData) {
    if (docData is! Map) return [];
    final doc = docData['data'];
    if (doc is! Map) return [];
    final items = doc['items'];
    if (items is! List) return [];
    final codes = <String>[];
    for (final it in items) {
      if (it is! Map) continue;
      final code = (it['ref_code'] ?? '').toString().trim();
      if (code.isNotEmpty && !codes.contains(code)) codes.add(code);
    }
    return codes;
  }

  /// Returns the distinct customer ref-codes contained in [posUpload], read
  /// from the POS Upload document's `items` child table. Empty on any failure.
  Future<List<String>> getPosUploadRefCodes(String posUpload) async {
    if (posUpload.isEmpty) return [];
    try {
      final resp = await getPosUpload(posUpload);
      if (resp.statusCode == 200) return parsePosUploadRefCodes(resp.data);
    } catch (_) {
      // Picker convenience only — never block the report on this.
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // POS AND DELIVERY NOTE ITEM RATE
  // ---------------------------------------------------------------------------

  /// Builds the `frappe.desk.query_report.run` filter map for the
  /// "POS and Delivery Note Item Rate" report. Empty filters are omitted so
  /// the report applies its own defaults. Checkboxes are encoded as `1` when on.
  static Map<String, dynamic> buildPosDnItemRateFilters({
    List<String> posUploads = const [],
    String? fromDate,
    String? toDate,
    List<String> customers = const [],
    List<String> customerGroups = const [],
    List<String> itemGroups = const [],
    bool showMapped = false,
    bool onlyCoded = false,
  }) {
    final f = <String, dynamic>{};
    if (posUploads.isNotEmpty) f['pos_upload'] = posUploads;
    if (fromDate != null && fromDate.trim().isNotEmpty) {
      f['from_date'] = fromDate.trim();
    }
    if (toDate != null && toDate.trim().isNotEmpty) {
      f['to_date'] = toDate.trim();
    }
    if (customers.isNotEmpty) f['customer'] = customers;
    if (customerGroups.isNotEmpty) f['customer_group'] = customerGroups;
    if (itemGroups.isNotEmpty) f['item_group'] = itemGroups;
    if (showMapped) f['show_mapped'] = 1;
    if (onlyCoded) f['only_coded'] = 1;
    return f;
  }

  /// Runs the "POS and Delivery Note Item Rate" scripted report.
  ///
  /// Returns the raw [Response] so the controller can parse `message.result`
  /// (one row per upload line × mapped item, each carrying a server-computed
  /// `status`). Read-only; the report never writes.
  Future<Response> runPosDnItemRateReport({
    List<String> posUploads = const [],
    String? fromDate,
    String? toDate,
    List<String> customers = const [],
    List<String> customerGroups = const [],
    List<String> itemGroups = const [],
    bool showMapped = false,
    bool onlyCoded = false,
  }) async {
    if (!_dioInitialised) await _initDio();

    final filters = buildPosDnItemRateFilters(
      posUploads: posUploads,
      fromDate: fromDate,
      toDate: toDate,
      customers: customers,
      customerGroups: customerGroups,
      itemGroups: itemGroups,
      showMapped: showMapped,
      onlyCoded: onlyCoded,
    );

    return await _dio.get(
      '/api/method/frappe.desk.query_report.run',
      queryParameters: {
        'report_name'           : 'POS and Delivery Note Item Rate',
        'filters'               : json.encode(filters),
        'ignore_prepared_report': 'true',
        'are_default_filters'   : 'false',
        '_'                     : DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Searches a doctype's `name` field (`like %query%`) and returns the
  /// matching names, sorted ascending. Used to drive the Customer / POS Upload
  /// pickers without prefetching the whole table. [filters] adds extra
  /// exact-match constraints (e.g. `{'selling': 1, 'enabled': 1}` for a
  /// Price List picker), merged with the name-like filter; omit it to keep
  /// existing callers' behaviour unchanged.
  /// Link pickers must only offer records that are still active. Frappe has no
  /// uniform flag: Item/Warehouse/Batch carry `disabled`, UOM/Price List/User
  /// carry `enabled`, others (Item Group, Warehouse Type) have neither. Read
  /// the DocType meta once per doctype and derive the filter from whichever
  /// field exists; `{}` when neither does or the meta cannot be fetched
  /// (fail-open: a picker that lists disabled rows beats one that lists none).
  final Map<String, Map<String, dynamic>> _activeFilterCache = {};

  Future<Map<String, dynamic>> activeRecordFilter(String doctype) async {
    final cached = _activeFilterCache[doctype];
    if (cached != null) return cached;
    Map<String, dynamic> filter = const {};
    try {
      final response = await getDocTypeMeta(doctype);
      filter = activeFilterFromMeta(response.data, doctype);
    } catch (e) {
      debugPrint('activeRecordFilter: meta fetch failed for $doctype: $e');
      return filter; // don't cache a transient failure
    }
    return _activeFilterCache[doctype] = filter;
  }

  /// Pure: `{'disabled': 0}` if the meta has a `disabled` field, else
  /// `{'enabled': 1}` if it has `enabled`, else `{}`. Accepts the raw
  /// `getdoctype` response (any shape `extractDocTypeMeta` tolerates).
  static Map<String, dynamic> activeFilterFromMeta(
      dynamic data, String doctype) {
    final meta = GlobalSearchService.extractDocTypeMeta(data, doctype);
    final fields = meta?['fields'];
    if (fields is! List) return const {};
    final names = fields
        .whereType<Map>()
        .map((f) => f['fieldname']?.toString())
        .toSet();
    if (names.contains('disabled')) return const {'disabled': 0};
    if (names.contains('enabled')) return const {'enabled': 1};
    return const {};
  }

  Future<List<String>> searchLinkOptions(
    String doctype, {
    String query = '',
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    final rows = await getList(
      null,
      doctype: doctype,
      fields: ['name'],
      filters: {
        ...await activeRecordFilter(doctype),
        ...?filters, // an explicit caller filter on the same key wins
        if (query.trim().isNotEmpty) 'name': ['like', '%${query.trim()}%'],
      },
      limit: limit,
      orderBy: 'name asc',
    );
    return rows
        .map((r) => (r['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  /// Like [searchLinkOptions], but for a DocType whose `name` is an opaque ID:
  /// also reads [titleField] (Employee → `employee_name`), matches [query]
  /// against the ID **or** the title, and orders by title.
  Future<List<LinkOption>> searchLinkOptionsWithTitle(
    String doctype, {
    required String titleField,
    String query = '',
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    final q = query.trim();
    final response = await getDocumentList(
      doctype,
      fields: ['name', titleField],
      filters: {
        ...await activeRecordFilter(doctype),
        ...?filters,
      },
      orFilters: q.isEmpty
          ? null
          : {
              'name': ['like', '%$q%'],
              titleField: ['like', '%$q%'],
            },
      limit: limit,
      orderBy: '$titleField asc',
    );
    final data = response.data is Map ? response.data['data'] : null;
    return parseLinkOptions(data, titleField);
  }

  /// All Warehouse names (the warehouse list is small enough to prefetch and
  /// filter client-side in [WarehousePickerSheet]).
  Future<List<String>> getWarehouseNames() =>
      searchLinkOptions('Warehouse', limit: 0);

  // ---------------------------------------------------------------------------
  // JOB CARD SUMMARY
  // ---------------------------------------------------------------------------

  /// Runs the ERP "Job Card Summary" scripted report.
  ///
  /// Filters match the ERP desktop defaults:
  ///   company        — read from StorageService (required)
  ///   fiscal_year    — e.g. "2026"
  ///   from_date      — yyyy-MM-dd
  ///   to_date        — yyyy-MM-dd
  ///   work_order     — optional single value (empty list → no filter)
  ///   production_item — optional item code (empty list → no filter)
  ///
  /// Returns the raw [Response] so the controller can parse
  /// `message.result` (`List<dynamic>`) and `message.columns`.
  Future<Response> getJobCardSummary({
    required String fromDate,
    required String toDate,
    String? workOrder,
    String? productionItem,
    String? workstation,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage     = Get.find<StorageService>();
    final company     = storage.getCompany();
    final fiscalYear  = fromDate.substring(0, 4);   // e.g. "2026"

    final filters = <String, dynamic>{
      'company'         : company,
      'fiscal_year'     : fiscalYear,
      'from_date'       : fromDate,
      'to_date'         : toDate,
      'work_order'      : workOrder?.isNotEmpty == true ? workOrder : [],
      'production_item' : productionItem?.isNotEmpty == true ? productionItem : [],
      'workstation'     : workstation?.isNotEmpty == true ? workstation : [],
    };

    return await _dio.get(
      '/api/method/frappe.desk.query_report.run',
      queryParameters: {
        'report_name'           : 'Job Card Summary',
        'filters'               : json.encode(filters),
        'ignore_prepared_report': 'false',
        'are_default_filters'   : 'true',
        '_'                     : DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Fetches per-rack available quantity for [itemCode] + [batchNo] within
  /// [warehouse] from the Stock Ledger report.
  Future<Map<String, double>> getRackBatchStock({
    required String itemCode,
    required String batchNo,
    required String warehouse,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage  = Get.find<StorageService>();
    final company  = storage.getCompany();
    final today    = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final filters = <String, dynamic>{
      'company'  : company,
      'item_code': await stockBalanceItemCodeFilter(itemCode),
      'batch_no' : batchNo,
      'warehouse': warehouse,
      'from_date': '2000-01-01',
      'to_date'  : today,
    };

    late final Response response;
    try {
      response = await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'          : 'Stock Ledger',
          'filters'              : json.encode(filters),
          'ignore_prepared_report': 'true',
          'are_default_filters'  : 'false',
          '_'                    : DateTime.now().millisecondsSinceEpoch,
        },
      );
    } on DioException {
      return {};
    } catch (_) {
      return {};
    }

    if (response.statusCode != 200) return {};

    try {
      final message = response.data['message'] as Map<String, dynamic>?;
      if (message == null) return {};

      final rawColumns = message['columns'] as List<dynamic>?;
      final rawRows    = message['result']  as List<dynamic>?;
      if (rawColumns == null || rawRows == null || rawRows.isEmpty) return {};

      String fieldname(dynamic col) {
        if (col is Map) return (col['fieldname'] as String? ?? '').toLowerCase();
        return col.toString().toLowerCase();
      }

      final colNames = rawColumns.map(fieldname).toList();
      final rackIdx  = colNames.indexOf('rack');
      final qtyIdx   = colNames.indexOf('qty_after_transaction');

      if (rackIdx == -1 || qtyIdx == -1) return {};

      final result = <String, double>{};
      for (final row in rawRows) {
        if (row is! List || row.length <= rackIdx || row.length <= qtyIdx) {
          continue;
        }
        final rack = row[rackIdx]?.toString().trim() ?? '';
        if (rack.isEmpty) continue;

        final qty = switch (row[qtyIdx]) {
          final num n   => n.toDouble(),
          final String s => double.tryParse(s) ?? 0.0,
          _              => 0.0,
        };

        result[rack] = qty;
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  /// Legacy list projection of the ledger for callers with fail-open handling.
  Future<List<Map<String, dynamic>>> getStockLedgerEntries({
    required String itemCode,
    required String warehouse,
    required String fromDate,
    required String toDate,
  }) async {
    try {
      final result = await getStockLedgerReport(
        itemCode: itemCode,
        warehouse: warehouse,
        fromDate: fromDate,
        toDate: toDate,
      );
      return _legacyStockLedgerRows(result.rows);
    } catch (_) {
      return [];
    }
  }

  /// Stock Ledger's movement records and returned headers. Network and
  /// malformed replies propagate so the ledger can distinguish them from empty.
  Future<StockLedgerReportResult> getStockLedgerReport({
    required String itemCode,
    required String warehouse,
    required String fromDate,
    required String toDate,
  }) async {
    if (!_dioInitialised) await _initDio();
    final storage = Get.find<StorageService>();
    final filters = <String, dynamic>{
      'company'  : storage.getCompany(),
      'item_code': await stockBalanceItemCodeFilter(itemCode),
      if (warehouse.isNotEmpty) 'warehouse': warehouse,
      'from_date': fromDate,
      'to_date'  : toDate,
    };
    final response = await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'           : 'Stock Ledger',
          'filters'               : json.encode(filters),
          'ignore_prepared_report': 'true',
          'are_default_filters'   : 'false',
          '_'                     : DateTime.now().millisecondsSinceEpoch,
        },
    );
    if (response.statusCode != 200) {
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 0,
        requestOptions: response.requestOptions,
        response: response,
      );
    }
    final data = response.data;
    final message = data is Map ? data['message'] : null;
    if (message is! Map || message['result'] is! List) {
      throw const FormatException('Stock Ledger response has no result list');
    }
    return parseStockLedgerReport(message);
  }

  static List<Map<String, dynamic>> parseStockLedgerEntries(
    Map<String, dynamic>? message,
  ) => _legacyStockLedgerRows(parseStockLedgerReport(message).rows);

  static List<Map<String, dynamic>> _legacyStockLedgerRows(
    List<Map<String, dynamic>> rows,
  ) => [
    for (final row in rows)
      {
        'date': row['date'],
        'voucher_type': row['voucher_type'],
        'voucher_no': row['voucher_no'],
        'qty': row['qty'] ?? 0.0,
        'balance': row['balance'] ?? 0.0,
      },
  ];

  static StockLedgerReportResult parseStockLedgerReport(Map? message) {
    final columns = decodeDeskColumns(message?['columns']);
    final rawRows = message?['result'];
    final rows = <Map<String, dynamic>>[];
    if (rawRows is List) {
      final addsTotal = _stockReportAddsTotal(message);
      for (final (index, raw) in rawRows.indexed) {
        if (addsTotal && raw is List && index == rawRows.length - 1) continue;
        final row = decodeDeskRow(raw, columns);
        if (row == null || _stockReportFlag(row['is_total_row'])) continue;
        final voucher = (row['voucher_no'] ?? row['voucher_#'] ?? '').toString();
        final timestamp = (row['posting_datetime'] ?? row['date'] ??
            [row['posting_date'], row['posting_time']].whereType<String>().join(' '))
            .toString();
        final date = (row['posting_date'] ?? row['date'] ?? '').toString();
        // Opening and closing markers have neither a voucher nor a date.
        // When a positional grand total places a caption in the date column,
        // only a genuine timestamp can identify a voucherless movement.
        if (voucher.trim().isEmpty && DateTime.tryParse(timestamp.trim()) == null) {
          continue;
        }
        final actual = _stockReportNumber(row['actual_qty']);
        final inQty = _stockReportNumber(row['in_qty']);
        final outQty = _stockReportNumber(row['out_qty']);
        // A single nonzero side identifies the direction. A zero on one
        // side alone cannot tell us whether the missing side moved stock.
        final signed = actual ?? switch ((inQty, outQty)) {
          (final incoming?, final outgoing?) => incoming + outgoing,
          (final incoming?, null) when incoming != 0 => incoming,
          (null, final outgoing?) when outgoing != 0 => outgoing,
          _ => null,
        };
        rows.add(Map.unmodifiable({
          ...row,
          'date': date,
          'timestamp': timestamp,
          'voucher_type': (row['voucher_type'] ?? '').toString(),
          'voucher_no': voucher,
          'qty': signed,
          'balance': _stockReportNumber(
            row['qty_after_transaction'] ?? row['balance_qty'],
          ),
          'in_qty': inQty ?? signed?.clamp(0.0, double.infinity),
          'out_qty': outQty ?? signed?.clamp(double.negativeInfinity, 0.0),
        }));
      }
    }
    return (columns: columns, rows: List.unmodifiable(rows));
  }

  static double? _stockReportNumber(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return number?.isFinite == true ? number : null;
  }

  /// Sales-Order reservations behind the reserved figure for [itemCode] in
  /// [warehouse], via Stock Reservation Entry (the source of the report's
  /// reserved_stock column on ERPNext v15).
  ///
  /// Returns rows `{voucher_type, voucher_no, reserved, status}` where
  /// `reserved` = reserved_qty − delivered_qty (only still-reserved rows).
  /// Fail-open: returns `[]` on any error.
  Future<List<Map<String, dynamic>>> getStockReservations({
    required String itemCode,
    required String warehouse,
  }) async {
    try {
      final rows = await getList(
        null,
        doctype: 'Stock Reservation Entry',
        fields: [
          'voucher_type',
          'voucher_no',
          'reserved_qty',
          'delivered_qty',
          'status',
        ],
        filters: {
          'item_code': itemCode,
          if (warehouse.isNotEmpty) 'warehouse': warehouse,
          'docstatus': 1,
        },
        limit: 100,
        orderBy: 'creation asc',
      );
      double toNum(dynamic v) =>
          v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
      return rows
          .map((r) => <String, dynamic>{
                'voucher_type': (r['voucher_type'] ?? 'Sales Order').toString(),
                'voucher_no': (r['voucher_no'] ?? '').toString(),
                'reserved': toNum(r['reserved_qty']) - toNum(r['delivered_qty']),
                'status': (r['status'] ?? '').toString(),
              })
          .where((r) => (r['reserved'] as double) > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Calls `frappe.client.get_count` to retrieve a document count server-side.
  ///
  /// Much more efficient than fetching all documents with `limit: 0` and
  /// counting them client-side. The server returns `{"message": <int>}`.
  Future<Response> getDocumentCount(
    String doctype, {
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
  }) async {
    if (!_dioInitialised) await _initDio();
    return _dio.get(
      '/api/method/frappe.client.get_count',
      queryParameters: {
        'doctype': doctype,
        if (filterTuples != null && filterTuples.isNotEmpty)
          'filters': jsonEncode(filterTuples)
        else if (filters != null && filters.isNotEmpty)
          'filters': jsonEncode(filters),
      },
    );
  }

  // Module specific getters
  Future<Response> getPurchaseReceipts({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters, String orderBy = 'modified desc'}) async =>
      getDocumentList('Purchase Receipt', limit: limit, limitStart: limitStart, filters: filters, orderBy: orderBy, fields: ['name', 'owner', 'creation', 'modified', 'modified_by', 'docstatus', 'status', 'supplier', 'posting_date', 'posting_time', 'set_warehouse', 'currency', 'total_qty', 'grand_total', 'per_billed']);
  Future<Response> getPurchaseReceipt(String name) async => getDocument('Purchase Receipt', name);
  Future<Response> getPackingSlips({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Packing Slip', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'delivery_note', 'modified', 'creation', 'docstatus', 'custom_po_no', 'from_case_no', 'to_case_no', 'owner']);
  Future<Response> getPackingSlip(String name) async => getDocument('Packing Slip', name);
  Future<Response> getStockEntries({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Stock Entry', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'purpose', 'total_amount', 'custom_total_qty', 'modified', 'docstatus', 'creation', 'stock_entry_type']);
  Future<Response> getStockEntry(String name) async => getDocument('Stock Entry', name);
  Future<Response> getDeliveryNotes({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('Delivery Note', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'customer', 'grand_total', 'posting_date', 'modified', 'status', 'currency', 'po_no', 'total_qty', 'creation', 'docstatus']);
  Future<Response> getDeliveryNote(String name) async => getDocument('Delivery Note', name);
  Future<Response> getPosUploads({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    if (filters != null && filters.containsKey('docstatus')) filters.remove('docstatus');
    return getDocumentList('POS Upload', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'total_qty']);
  }
  Future<Response> getPosUpload(String name) async => getDocument('POS Upload', name);
  Future<Response> getTodos({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async =>
      getDocumentList('ToDo', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'status', 'description', 'modified', 'priority', 'date']);
  Future<Response> getTodo(String name) async => getDocument('ToDo', name);
  Future<Response> getPurchaseOrders({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters, String orderBy = 'modified desc'}) async {
    return getDocumentList('Purchase Order', limit: limit, limitStart: limitStart, filters: filters, fields: ['name', 'supplier', 'transaction_date', 'grand_total', 'currency', 'status', 'docstatus', 'modified', 'creation'], orderBy: orderBy);
  }
  Future<Response> getPurchaseOrder(String name) async => getDocument('Purchase Order', name);
  Future<Response> createPurchaseOrder(Map<String, dynamic> data) async => createDocument('Purchase Order', data);
  Future<Response> updatePurchaseOrder(String name, Map<String, dynamic> data) async => updateDocument('Purchase Order', name, data);
  Future<Response> login(String email, String password) async {
    _rackWarehouseSession++;
    clearDeskHtml();
    if (!_dioInitialised) await _initDio();
    try {
      final response = await _dio.post('/api/method/login', data: {'usr': email, 'pwd': password}, options: SessionExpiryInterceptor.unchecked());
      return response;
    } on DioException catch (e) {
      GlobalSnackbar.error(title: 'Login Error', message: e.message ?? 'An unknown error occurred');
      rethrow;
    } catch (e) {
      GlobalSnackbar.error(title: 'Login Error', message: 'An unexpected error occurred: $e');
      rethrow;
    }
  }
  Future<Response> loginWithFrappe(String username, String password) async {
    _rackWarehouseSession++;
    clearDeskHtml();
    if (!_dioInitialised) await _initDio();

    Future<Response> sendCredentials() => _dio.post(
          '/api/method/login',
          data: FormData.fromMap({'usr': username, 'pwd': password}),
          options: SessionExpiryInterceptor.unchecked(
            Options(contentType: Headers.formUrlEncodedContentType),
          ),
        );

    try {
      return await sendCredentials();
    } on DioException catch (error) {
      final cause = error.error;
      if (cause is! CookieManagerLoadException ||
          cause.error is! FileSystemException) {
        rethrow;
      }
      // CookieManager rejected the request before sending the credentials.
      await clearSessionCookies();
      return sendCredentials();
    }
  }
  // ── Desk boot page ────────────────────────────────────────────────────────
  /// How long a downloaded Desk page is reused.
  static const deskHtmlLifetime = Duration(minutes: 2);
  static final _deskBootMarker = RegExp(r'frappe\.boot\s*=');

  Future<String?>? _deskHtml;
  DateTime? _deskHtmlAt;

  /// The page Desk serves, which embeds `frappe.boot`: the session user's
  /// workspaces, sidebars and roles. v16 serves it at /desk (its /app only
  /// redirects there); v15 at /app. `null` when neither carries boot data
  /// (signed out, offline).
  ///
  /// The page is about half a megabyte and is wanted by several callers
  /// right after sign-in, so concurrent calls share one download and the
  /// result is reused for [deskHtmlLifetime]. A failed read is not kept.
  Future<String?> getDeskHtml() {
    final cached = _deskHtml;
    final at = _deskHtmlAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < deskHtmlLifetime) {
      return cached;
    }
    late final Future<String?> request;
    request = _fetchDeskHtml().then((html) {
      if (html == null && identical(_deskHtml, request)) clearDeskHtml();
      return html;
    });
    _deskHtmlAt = DateTime.now();
    return _deskHtml = request;
  }

  /// Forgets the reused Desk page: it belongs to one session on one server.
  void clearDeskHtml() {
    _deskHtml = null;
    _deskHtmlAt = null;
  }

  Future<String?> _fetchDeskHtml() async {
    if (!_dioInitialised) await _initDio();
    for (final path in const ['/desk', '/app']) {
      try {
        final r = await _dio.get<String>(
          path,
          options: Options(
              responseType: ResponseType.plain, followRedirects: false),
        );
        final html = r.data;
        if (html != null && _deskBootMarker.hasMatch(html)) return html;
      } catch (_) {
        // Wrong path for this version, or not reachable: try the next.
      }
    }
    return null;
  }

  Future<bool> hasSessionCookies() async {
    if (!_dioInitialised) await _initDio();
    final server = Uri.parse(_baseUrl);
    if ((server.scheme != 'https' && server.scheme != 'http') ||
        server.host.isEmpty) {
      throw const FormatException('Invalid server URL');
    }
    final cookies = await _cookieManager.cookieJar.loadForRequest(server);
    return cookies.any((cookie) => cookie.name == 'sid');
  }

  Future<void> clearSessionCookies() => _cookieCleanup ??=
      _clearSessionCookies().whenComplete(() => _cookieCleanup = null);

  Future<void> _clearSessionCookies() async {
    _rackWarehouseSession++;
    clearDeskHtml();
    if (!_dioInitialised) await _initDio();
    try {
      await _cookieManager.cookieJar.deleteAll();
    } catch (_) {
      // deleteAll initializes the jar first, so an unreadable index can block it.
      try {
        await Directory(_cookiePath).delete(recursive: true);
      } on PathNotFoundException {
        // Another caller already removed the persisted cookies.
      }
      final replacement = CookieManager(_createCookieJar(_cookiePath));
      final index = _dio.interceptors.indexOf(_cookieManager);
      _dio.interceptors[index] = replacement;
      _cookieManager = replacement;
    }
  }

  Future<String> getSessionCookieHeader() async {
    if (!_dioInitialised) await _initDio();
    final cookies =
        await _cookieManager.cookieJar.loadForRequest(Uri.parse(_baseUrl));
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  Future<Response> logoutApiCall({CancelToken? cancelToken}) async {
    _rackWarehouseSession++;
    if (!_dioInitialised) await _initDio();
    return await _dio.post(
      '/api/method/logout',
      cancelToken: cancelToken,
      options: SessionExpiryInterceptor.unchecked(),
    );
  }
  Future<Response> getLoggedUser() async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get(SessionExpiryInterceptor.identityPath, options: SessionExpiryInterceptor.unchecked());
  }
  Future<Response> getUserDetails(String email) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/resource/User/$email');
  }
  Future<Response> resetPassword(String email) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post('/api/method/frappe.core.doctype.user.user.reset_password', data: {'user': email}, options: Options(contentType: Headers.formUrlEncodedContentType));
  }
  Future<Response> changePassword(String oldPassword, String newPassword) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post('/api/method/frappe.core.doctype.user.user.update_password',
        data: {'old_password': oldPassword, 'new_password': newPassword, 'logout_all_sessions': 0},
        options: Options(contentType: Headers.formUrlEncodedContentType)
    );
  }
}
