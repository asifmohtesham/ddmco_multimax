import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';

/// Stock of an item in one rack. Item-level: the Stock Balance report cannot
/// split a rack by batch, so this says where the item is kept, not which
/// batch sits there.
class RackStockLine {
  const RackStockLine({
    required this.warehouse,
    required this.rack,
    required this.qty,
  });

  final String warehouse;

  /// Empty when the stock has no rack recorded.
  final String rack;
  final double qty;
}

/// Everything the oldest-stock-first check reads from the server.
///
/// Every method **throws** when the server cannot answer. The check refuses
/// the scan in that case; an empty result must only ever mean "none".
abstract class BatchAgeDataSource {
  /// The group warehouse [warehouse] sits under, or null at the top level.
  Future<String?> parentWarehouse(String warehouse);

  /// Batch balances of [itemCode] in [warehouse] — a group warehouse returns
  /// one line per leaf warehouse under it. Only positive balances.
  Future<List<BatchStockLine>> batchStock({
    required String itemCode,
    required String warehouse,
  });

  /// Age of each of [batchNos]. A batch the server does not know is absent.
  Future<Map<String, BatchAge>> batchAges(List<String> batchNos);

  /// Outward quantities of [itemCode] on draft Delivery Notes and draft Stock
  /// Entries, each tagged with its document.
  Future<List<BatchDraftLine>> draftLines({required String itemCode});

  /// Where [itemCode] is kept in [warehouse] (group or leaf), by rack.
  Future<List<RackStockLine>> rackStock({
    required String itemCode,
    required String warehouse,
  });
}

/// [BatchAgeDataSource] over the standard Frappe / ERPNext endpoints.
///
/// Every request is one both v15 and v16 accept; where a list form might be
/// refused, the second standard form is tried before giving up. Verified on
/// v16 (Frappe 16.56 / ERPNext 16.55) on 19 November 2026.
class ApiBatchAgeDataSource implements BatchAgeDataSource {
  ApiBatchAgeDataSource([ApiProvider? api]) : _injected = api;

  final ApiProvider? _injected;

  ApiProvider get _api =>
      _injected ??
      (Get.isRegistered<ApiProvider>() ? Get.find<ApiProvider>() : ApiProvider());

  /// warehouse → parent. The tree changes rarely; kept for the app session.
  static final Map<String, String?> _parentCache = {};

  /// Clears the cached warehouse tree (server switch, tests).
  static void clearCache() => _parentCache.clear();

  static const _maxRows = 1000;

  String get _company => Get.find<StorageService>().getCompany();

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  // ── Warehouse tree ─────────────────────────────────────────────────────

  @override
  Future<String?> parentWarehouse(String warehouse) async {
    final key = warehouse.trim();
    if (_parentCache.containsKey(key)) return _parentCache[key];
    final rows = _rows(await _api.getDocumentList(
      'Warehouse',
      fields: ['name', 'parent_warehouse'],
      filterTuples: [
        ['Warehouse', 'name', '=', key],
      ],
      limit: 1,
    ));
    if (rows.isEmpty) {
      throw StateError('Warehouse "$key" was not returned by the server');
    }
    final parent = (rows.first['parent_warehouse'] ?? '').toString().trim();
    return _parentCache[key] = parent.isEmpty ? null : parent;
  }

  // ── Balances ───────────────────────────────────────────────────────────

  @override
  Future<List<BatchStockLine>> batchStock({
    required String itemCode,
    required String warehouse,
  }) async {
    final response = await _api.getReport(
      'Batch-Wise Balance History',
      filters: {
        'company': _company,
        'from_date': _today,
        'to_date': _today,
        'item_code': itemCode,
        'warehouse': warehouse,
      },
    );
    return parseBatchStock(_message(response));
  }

