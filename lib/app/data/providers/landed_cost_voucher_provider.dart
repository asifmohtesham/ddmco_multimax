import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class LandedCostVoucherProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getLandedCostVouchers({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Landed Cost Voucher',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: [
        'name',
        'company',
        'docstatus',
        'posting_date',
        'total_taxes_and_charges'
      ],
    );
  }

  Future<Response> getLandedCostVoucher(String name) async {
    return _apiProvider.getDocument('Landed Cost Voucher', name);
  }

  Future<Response> createLandedCostVoucher(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Landed Cost Voucher', data);
  }

  Future<Response> updateLandedCostVoucher(
    String name,
    Map<String, dynamic> data,
  ) async {
    return _apiProvider.updateDocument('Landed Cost Voucher', name, data);
  }
}
