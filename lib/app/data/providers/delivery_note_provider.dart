import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class DeliveryNoteProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getDeliveryNotes({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return _apiProvider.getDeliveryNotes(limit: limit, limitStart: limitStart, filters: filters);
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
