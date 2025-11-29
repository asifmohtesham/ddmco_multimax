import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class PosUploadProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPosUploads({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return _apiProvider.getPosUploads(limit: limit, limitStart: limitStart, filters: filters);
  }

  Future<Response> getPosUpload(String name) async {
    return _apiProvider.getPosUpload(name);
  }
}
