import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get/get.dart' hide Response, FormData;
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/batch_wise_balance_row.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class ApiProvider {
  static const String defaultBaseUrl = "https://erp.multimax.cloud";

  bool _dioInitialised = false;
  late Dio _dio;
  late CookieJar _cookieJar;
  String _baseUrl = defaultBaseUrl;

  String get baseUrl => _baseUrl;

  ApiProvider() {
    _initDio();
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
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
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
    String orderBy = 'modified desc',
  }) async {
    if (!_dioInitialised) await _initDio();

    final String endpoint = '/api/resource/$doctype';
    final queryParameters = {
      'limit_page_length': limit,
      'limit_start': limitStart,
      'order_by': orderBy,
    };

    if (fields != null) {
      queryParameters['fields'] = json.encode(fields);
    }

    // Process Standard Filters (AND)
    if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        if (entry.value is List && (entry.value as List).length == 2) {
          return [doctype, entry.key, entry.value[0], entry.value[1]];
        }
        return [doctype, entry.key, '=', entry.value];
      }).toList();

      queryParameters['filters'] = json.encode(filterList);
    }

    // Process OR Filters (OR)
    if (orFilters != null && orFilters.isNotEmpty) {
      final List<List<dynamic>> orFilterList = orFilters.entries.map((entry) {
        if (entry.value is List && (entry.value as List).length == 2) {
          return [doctype, entry.key, entry.value[0], entry.value[1]];
        }
        return [doctype, entry.key, '=', entry.value];
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

  /// Submit a document (change docstatus from 0 to 1) in ERPNext.
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
  }) async {
    final dt = _positional ?? doctype;
    if (dt == null) return [];

    try {
      if (!_dioInitialised) await _initDio();
      final response = await _dio.get('/api/resource/$dt', queryParameters: {
        if (fields != null) 'fields': json.encode(fields)
        else 'fields': json.encode(['name']),
        'limit_page_length': limit,
        'order_by': orderBy,
        if (filters != null && filters.isNotEmpty)
          'filters': json.encode(
            filters.entries.map((e) {
              if (e.value is List && (e.value as List).length == 2) {
                return [dt, e.key, e.value[0], e.value[1]];
              }
              return [dt, e.key, '=', e.value];
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
      "item_code": itemCode,
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
        // Key-based rows — return as-is
        return rawRows
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
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
  /// rows by rack dimension.  The trailing Total row (a List, not a Map)
  /// is discarded before returning.
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
      'item_code'                : itemCode,
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

      // Discard the trailing Total row — it is always a List, never a Map.
      // Map rows are the real per-rack data rows.
      final dataRows = rawRows.whereType<Map>().toList();
      if (dataRows.isEmpty) return [];

      return dataRows
          .map((r) {
            final rack = (r['rack'] ?? '').toString().trim();
            final qty  = _toDouble(r['bal_qty'] ?? r['qty'] ?? r['balance_qty']);
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
      'item_code': itemCode,
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
