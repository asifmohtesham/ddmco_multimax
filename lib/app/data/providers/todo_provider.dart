import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class ToDoProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  static const List<String> _listFields = [
    'name',
    'status',
    'description',
    'modified',
    'priority',
    'date',
  ];

  Future<Response> getTodos({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'ToDo',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: _listFields,
    );
  }

  Future<Response> getTodo(String name) async {
    return _apiProvider.getDocument('ToDo', name);
  }
}
