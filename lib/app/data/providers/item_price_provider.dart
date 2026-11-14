import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class ItemPriceProvider {
  final ApiProvider _api = Get.find<ApiProvider>();

  static const List<String> listFields = [
    'name',
    'item_code',
    'item_name',
    'uom',
    'price_list',
    'price_list_rate',
    'currency',
    'customer',
    'supplier',
    'batch_no',
    'valid_from',
    'valid_upto',
    'selling',
    'buying',
    'modified',
  ];

  Future<Response> getItemPrices({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    String orderBy = 'modified desc',
  }) =>
      _api.getDocumentList(
        'Item Price',
        limit: limit,
        limitStart: limitStart,
        fields: listFields,
        filterTuples: filters,
        orFilterTuples: orFilters,
        orderBy: orderBy,
      );

  Future<Response> getItemPrice(String name) =>
      _api.getDocument('Item Price', name);

  Future<Response> createItemPrice(Map<String, dynamic> data) =>
      _api.createDocument('Item Price', data);

  Future<Response> updateItemPrice(String name, Map<String, dynamic> data) =>
      _api.updateDocument('Item Price', name, data);

  Future<Response> deleteItemPrice(String name) =>
      _api.deleteDocument('Item Price', name);

  Future<int> count(List<List<dynamic>> filters) async {
    final res = await _api.getDocumentCount('Item Price', filterTuples: filters);
    return (res.data['message'] as num?)?.toInt() ?? 0;
  }

  /// Enabled price lists (3 on the live site).
  Future<Response> getPriceLists() => _api.getDocumentList(
        'Price List',
        limit: 0,
        fields: const ['name', 'currency', 'buying', 'selling'],
        filters: const {'enabled': 1},
        orderBy: 'name asc',
      );

  /// Full Item doc — the form needs `uoms`, `stock_uom`, `has_variants`.
  Future<Response> getItem(String itemCode) =>
      _api.getDocument('Item', itemCode);
}
