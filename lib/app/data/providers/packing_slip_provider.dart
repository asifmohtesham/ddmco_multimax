import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class PackingSlipProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPackingSlips({
    int limit = 20, 
    int limitStart = 0, 
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Packing Slip', 
      limit: limit, 
      limitStart: limitStart, 
      filters: filters,
      orderBy: orderBy,
      // Updated fields list based on requirement
      fields: ['name', 'delivery_note', 'modified', 'creation', 'docstatus', 'custom_po_no', 'from_case_no', 'to_case_no', 'owner'],
    );
  }

  Future<Response> getPackingSlip(String name) async {
    return _apiProvider.getDocument('Packing Slip', name);
  }
}
