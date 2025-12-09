import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class ToDoProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getTodos({int limit = 20, int limitStart = 0, Map<String, dynamic>? filters}) async {
    return _apiProvider.getTodos(limit: limit, limitStart: limitStart, filters: filters);
  }

  Future<Response> getTodo(String name) async {
    return _apiProvider.getTodo(name);
  }
}
