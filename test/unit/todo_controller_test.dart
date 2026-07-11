import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/todo_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/modules/todo/todo_controller.dart';

class _FakeApiProvider extends ApiProvider {}

class _FakeToDoProvider extends ToDoProvider {
  Map<String, dynamic>? getTodoData;
  int getTodoStatusCode = 200;
  int updateStatusCode = 200;
  String? lastCloseName;
  String? lastCloseModified;

  @override
  Future<Response> getTodo(String name) async => Response(
        requestOptions: RequestOptions(path: '/api/resource/ToDo/$name'),
        statusCode: getTodoStatusCode,
        data: getTodoData == null ? null : {'data': getTodoData},
      );

  @override
  Future<Response> closeTodo(String name, {String? modified}) async {
    lastCloseName = name;
    lastCloseModified = modified;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/ToDo/$name'),
      statusCode: updateStatusCode,
    );
  }
}

Map<String, dynamic> _canned({
  String name = 'TD-0001',
  String status = 'Open',
}) =>
    {
      'name': name,
      'status': status,
      'description': 'Pack DN-101',
      'modified': '2026-07-11 09:05:00',
      'priority': 'High',
      'date': '2026-07-15',
      'reference_type': '',
      'reference_name': '',
      'allocated_to': '',
      'owner': '',
      'assigned_by': '',
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  late _FakeToDoProvider fakeProvider;

  setUp(() {
    Get.put<ApiProvider>(_FakeApiProvider());
    fakeProvider = _FakeToDoProvider();
    Get.put<ToDoProvider>(fakeProvider);
  });

  tearDown(() => Get.deleteAll(force: true));

  group('refreshTodoDetail', () {
    test('patches the cache and matching list row on success', () async {
      fakeProvider.getTodoData = _canned(status: 'Closed');
      final ctrl = ToDoController();
      ctrl.todos.add(ToDo.fromJson(_canned(status: 'Open')));

      await ctrl.refreshTodoDetail('TD-0001');

      expect(ctrl.todos.first.status, 'Closed');
    });

    // Regression: closeTodo used to evict the cache entry BEFORE
    // re-fetching, so a transient failure left the expanded detail panel
    // blank even though the close itself had already succeeded server-side.
    test('a failed re-fetch leaves the previous state intact (no evict-then-fetch)',
        () async {
      fakeProvider.getTodoData = _canned(status: 'Open');
      final ctrl = ToDoController();
      ctrl.todos.add(ToDo.fromJson(_canned(status: 'Open')));

      await ctrl.refreshTodoDetail('TD-0001');
      expect(ctrl.todos.first.status, 'Open');

      fakeProvider.getTodoStatusCode = 500;
      await ctrl.refreshTodoDetail('TD-0001');

      expect(ctrl.todos.first.status, 'Open',
          reason: 'a failed refresh must not blank already-shown data');
    });
  });

  group('setTodoStatus', () {
    test('closes a ToDo and sends the modified timestamp for optimistic locking',
        () async {
      fakeProvider.getTodoData = _canned(status: 'Closed');
      final ctrl = ToDoController();
      ctrl.todos.add(ToDo.fromJson(_canned(status: 'Open')));

      await ctrl.setTodoStatus('TD-0001',
          close: true, modified: '2026-07-11 09:00:00');

      expect(fakeProvider.lastCloseName, 'TD-0001');
      expect(fakeProvider.lastCloseModified, '2026-07-11 09:00:00');
      expect(ctrl.closingTodoName.value, isNull);
      expect(ctrl.todos.first.status, 'Closed');
    });

    // Regression: isClosingTodo used to be a single controller-wide RxBool,
    // so closing one card disabled every other card's Close button too.
    test('closingTodoName is scoped to the ToDo currently being closed',
        () async {
      fakeProvider.getTodoData = _canned();
      final ctrl = ToDoController();
      final future = ctrl.setTodoStatus('TD-0001', close: true);

      expect(ctrl.closingTodoName.value, 'TD-0001');

      await future;

      expect(ctrl.closingTodoName.value, isNull);
    });
  });
}
