import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/batch_wise_balance_row.dart';
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class ApiProvider {
  static const String defaultBaseUrl = "https://erp.domain.com";

  bool _dioInitialised = false;
  late Dio _dio;
  late CookieJar _cookieJar;
  String _baseUrl = defaultBaseUrl;

  String get baseUrl => _baseUrl;

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
      final parts = (_erpNextVersion ?? '').split('.');
      final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      // Unknown version → assume new behavior (safe default for ≥ v15.72)
      _stockBalanceUsesListFilters = _erpNextVersion != null ? minor >= 72 : true;
    } catch (_) {
      _stockBalanceUsesListFilters = true;
    }
    return _stockBalanceUsesListFilters!;
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

  ApiProvider() {
    _initDio();
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
    _stockBalanceUsesListFilters = null;
    _erpNextVersion = null;
    if (_dioInitialised) {
      _dio.options.baseUrl = _baseUrl;
    }
  }

  Future<void> _initDio() async {
    if (_dioInitialised) return;

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
    final cookiePath = '${appSupportDir.path}/.cookies/';
    _cookieJar = PersistCookieJar(ignoreExpires: true, storage: FileStorage(cookiePath));
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
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
    } on DioException catch (e) {
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
  Future<({Set<String> create, Set<String> write})> fetchDocTypeRoles(
      String doctype) async {
    final response = await callMethod(
      'frappe.desk.form.load.getdoctype',
      params: {'doctype': doctype, 'with_parent': 1},
    );
    return (
      create: rolesWithPermission(response.data, doctype, 'create'),
      write: rolesWithPermission(response.data, doctype, 'write'),
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
  /// permlevel 0 for [doctype] from a `getdoctype` response.
  ///
  /// getdoctype returns `{"docs": [<DocType meta>, …]}` (unwrapped); this also
  /// tolerates a `{"message": {"docs": …}}` shape defensively. Fail-closed:
  /// any unexpected shape yields an empty set. Exposed as a public static
  /// method so unit tests can exercise it without a live HTTP connection.
  static Set<String> rolesWithPermission(
      dynamic data, String doctype, String permKey) {
    final roles = <String>{};
    if (data is! Map) return roles;
    final docs = data['docs'] ??
        (data['message'] is Map ? data['message']['docs'] : null);
    if (docs is! List) return roles;
    for (final doc in docs) {
      if (doc is! Map) continue;
      if (doc['doctype'] != 'DocType' || doc['name'] != doctype) continue;
      final perms = doc['permissions'];
      if (perms is! List) continue;
      for (final p in perms) {
        if (p is! Map) continue;
        final lvl = p['permlevel'];
        if ((lvl == 0 || lvl == null) && p[permKey] == 1) {
          final role = p['role'];
          if (role is String && role.isNotEmpty) roles.add(role);
        }
      }
    }
    return roles;
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
  /// [_positional] is an OPTIONAL positional kept for backwards compat with
  /// any legacy call-site that still passes the doctype positionally.
  /// New call-sites should use the named [doctype] parameter instead:
  ///
  ///   ApiProvider().getList(doctype: 'Batch', filters: {...}, fields: [...])
  ///
  /// Group D fix: the param was previously declared as a required positional
  /// (String? _positional) with no default — callers that omitted it (i.e.
  /// all named-only call-sites) produced a compile error.  Wrapping in
  /// square brackets makes it an optional positional with an implicit null
  /// default, so both calling styles compile correctly.
  Future<List<Map<String, dynamic>>> getList(
    String? _positional, {
    String? doctype,
    Map<String, dynamic>? filters,
    List<String>? fields,
    int limit = 20,
    String orderBy = 'modified desc',
    String? groupBy = '',
    String? filterDoctype,
  }) async {
    final dt = _positional ?? doctype;
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
      print('Error fetching list for $dt: $e');
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
      print('Error fetching list for $doctype: $e');
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

  /// Fetches all rack names in [warehouse] from the Rack DocType API.
  ///
  /// Calls `GET /api/resource/Rack?filters=[["Rack","warehouse","=",wh]]&fields=["name"]&limit_page_length=0`.
  /// Returns an empty list when [warehouse] is empty or on any API error.
  Future<List<String>> getRacksByWarehouse(String warehouse) async {
    if (warehouse.isEmpty) return [];
    try {
      if (!_dioInitialised) await _initDio();
      final response = await _dio.get('/api/resource/Rack', queryParameters: {
        'fields':            json.encode(['name']),
        'filters':           json.encode([['Rack', 'warehouse', '=', warehouse]]),
        'limit_page_length': 0,
        'order_by':          'name asc',
      });
      return parseRacksByWarehouseResponse(response.data);
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

  /// Resolves the authoritative warehouse of [rack] from the Rack DocType.
  ///
  /// Distinguishes "rack does not exist" (404 → notFound) from transient
  /// failures (error) so callers can reject invalid racks while degrading
  /// gracefully offline.
  /// An empty [rack] resolves to [RackLookupStatus.notFound].
  Future<RackWarehouseLookup> getRackWarehouse(String rack) async {
    if (rack.isEmpty) return const RackWarehouseLookup.notFound();
    try {
      final response = await getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data != null) {
        return RackWarehouseLookup.found(
            parseRackWarehouseResponse(response.data));
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

  Future<({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})>
      getStockBalanceReport({
    required String fromDate,
    required String toDate,
    List<String>? itemCodes,
    String? warehouse,
    String? itemGroup,
    bool showDimensionWise     = false,
    bool showVariantAttributes = false,
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

    final filters = <String, dynamic>{
      'company'             : storage.getCompany(),
      'from_date'           : fromDate,
      'to_date'             : toDate,
      'valuation_field_type': 'Currency',
      if (itemCodeFilter != null)
        'item_code'         : itemCodeFilter,
      if (warehouse != null && warehouse.isNotEmpty)
        'warehouse'         : warehouse,
      if (itemGroup != null && itemGroup.isNotEmpty)
        'item_group'        : itemGroup,
      if (showDimensionWise)     'show_dimension_wise_stock': 1,
      if (showVariantAttributes) 'show_variant_attributes'  : 1,
    };

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
      return (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    }

    return parseStockBalanceResponse(
      response.data['message'] as Map<String, dynamic>?,
    );
  }

  // ---------------------------------------------------------------------------
  // getBatchWiseBalance
  //
  // All-named params, optional batchNo (omit = fetch all batches for item+wh).
  // Used by ItemSheetControllerBase.fetchBatchBalance and
  // StockEntryItemFormController.fetchBatchWiseHistory.
  // Signature was already correct on this branch — no changes needed.
  // ---------------------------------------------------------------------------

  /// Fetch Batch-Wise Balance History rows for [itemCode].
  ///
  /// [batchNo] is optional — omit to fetch all in-stock batches for the item
  /// (used by BatchPickerSheet pre-fetch / fetchBatchWiseHistory).
  ///
  /// Both Map rows (key-based) and List rows (positional) are normalised to
  /// a consistent shape: {'batch_no': String, 'qty': double, ...} so that
  /// [ItemSheetControllerBase.fetchBatchBalance] can always read r['qty']
  /// regardless of the ERP response format.
  Future<List<Map<String, dynamic>>> getBatchWiseBalance({
    required String itemCode,
    String? batchNo,
    String? warehouse,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final String company = storage.getCompany();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final Map<String, dynamic> filters = {
      "company"   : company,
      "from_date" : today,
      "to_date"   : today,
      "item_code" : itemCode,
    };

    if (batchNo   != null && batchNo.isNotEmpty)   filters["batch_no"]  = batchNo;
    if (warehouse != null && warehouse.isNotEmpty) filters["warehouse"] = warehouse;

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
      if (rawRows == null) return [];

      final firstRow = rawRows.firstWhere((r) => r != null, orElse: () => null);

      if (firstRow is Map) {
        // Fix 1: Map rows from Batch-Wise Balance History report carry the
        // balance under 'balance_qty', not 'qty'.  Normalise to 'qty' so
        // fetchBatchBalance() (which reads r['qty']) gets the correct value.
        return rawRows
            .whereType<Map>()
            .map((r) {
              final m = Map<String, dynamic>.from(r);
              m['qty'] ??= _toDouble(
                m['balance_qty'] ?? m['bal_qty'] ?? m['balance'],
              );
              return m;
            })
            .toList();
      }

      // List rows — resolve column indices
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

  // ---------------------------------------------------------------------------
  // getItemVariantDetails
  // ---------------------------------------------------------------------------

  /// Fetches all variants of [itemCode] (the template/parent item) via the
  /// ERPNext "Item Variant Details" script report.
  ///
  /// Returns both column definitions (dynamic per item template) and row data
  /// so the UI can render attribute columns generically at runtime.
  Future<({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})>
      getItemVariantDetails(String itemCode) async {
    if (!_dioInitialised) await _initDio();

    late final Response response;
    try {
      response = await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'           : 'Item Variant Details',
          'filters'               : json.encode({'item': itemCode}),
          'ignore_prepared_report': 'true',
          '_'                     : DateTime.now().millisecondsSinceEpoch,
        },
      );
    } on DioException {
      return (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    } catch (_) {
      return (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    }

    if (response.statusCode != 200) {
      return (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    }

    return parseItemVariantDetailsResponse(
      response.data['message'] as Map<String, dynamic>?,
    );
  }

  /// Exposed as a public static method so unit tests can exercise the parsing
  /// logic without a live HTTP connection or GetX service registration.
  static ({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})
      parseItemVariantDetailsResponse(Map<String, dynamic>? message) {
    const empty = (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    if (message == null) return empty;
    try {
      final rawCols = message['columns'] as List<dynamic>? ?? [];
      final rawRows = message['result']  as List<dynamic>? ?? [];
      final columns = rawCols
          .whereType<Map>()
          .map((c) => Map<String, dynamic>.from(c))
          .toList();
      final rows = rawRows
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      return (columns: columns, rows: rows);
    } catch (_) {
      return empty;
    }
  }

  static ({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})
      parseStockBalanceResponse(Map<String, dynamic>? message) {
    const empty = (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    if (message == null) return empty;
    try {
      final rawCols = message['columns'] as List<dynamic>? ?? [];
      final rawRows = message['result']  as List<dynamic>? ?? [];
      if (rawRows.isEmpty) return empty;

      String fn(dynamic col) {
        if (col is Map) return (col['fieldname'] as String? ?? '').toLowerCase();
        final s       = col.toString().toLowerCase();
        final lastDot = s.lastIndexOf('.');
        return lastDot >= 0
            ? s.substring(lastDot + 1).replaceAll('`', '')
            : s;
      }

      String lbl(dynamic col) {
        if (col is Map) return (col['label'] as String? ?? '');
        return col.toString();
      }

      final columns = rawCols
          .map((c) => <String, dynamic>{'fieldname': fn(c), 'label': lbl(c)})
          .toList();

      // Find first non-null row to determine row format (Map vs List).
      // Avoid firstWhere with orElse: () => null — the inferred return type
      // conflicts with the list element type and throws at runtime.
      dynamic firstRow;
      for (final r in rawRows) {
        if (r != null) { firstRow = r; break; }
      }

      if (firstRow is Map) {
        final rows = rawRows
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        return (columns: columns, rows: rows);
      }

      final fieldnames = rawCols.map(fn).toList();
      final rows = rawRows
          .whereType<List>()
          .map((r) {
            final row = <String, dynamic>{};
            for (var i = 0; i < fieldnames.length && i < r.length; i++) {
              row[fieldnames[i]] = r[i];
            }
            return row;
          })
          .toList();

      return (columns: columns, rows: rows);
    } catch (_) {
      return empty;
    }
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

  // ---------------------------------------------------------------------------
  // getItemDetails — Item Variant Details tile helper
  // ---------------------------------------------------------------------------

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

  /// Fetch per-rack stock balance rows for [itemCode] + [warehouse],
  /// optionally filtered by [batchNo].
  ///
  /// Always sends `show_variant_attributes=1` and
  /// `show_dimension_wise_stock=1` so the Stock Balance report expands
  /// rows by rack dimension.
  ///
  /// Both Map rows (key-based) and List rows (positional) are handled.
  /// Every returned row is normalised to {'rack': String, 'qty': double}
  /// so callers can always read r['rack'] and r['qty'] regardless of the
  /// ERP response format.
  Future<List<Map<String, dynamic>>> getStockBalanceWithDimension({
    required String itemCode,
    String? warehouse,
    String? batchNo,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();
    final company = storage.getCompany();
    final today   = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final filters = <String, dynamic>{
      'company'                  : company,
      'from_date'                : today,
      'to_date'                  : today,
      'item_code'                : await stockBalanceItemCodeFilter(itemCode),
      'show_variant_attributes'  : 1,
      'show_dimension_wise_stock': 1,
    };
    if (warehouse != null && warehouse.isNotEmpty) filters['warehouse'] = warehouse;
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
              return <String, dynamic>{'rack': rack, 'qty': qty};
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
            return <String, dynamic>{'rack': rack, 'qty': qty};
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
  /// pickers without prefetching the whole table.
  Future<List<String>> searchLinkOptions(
    String doctype, {
    String query = '',
    int limit = 20,
  }) async {
    final rows = await getList(
      null,
      doctype: doctype,
      fields: ['name'],
      filters: query.trim().isEmpty ? null : {'name': ['like', '%${query.trim()}%']},
      limit: limit,
      orderBy: 'name asc',
    );
    return rows
        .map((r) => (r['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
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
  /// message.result (List<dynamic>) and message.columns.
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

  /// Fetches Stock Ledger entries for [itemCode] in [warehouse] over the
  /// [fromDate]–[toDate] period, for the ledger drill-down sheet.
  ///
  /// Returns rows `{date, voucher_type, voucher_no, qty, balance}` oldest →
  /// newest (`qty` = signed actual_qty, `balance` = qty_after_transaction).
  /// Fail-open: returns `[]` on any error so the sheet shows an empty state.
  Future<List<Map<String, dynamic>>> getStockLedgerEntries({
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
    try {
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
      if (response.statusCode != 200) return [];
      return parseStockLedgerEntries(
          response.data['message'] as Map<String, dynamic>?);
    } catch (_) {
      return [];
    }
  }

  /// Normalises a Stock Ledger report `message` into ledger rows. Exposed as a
  /// static so the parsing is unit-testable without a live connection.
  static List<Map<String, dynamic>> parseStockLedgerEntries(
      Map<String, dynamic>? message) {
    if (message == null) return [];
    try {
      final rawCols = message['columns'] as List<dynamic>? ?? [];
      final rawRows = message['result']  as List<dynamic>? ?? [];
      if (rawRows.isEmpty) return [];

      String fn(dynamic c) {
        if (c is Map) return (c['fieldname'] as String? ?? '').toLowerCase();
        final s = c.toString().toLowerCase();
        final i = s.lastIndexOf('.');
        return i >= 0 ? s.substring(i + 1).replaceAll('`', '') : s;
      }

      dynamic first;
      for (final r in rawRows) {
        if (r != null) { first = r; break; }
      }
      late final List<Map<String, dynamic>> mapRows;
      if (first is Map) {
        mapRows = rawRows
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
      } else {
        final names = rawCols.map(fn).toList();
        mapRows = rawRows.whereType<List>().map((r) {
          final m = <String, dynamic>{};
          for (var i = 0; i < names.length && i < r.length; i++) {
            m[names[i]] = r[i];
          }
          return m;
        }).toList();
      }

      double toNum(dynamic v) =>
          v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

      return mapRows
          .where((r) => r['voucher_no'] != null || r['posting_date'] != null)
          .map((r) => <String, dynamic>{
                'date': (r['posting_date'] ?? r['date'] ?? '').toString(),
                'voucher_type': (r['voucher_type'] ?? '').toString(),
                'voucher_no': (r['voucher_no'] ?? '').toString(),
                'qty': toNum(r['actual_qty']),
                'balance': toNum(r['qty_after_transaction']),
              })
          .toList();
    } catch (_) {
      return [];
    }
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
  }) async {
    if (!_dioInitialised) await _initDio();
    return _dio.get(
      '/api/method/frappe.client.get_count',
      queryParameters: {
        'doctype': doctype,
        if (filters != null && filters.isNotEmpty)
          'filters': jsonEncode(filters),
      },
    );
  }

  // Module specific getters
  Future<Response> getPurchaseReceipts({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters, String orderBy = 'modified desc'}) async =>
      getDocumentList('Purchase Receipt', limit: limit, limitStart: limitStart, filters: filters, orderBy: orderBy, fields: ['name', 'owner', 'creation', 'modified', 'modified_by', 'docstatus', 'status', 'supplier', 'posting_date', 'posting_time', 'set_warehouse', 'currency', 'total_qty', 'grand_total']);
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
    if (!_dioInitialised) await _initDio();
    try {
      final response = await _dio.post('/api/method/login', data: {'usr': email, 'pwd': password});
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
    if (!_dioInitialised) await _initDio();
    try {
      final formData = FormData.fromMap({'usr': username, 'pwd': password});
      return await _dio.post('/api/method/login', data: formData, options: Options(contentType: Headers.formUrlEncodedContentType));
    } on DioException catch (e) {
      rethrow;
    }
  }
  Future<bool> hasSessionCookies() async {
    if (!_dioInitialised) await _initDio();
    final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
    return cookies.any((cookie) => cookie.name == 'sid');
  }
  Future<void> clearSessionCookies() async {
    if (!_dioInitialised) await _initDio();
    await _cookieJar.deleteAll();
  }

  Future<String> getSessionCookieHeader() async {
    if (!_dioInitialised) await _initDio();
    final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  Future<Response> logoutApiCall() async {
    if (!_dioInitialised) await _initDio();
    return await _dio.post('/api/method/logout');
  }
  Future<Response> getLoggedUser() async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get('/api/method/frappe.auth.get_logged_user');
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