  /// Rows of the Batch-Wise Balance History report → positive balances.
  /// Handles keyed rows and positional rows; the report's trailing Total row
  /// (a list, or a row with no batch) is dropped.
  static List<BatchStockLine> parseBatchStock(Map<String, dynamic> message) {
    final rows = message['result'];
    if (rows is! List) throw const FormatException('Report has no result');

    int? col(bool Function(String) test) {
      final columns = message['columns'];
      if (columns is! List) return null;
      for (var i = 0; i < columns.length; i++) {
        if (test(_columnName(columns[i]))) return i;
      }
      return null;
    }

    final batchIdx = col((c) => c == 'batch' || c == 'batch_no');
    final whIdx = col((c) => c == 'warehouse');
    final balIdx = col((c) => c == 'balance_qty' || c == 'bal_qty');

    final out = <BatchStockLine>[];
    for (final row in rows) {
      String batch;
      String warehouse;
      double qty;
      if (row is Map) {
        batch = _str(row['batch'] ?? row['batch_no']);
        warehouse = _str(row['warehouse']);
        qty = _num(row['balance_qty'] ?? row['bal_qty'] ?? row['balance']);
      } else if (row is List &&
          batchIdx != null &&
          whIdx != null &&
          balIdx != null &&
          row.length > batchIdx &&
          row.length > whIdx &&
          row.length > balIdx) {
        batch = _str(row[batchIdx]);
        warehouse = _str(row[whIdx]);
        qty = _num(row[balIdx]);
      } else {
        continue;
      }
      if (batch.isEmpty || warehouse.isEmpty || qty <= 0) continue;
      out.add(BatchStockLine(batchNo: batch, warehouse: warehouse, qty: qty));
    }
    return out;
  }

  // ── Ages ───────────────────────────────────────────────────────────────

  @override
  Future<Map<String, BatchAge>> batchAges(List<String> batchNos) async {
    final names = {
      for (final b in batchNos)
        if (b.trim().isNotEmpty) b.trim(),
    }.toList();
    if (names.isEmpty) return const {};

    final (receipts, records) =
        await (_firstReceiptDates(names), _batchRecordDates(names)).wait;

    final ages = <String, BatchAge>{};
    for (final name in names) {
      final record = records[name];
      // A batch missing from the Batch list is left out: its age is unknown
      // and the rule will refuse rather than guess.
      if (record == null) continue;
      final age = resolveBatchAge(
        firstReceipt: receipts[name],
        manufacturing: record.mfg,
        creation: record.created,
      );
      if (age != null) ages[name] = age;
    }
    return ages;
  }

  Future<Map<String, DateTime>> _firstReceiptDates(List<String> names) async {
    List<Map<String, dynamic>> rows;
    try {
      // One call: the Purchase Receipt list joined to its item rows.
      rows = _rows(await _api.getDocumentList(
        'Purchase Receipt',
        fields: [
          'name',
          'posting_date',
          '`tabPurchase Receipt Item`.batch_no',
        ],
        filterTuples: [
          ['Purchase Receipt Item', 'batch_no', 'in', names],
          ['Purchase Receipt', 'docstatus', '=', 1],
          ['Purchase Receipt', 'is_return', '=', 0],
        ],
        orderBy: 'posting_date asc',
        limit: _maxRows,
      ));
    } on DioException catch (e) {
      if (_isAuthFailure(e)) rethrow;
      rows = await _firstReceiptRowsTwoStep(names);
    }
    return parseFirstReceipts(rows);
  }

  /// Second standard form: item rows through their parent, then the receipts.
  Future<List<Map<String, dynamic>>> _firstReceiptRowsTwoStep(
      List<String> names) async {
    final items = _methodRows(await _api.callMethod(
      'frappe.client.get_list',
      params: {
        'doctype': 'Purchase Receipt Item',
        'parent': 'Purchase Receipt',
        'filters': json.encode([
          ['batch_no', 'in', names],
          ['docstatus', '=', 1],
        ]),
        'fields': json.encode(['parent', 'batch_no']),
        'limit_page_length': _maxRows,
      },
    ));
    final parents = {
      for (final r in items)
        if (_str(r['parent']).isNotEmpty) _str(r['parent']),
    }.toList();
    if (parents.isEmpty) return const [];

    final receipts = _rows(await _api.getDocumentList(
      'Purchase Receipt',
      fields: ['name', 'posting_date'],
      filterTuples: [
        ['Purchase Receipt', 'name', 'in', parents],
        ['Purchase Receipt', 'docstatus', '=', 1],
        ['Purchase Receipt', 'is_return', '=', 0],
      ],
      limit: parents.length + 5,
    ));
    final dateOf = {
      for (final r in receipts) _str(r['name']): r['posting_date'],
    };
    return [
      for (final r in items)
        if (dateOf.containsKey(_str(r['parent'])))
          {'batch_no': r['batch_no'], 'posting_date': dateOf[_str(r['parent'])]},
    ];
  }

