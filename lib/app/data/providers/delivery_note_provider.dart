import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class DeliveryNoteProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getDeliveryNotes({
    int limit = 20, 
    int limitStart = 0, 
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Delivery Note', 
      limit: limit, 
      limitStart: limitStart, 
      filters: filters,
      orderBy: orderBy,
      fields: ['name', 'customer', 'grand_total', 'posting_date', 'modified', 'status', 'currency', 'po_no', 'total_qty', 'creation', 'docstatus'],
    );
  }

  Future<Response> getDeliveryNote(String name) async {
    return _apiProvider.getDeliveryNote(name);
  }

  Future<Response> getPosUploads({int limit = 100, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return _apiProvider.getPosUploads(limit: limit, limitStart: limitStart, filters: filters);
  }

  Future<Response> getPosUpload(String name) async {
    return _apiProvider.getPosUpload(name);
  }

  Future<Response> getItemDetails(String barcode) async {
    return _apiProvider.getDocument('Item', barcode.substring(0, 7));
  }
}
