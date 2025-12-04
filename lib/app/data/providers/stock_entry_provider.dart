import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class StockEntryProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getStockEntries({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return _apiProvider.getStockEntries(limit: limit, limitStart: limitStart, filters: filters);
  }

  Future<Response> getStockEntry(String name) async {
    return _apiProvider.getStockEntry(name);
  }

  Future<Response> createStockEntry(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Stock Entry', data);
  }

  Future<Response> updateStockEntry(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Stock Entry', name, data);
  }
}