  /// `{batch_no, posting_date}` rows → earliest date per batch.
  static Map<String, DateTime> parseFirstReceipts(
      List<Map<String, dynamic>> rows) {
    final first = <String, DateTime>{};
    for (final row in rows) {
      final batch = _str(row['batch_no']);
      final date = parseBatchAgeDate(row['posting_date']);
      if (batch.isEmpty || date == null) continue;
      final known = first[batch];
      if (known == null || date.isBefore(known)) first[batch] = date;
    }
    return first;
  }

  Future<Map<String, ({DateTime? mfg, DateTime? created})>> _batchRecordDates(
      List<String> names) async {
    final rows = _rows(await _api.getDocumentList(
      'Batch',
      fields: ['name', 'manufacturing_date', 'creation'],
      filterTuples: [
        ['Batch', 'name', 'in', names],
      ],
      // The list default is 20 rows; an item can have more batches in stock.
      limit: names.length + 5,
    ));
    return {
      for (final r in rows)
        _str(r['name']): (
          mfg: parseBatchAgeDate(r['manufacturing_date']),
          created: parseBatchAgeDate(r['creation']),
        ),
    };
  }

  // ── Drafts ─────────────────────────────────────────────────────────────

  @override
  Future<List<BatchDraftLine>> draftLines({required String itemCode}) async {
    final (deliveryNotes, stockEntries) = await (
      _draftRows(
        doctype: 'Delivery Note',
        child: 'Delivery Note Item',
        parentFields: ['name', 'set_warehouse'],
        childFields: ['batch_no', 'warehouse', 'stock_qty', 'qty'],
        itemCode: itemCode,
      ),
      _draftRows(
        doctype: 'Stock Entry',
        child: 'Stock Entry Detail',
        parentFields: ['name'],
        childFields: ['batch_no', 's_warehouse', 'transfer_qty', 'qty'],
        itemCode: itemCode,
      ),
    ).wait;
    return [
      ...parseDraftRows(deliveryNotes,
          doctype: 'Delivery Note',
          warehouseKeys: const ['warehouse', 'set_warehouse'],
          qtyKeys: const ['stock_qty', 'qty']),
      ...parseDraftRows(stockEntries,
          doctype: 'Stock Entry',
          warehouseKeys: const ['s_warehouse'],
          qtyKeys: const ['transfer_qty', 'qty']),
    ];
  }

  Future<List<Map<String, dynamic>>> _draftRows({
    required String doctype,
    required String child,
    required List<String> parentFields,
    required List<String> childFields,
    required String itemCode,
  }) async {
    try {
      return _rows(await _api.getDocumentList(
        doctype,
        fields: [
          ...parentFields,
          for (final f in childFields) '`tab$child`.$f',
        ],
        filterTuples: [
          [child, 'item_code', '=', itemCode],
          [doctype, 'docstatus', '=', 0],
        ],
        limit: _maxRows,
      ));
    } on DioException catch (e) {
      if (_isAuthFailure(e)) rethrow;
      // Second standard form: the child rows through their parent. The
      // document name comes back as `parent`; header fields are not available.
      final rows = _methodRows(await _api.callMethod(
        'frappe.client.get_list',
        params: {
          'doctype': child,
          'parent': doctype,
          'filters': json.encode([
            ['item_code', '=', itemCode],
            ['docstatus', '=', 0],
          ]),
          'fields': json.encode(['parent', ...childFields]),
          'limit_page_length': _maxRows,
        },
      ));
      return [
        for (final r in rows) {...r, 'name': r['parent']},
      ];
    }
  }

  /// Draft rows → lines with a batch, an outward warehouse and a quantity.
  /// The first non-blank of [warehouseKeys] / first positive of [qtyKeys] wins.
  static List<BatchDraftLine> parseDraftRows(
    List<Map<String, dynamic>> rows, {
    required String doctype,
    required List<String> warehouseKeys,
    required List<String> qtyKeys,
  }) {
    final out = <BatchDraftLine>[];
    for (final row in rows) {
      final batch = _str(row['batch_no']);
      if (batch.isEmpty) continue;
      final warehouse = warehouseKeys
          .map((k) => _str(row[k]))
          .firstWhere((w) => w.isNotEmpty, orElse: () => '');
      if (warehouse.isEmpty) continue; // inward-only row, or unknown source
      final qty = qtyKeys
          .map((k) => _num(row[k]))
          .firstWhere((q) => q > 0, orElse: () => 0);
      if (qty <= 0) continue;
      out.add(BatchDraftLine(
        batchNo: batch,
        warehouse: warehouse,
        qty: qty,
        doctype: doctype,
        docName: _str(row['name']),
      ));
    }
    return out;
  }

