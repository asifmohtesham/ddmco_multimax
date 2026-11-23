import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_logic.dart';
import 'package:multimax/app/modules/stock_sheet/model/ageing_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/items_from_photos_models.dart';

/// Item and Finished Goods stock lookups for the stock sheet.
class ItemsFromPhotosProvider {
  ItemsFromPhotosProvider({
    ApiProvider? api,
    DateTime Function()? now,
    String Function()? company,
  }) : _api = api,
       _now = now ?? DateTime.now,
       _company = company ?? (() => Get.find<StorageService>().getCompany());

  static const String finishedGoodsWarehouse = 'Finished Goods - KA';
  static const int _chunkSize = 100;

  /// The ageing ranges the Stock Ageing report is run with.
  static const String ageingRange = '90, 180, 360, 720';

  final ApiProvider? _api;
  final DateTime Function() _now;
  final String Function() _company;

  ApiProvider get _client => _api ?? Get.find<ApiProvider>();

  /// Item master data for [itemCodes]; codes the ERP does not know are absent.
  Future<Map<String, ItemInfo>> fetchItems(List<String> itemCodes) async {
    final result = <String, ItemInfo>{};
    for (final chunk in _chunks(itemCodes)) {
      final response = await _guard(
        () => _client.getDocumentList(
          'Item',
          fields: const [
            'name',
            'item_name',
            'variant_of',
            'country_of_origin',
            'image',
          ],
          filterTuples: [
            ['Item', 'name', 'in', chunk],
          ],
          limit: 0,
        ),
      );
      final data = response.data is Map ? response.data['data'] : null;
      // A body without a data list is not "no such items": treating it so
      // would list every code as not in the ERP.
      if (data is! List) {
        throw const FormatException('Unexpected Item response');
      }
      for (final row in data) {
        if (row is! Map) continue;
        final code = row['name']?.toString() ?? '';
        if (code.isEmpty) continue;
        result[code] = ItemInfo(
          itemCode: code,
          itemName: _text(row['item_name']),
          variantOf: _text(row['variant_of']),
          countryOfOrigin: _text(row['country_of_origin']),
          image: _text(row['image']),
        );
      }
    }
    return result;
  }

  /// Today's Stock Balance rows for [itemCodes] in Finished Goods (child
  /// warehouses included by the report), one row per rack.
  Future<List<Map<String, dynamic>>> fetchFinishedGoodsStock(
    List<String> itemCodes,
  ) async {
    final today = DateFormat('yyyy-MM-dd').format(_now());
    final rows = <Map<String, dynamic>>[];
    for (final chunk in _chunks(itemCodes)) {
      final report = await _guard(
        () => _client.getStockBalanceReport(
          fromDate: today,
          toDate: today,
          itemCodes: chunk,
          warehouses: const [finishedGoodsWarehouse],
          showDimensionWise: true,
        ),
      );
      final wanted = chunk.toSet();
      // v15 before 15.72 ignores the item filter and returns the whole
      // warehouse, so drop anything outside the chunk.
      rows.addAll(
        report.rows.where((r) => wanted.contains(r['item_code']?.toString())),
      );
    }
    return rows;
  }

  /// The item's rows in Stock Ageing as of today, Finished Goods; empty when
  /// the report has none. Throws [StockAccessDenied] on 403 and whatever else
  /// the call throws.
  Future<List<ItemAgeing>> fetchStockAgeing(String itemCode) async {
    final response = await _guard(
      () => _client.runStockAgeingCustom(
        filters: {
          'company': _company(),
          'to_date': DateFormat('yyyy-MM-dd').format(_now()),
          'warehouse': finishedGoodsWarehouse,
          'range': ageingRange,
          'item_code': itemCode,
          'show_warehouse_wise_stock': 0,
        },
      ),
    );
    final data = response.data;
    final message = data is Map ? data['message'] : null;
    if (message is! Map) {
      throw const FormatException('Unexpected Stock Ageing response');
    }
    // The report is a Custom Report whose saved column titles are frozen, so
    // the buckets are titled from the range the run was made with.
    final columns = StockAgeingLogic.applyRange(
      message['columns'] is List ? message['columns'] as List : const [],
      ageingRange,
    );
    final buckets = StockAgeingLogic.parseBuckets(columns);
    // The four figures' labels, verbatim from the report.
    final labels = <String, String>{
      for (final c in columns)
        if (c is Map &&
            _text(c['fieldname']) != null &&
            _text(c['label']) != null)
          _text(c['fieldname'])!: _text(c['label'])!,
    };
    final kept = StockAgeingLogic.parseRows(
      message['result'],
    ).where((r) => r['item_code']?.toString() == itemCode).toList();
    final num_ = StockAgeingLogic.num_;
    return [
      for (final r in kept)
        ItemAgeing(
          warehouse: kept.length > 1 ? _text(r['warehouse']) : null,
          availableQty: num_(r['qty']),
          averageAge: num_(r['average_age']),
          earliest: num_(r['earliest']).round(),
          latest: num_(r['latest']).round(),
          buckets: [
            for (final b in buckets)
              (label: b.label, qty: num_(r[b.qtyKey])),
          ],
          availableQtyLabel: labels['qty'] ?? 'Available Qty',
          averageAgeLabel: labels['average_age'] ?? 'Average Age',
          earliestLabel: labels['earliest'] ?? 'Earliest',
          latestLabel: labels['latest'] ?? 'Latest',
        ),
    ];
  }

  /// The bytes of an Item's image ([ItemInfo.image]). Throws on failure.
  Future<Uint8List> fetchImage(String url) => _client.getFileBytes(url);

  Iterable<List<String>> _chunks(List<String> codes) sync* {
    final distinct = codes.toSet().toList();
    for (var i = 0; i < distinct.length; i += _chunkSize) {
      final end = i + _chunkSize < distinct.length
          ? i + _chunkSize
          : distinct.length;
      yield distinct.sublist(i, end);
    }
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) throw const StockAccessDenied();
      rethrow;
    }
  }

  String? _text(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
