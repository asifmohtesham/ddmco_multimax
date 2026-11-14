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
    'reference_type',
    'reference_name',
    'allocated_to',
    'owner',
    'assigned_by',
  ];

  Future<Response> getTodos({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    List<List<dynamic>>? orFilterTuples,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'ToDo',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orFilterTuples: orFilterTuples,
      orderBy: orderBy,
      fields: _listFields,
    );
  }

  Future<Response> getTodo(String name) async {
    return _apiProvider.getDocument('ToDo', name);
  }

  Future<Response> createTodo(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('ToDo', data);
  }

  Future<Response> updateTodo(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('ToDo', name, data);
  }

  Future<Response> deleteTodo(String name) async {
    return _apiProvider.deleteDocument('ToDo', name);
  }

  /// [modified] is the document's last-known `modified` timestamp — passing
  /// it arms Frappe's optimistic-lock check (a stale write comes back HTTP
  /// 409 `TimestampMismatchError`) the same way a full [updateTodo] save
  /// does, so a status flip can't silently clobber a concurrent edit.
  Future<Response> closeTodo(String name, {String? modified}) async {
    return updateTodo(name, {
      'status': 'Closed',
      if (modified != null) 'modified': modified,
    });
  }

  Future<Response> reopenTodo(String name, {String? modified}) async {
    return updateTodo(name, {
      'status': 'Open',
      if (modified != null) 'modified': modified,
    });
  }
}