  // ── Racks ──────────────────────────────────────────────────────────────

  @override
  Future<List<RackStockLine>> rackStock({
    required String itemCode,
    required String warehouse,
  }) async {
    final response = await _api.getReport(
      'Stock Balance',
      filters: {
        'company': _company,
        'from_date': _today,
        'to_date': _today,
        // List or string depending on the server version — the one existing
        // version check, shared with every other Stock Balance call.
        'item_code': await _api.stockBalanceItemCodeFilter(itemCode),
        'warehouse': warehouse,
        'show_variant_attributes': 1,
        'show_dimension_wise_stock': 1,
      },
    );
    return parseRackStock(_message(response));
  }

  /// Rows of the Stock Balance report with the rack dimension → racks that
  /// hold stock, largest first. Zero and negative rack balances are dropped.
  static List<RackStockLine> parseRackStock(Map<String, dynamic> message) {
    final rows = message['result'];
    if (rows is! List) throw const FormatException('Report has no result');

    int? col(bool Function(String) test) {
      final columns = message['columns'];
      if (columns is! List) return null;
      for (var i = 0; i < columns.length; i++) {
        if (test(_columnName(columns[i]))) return i;
      }
      return null;
    }

    final whIdx = col((c) => c == 'warehouse');
    final rackIdx = col((c) => c == 'rack');
    final balIdx = col((c) => c == 'bal_qty');

    final totals = <String, RackStockLine>{};
    for (final row in rows) {
      String warehouse;
      String rack;
      double qty;
      if (row is Map) {
        warehouse = _str(row['warehouse']);
        rack = _str(row['rack']);
        qty = _num(row['bal_qty'] ?? row['qty']);
      } else if (row is List &&
          whIdx != null &&
          rackIdx != null &&
          balIdx != null &&
          row.length > whIdx &&
          row.length > rackIdx &&
          row.length > balIdx) {
        warehouse = _str(row[whIdx]);
        rack = _str(row[rackIdx]);
        qty = _num(row[balIdx]);
      } else {
        continue;
      }
      if (warehouse.isEmpty || qty <= 0) continue;
      final key = '$warehouse\u0000$rack';
      final known = totals[key];
      totals[key] = RackStockLine(
        warehouse: warehouse,
        rack: rack,
        qty: (known?.qty ?? 0) + qty,
      );
    }
    return totals.values.toList()..sort((a, b) => b.qty.compareTo(a.qty));
  }

  // ── Response helpers ───────────────────────────────────────────────────

  static bool _isAuthFailure(DioException e) {
    final status = e.response?.statusCode;
    return status == 401 || status == 403;
  }

  static List<Map<String, dynamic>> _rows(Response response) =>
      _asRows((response.data as Map?)?['data']);

  static List<Map<String, dynamic>> _methodRows(Response response) =>
      _asRows((response.data as Map?)?['message']);

  static List<Map<String, dynamic>> _asRows(dynamic raw) {
    if (raw is! List) throw const FormatException('Unexpected list response');
    return [
      for (final r in raw)
        if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  static Map<String, dynamic> _message(Response response) {
    final message = (response.data as Map?)?['message'];
    if (message is! Map) throw const FormatException('Report has no message');
    return Map<String, dynamic>.from(message);
  }

  static String _columnName(dynamic column) {
    if (column is Map) return _str(column['fieldname']).toLowerCase();
    final s = column.toString().toLowerCase();
    final cut = s.indexOf(':');
    return (cut >= 0 ? s.substring(0, cut) : s).trim().replaceAll(' ', '_');
  }

  static String _str(dynamic v) => v?.toString().trim() ?? '';

  static double _num(dynamic v) => switch (v) {
        final num n => n.toDouble(),
        final String s => double.tryParse(s) ?? 0.0,
        _ => 0.0,
      };
}
