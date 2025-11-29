import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class PurchaseReceiptProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPurchaseReceipts({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return _apiProvider.getPurchaseReceipts(limit: limit, limitStart: limitStart, filters: filters);
  }

  Future<Response> getPurchaseReceipt(String name) async {
    return _apiProvider.getPurchaseReceipt(name);
  }
}
