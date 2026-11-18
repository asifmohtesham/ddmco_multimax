import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';

/// Item and Finished Goods stock lookups for the stock sheet.
class StockSheetProvider {
  StockSheetProvider({ApiProvider? api, DateTime Function()? now})
    : _api = api,
      _now = now ?? DateTime.now;

  static const String finishedGoodsWarehouse = 'Finished Goods - KA';
  static const int _chunkSize = 100;

  final ApiProvider? _api;
  final DateTime Function() _now;

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
