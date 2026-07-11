import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/modules/todo/form/todo_form_controller.dart';

class _FakeApiProvider extends ApiProvider {}

class _FakeToDoProvider extends ToDoProvider {
  Map<String, dynamic>? getTodoData;
  int getTodoStatusCode = 200;

  Map<String, dynamic>? createTodoData;
  int createTodoStatusCode = 200;
  Map<String, dynamic>? lastCreatePayload;

  Map<String, dynamic>? updateTodoData;
  int updateTodoStatusCode = 200;
  Map<String, dynamic>? lastUpdatePayload;
  String? lastUpdateName;
  Object? throwOnUpdate;

  @override
  Future<Response> getTodo(String name) async => Response(
        requestOptions: RequestOptions(path: '/api/resource/ToDo/$name'),
        statusCode: getTodoStatusCode,
        data: getTodoData == null ? null : {'data': getTodoData},
      );

  @override
  Future<Response> createTodo(Map<String, dynamic> data) async {
    lastCreatePayload = data;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/ToDo'),
      statusCode: createTodoStatusCode,
      data: createTodoData == null ? null : {'data': createTodoData},
    );
  }

  @override
  Future<Response> updateTodo(String name, Map<String, dynamic> data) async {
    lastUpdateName = name;
    lastUpdatePayload = data;
    if (throwOnUpdate != null) throw throwOnUpdate!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/ToDo/$name'),
      statusCode: updateTodoStatusCode,
      data: updateTodoData == null ? null : {'data': updateTodoData},
    );
  }
}

class _FakeUserProvider extends UserProvider {
  @override
  Future<Response> getUsers() async => Response(
        requestOptions: RequestOptions(path: '/api/resource/User'),
        statusCode: 200,
        data: {'data': const <Map<String, dynamic>>[]},
      );
}

Map<String, dynamic> _canned({
  String name = 'TD-0001',
  String status = 'Open',
  String description = 'Pack DN-101',
  String priority = 'High',
  String date = '2026-07-15',
  String referenceType = 'Delivery Note',
  String referenceName = 'DN-00042',
  String allocatedTo = 'ops@x.com',
}) =>
    {
      'name': name,
      'status': status,
      'description': description,
      'modified': '2026-07-11 09:00:00',
      'priority': priority,
      'date': date,
      'reference_type': referenceType,
      'reference_name': referenceName,
      'allocated_to': allocatedTo,
      'owner': allocatedTo,
      'assigned_by': '',
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ApiProvider's constructor fires _initDio(), which touches
    // path_provider for the cookie-jar directory — stub it so construction
    // doesn't throw in this headless test environment.
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
    Get.put<UserProvider>(_FakeUserProvider());
  });

  tearDown(() => Get.deleteAll(force: true));

  group('isEditable / canShowCloseAction', () {
    test('view mode is not editable', () {
      final ctrl = ToDoFormController()..mode.value = 'view';
      expect(ctrl.isEditable, isFalse);
    });

    test('new and edit modes are editable', () {
      final ctrl = ToDoFormController();
      ctrl.mode.value = 'new';
      expect(ctrl.isEditable, isTrue);
      ctrl.mode.value = 'edit';
      expect(ctrl.isEditable, isTrue);
    });

    test('close action hidden for an unsaved (new) doc', () {
      final ctrl = ToDoFormController()
        ..mode.value = 'new'
        ..name = '';
      expect(ctrl.canShowCloseAction, isFalse);
    });

    test('close action hidden for a cancelled doc', () {
      final ctrl = ToDoFormController()
        ..mode.value = 'edit'
        ..name = 'TD-0001';
      ctrl.status.value = 'Cancelled';
      expect(ctrl.canShowCloseAction, isFalse);
    });

    test('close action shown for an open, saved doc', () {
      final ctrl = ToDoFormController()
        ..mode.value = 'edit'
        ..name = 'TD-0001';
      ctrl.status.value = 'Open';
      expect(ctrl.canShowCloseAction, isTrue);
    });

    // Regression: 'view' mode is documented as read-only (no save/close
    // actions — see the class doc comment), but an earlier version of
    // canShowCloseAction only excluded 'new', so the header Close/Reopen
    // action rendered and was tappable in view mode too — exactly how the
    // Dashboard's "Upcoming tasks" row and every write-permission-gated
    // fallback open this form.
    test('close action hidden in view mode even for an open, saved doc', () {
      final ctrl = ToDoFormController()
        ..mode.value = 'view'
        ..name = 'TD-0001';
      ctrl.status.value = 'Open';
      expect(ctrl.canShowCloseAction, isFalse);
    });
  });

  group('fetchDocument', () {
    test('populates every field from the server response', () async {
      fakeProvider.getTodoData = _canned();
      final ctrl = ToDoFormController()
        ..mode.value = 'edit'
        ..name = 'TD-0001';

      await ctrl.fetchDocument();

      expect(ctrl.descriptionController.text, 'Pack DN-101');
      expect(ctrl.status.value, 'Open');
      expect(ctrl.priority.value, 'High');
      expect(ctrl.date.value, '2026-07-15');
      expect(ctrl.referenceType.value, 'Delivery Note');
      expect(ctrl.referenceName.value, 'DN-00042');
      expect(ctrl.allocatedTo.value, 'ops@x.com');
      expect(ctrl.isDirty.value, isFalse);
      expect(ctrl.isLoading.value, isFalse);
    });

    test('leaves the form usable when the fetch fails', () async {
      fakeProvider.getTodoStatusCode = 404;
      final ctrl = ToDoFormController()
        ..mode.value = 'edit'
        ..name = 'missing';

      await ctrl.fetchDocument();

      expect(ctrl.isLoading.value, isFalse);
    });
  });

  group('saveDocument — create', () {
    test('creates a new ToDo and flips to edit mode on success', () async {
      fakeProvider.createTodoData = _canned(name: 'TD-0099');
      fakeProvider.getTodoData = _canned(name: 'TD-0099');

      final ctrl = ToDoFormController()
        ..mode.value = 'new'
        ..name = '';
      ctrl.descriptionController.text = 'New task';
      ctrl.isDirty.value = true;

      await ctrl.saveDocument();

      expect(fakeProvider.lastCreatePayload?['description'], 'New task');
      expect(ctrl.mode.value, 'edit');
      expect(ctrl.name, 'TD-0099');
      expect(ctrl.saveResult.value, SaveResult.success);
      expect(ctrl.isSaving.value, isFalse);
    });

    test('flags an error result when create fails', () async {
      fakeProvider.createTodoStatusCode = 500;

      final ctrl = ToDoFormController()
        ..mode.value = 'new'
        ..name = '';
      ctrl.descriptionController.text = 'x';

      await ctrl.saveDocument();

      expect(ctrl.saveResult.value, SaveResult.error);
      expect(ctrl.mode.value, 'new', reason: 'should not flip modes on failure');
      expect(ctrl.isSaving.value, isFalse);
    });
  });

  group('saveDocument — update', () {
    test('sends the current field values plus the optimistic-lock token',
        () async {
      fakeProvider.updateTodoData = _canned(name: 'TD-0001', status: 'Closed');
      fakeProvider.getTodoData = _canned(name: 'TD-0001', status: 'Closed');

      final ctrl = ToDoFormController()
        ..mode.value = 'edit'
        ..name = 'TD-0001';
      ctrl.status.value = 'Closed';
      ctrl.priority.value = 'High';
      ctrl.descriptionController.text = 'x';

      await ctrl.saveDocument();

      expect(fakeProvider.lastUpdateName, 'TD-0001');
      expect(fakeProvider.lastUpdatePayload?['status'], 'Closed');
      expect(fakeProvider.lastUpdatePayload?['priority'], 'High');
      expect(fakeProvider.lastUpdatePayload?.containsKey('modified'), isTrue);
      expect(ctrl.saveResult.value, SaveResult.success);
    });

    test('re-entrancy guard skips a call already in flight', () async {
      final ctrl = ToDoFormController()
        ..mode.value = 'edit'
        ..name = 'TD-0001';
      ctrl.isSaving.value = true;

      await ctrl.saveDocument();

      expect(fakeProvider.lastUpdateName, isNull);
    });

    test('flags an error result and clears isSaving on a Dio failure',
        () async {
      fakeProvider.throwOnUpdate = DioException(
        requestOptions: RequestOptions(path: '/api/resource/ToDo/TD-0001'),
        response: Response(
          requestOptions:
              RequestOptions(path: '/api/resource/ToDo/TD-0001'),
          statusCode: 417,
          data: {
            'exception':
                'frappe.exceptions.ValidationError: Bad reference',
          },
        ),
      );

      final ctrl = ToDoFormController()
        ..mode.value = 'edit'
        ..name = 'TD-0001';
      ctrl.descriptionController.text = 'x';

      await ctrl.saveDocument();

      expect(ctrl.saveResult.value, SaveResult.error);
      expect(ctrl.isSaving.value, isFalse);
    });
  });

  group('field setters mark the form dirty (edit mode only)', () {
    test('setStatus updates the value and marks dirty', () {
      final ctrl = ToDoFormController()..mode.value = 'edit';
      expect(ctrl.isDirty.value, isFalse);

      ctrl.setStatus('Closed');

      expect(ctrl.status.value, 'Closed');
      expect(ctrl.isDirty.value, isTrue);
    });

    // Regression: dirty-tracking used to be a one-way latch that only ever
    // flipped false→true, so reverting a field to its fetched value still
    // left the form marked dirty. It's now a diff against the snapshot
    // taken right after fetchDocument, matching the DN/PO/PS convention.
    test('reverting a field to its fetched value clears isDirty again',
        () async {
      fakeProvider.getTodoData = _canned(priority: 'Medium');
      final ctrl = ToDoFormController()
        ..mode.value = 'edit'
        ..name = 'TD-0001';
      await ctrl.fetchDocument();
      expect(ctrl.isDirty.value, isFalse);

      ctrl.setPriority('High');
      expect(ctrl.isDirty.value, isTrue);

      ctrl.setPriority('Medium');
      expect(ctrl.isDirty.value, isFalse);
    });

    test('setReferenceType clears the previously selected reference name',
        () {
      final ctrl = ToDoFormController()..mode.value = 'edit';
      ctrl.referenceType.value = 'Delivery Note';
      ctrl.referenceName.value = 'DN-1';

      ctrl.setReferenceType('Purchase Order');

      expect(ctrl.referenceType.value, 'Purchase Order');
      expect(ctrl.referenceName.value, '');
    });

    test('clearReference resets both reference fields', () {
      final ctrl = ToDoFormController()..mode.value = 'edit';
      ctrl.referenceType.value = 'Delivery Note';
      ctrl.referenceName.value = 'DN-1';

      ctrl.clearReference();

      expect(ctrl.referenceType.value, '');
      expect(ctrl.referenceName.value, '');
    });

    test('setAllocatedTo / clearAllocatedTo track the display name', () {
      final ctrl = ToDoFormController()..mode.value = 'edit';

      ctrl.setAllocatedTo('ops@x.com', 'Ops Team');
      expect(ctrl.allocatedTo.value, 'ops@x.com');
      expect(ctrl.allocatedToDisplay.value, 'Ops Team');

      ctrl.clearAllocatedTo();
      expect(ctrl.allocatedTo.value, '');
      expect(ctrl.allocatedToDisplay.value, '');
    });

    test('view mode ignores every field mutation', () {
      final ctrl = ToDoFormController()..mode.value = 'view';

      ctrl.setStatus('Closed');
      ctrl.setPriority('High');
      ctrl.setAllocatedTo('ops@x.com', 'Ops Team');

      expect(ctrl.status.value, 'Open');
      expect(ctrl.priority.value, 'Medium');
      expect(ctrl.allocatedTo.value, '');
      expect(ctrl.isDirty.value, isFalse);
    });
  });

  group('searchReferenceDocs', () {
    test('no-ops when no reference type is selected', () async {
      final ctrl = ToDoFormController()..mode.value = 'edit';

      await ctrl.searchReferenceDocs('anything');

      expect(ctrl.isSearchingReference.value, isFalse);
      expect(ctrl.referenceSearchResults, isEmpty);
    });
  });

  group('enterEditMode', () {
    test('flips view to edit for a saved doc', () {
      final ctrl = ToDoFormController()..name = 'TD-0001';
      ctrl.mode.value = 'view';

      ctrl.enterEditMode();

      expect(ctrl.mode.value, 'edit');
      expect(ctrl.isEditable, isTrue);
    });

    test('no-ops when the doc is unsaved', () {
      final ctrl = ToDoFormController()..name = '';
      ctrl.mode.value = 'view';

      ctrl.enterEditMode();

      expect(ctrl.mode.value, 'view');
    });

    test('no-ops in new mode', () {
      final ctrl = ToDoFormController()..name = '';
      ctrl.mode.value = 'new';

      ctrl.enterEditMode();

      expect(ctrl.mode.value, 'new');
    });
  });

  group('v15 alignment', () {
    test('priority options match v15 todo.json (no Urgent)', () {
      expect(ToDoFormController.priorityOptions, ['Low', 'Medium', 'High']);
    });

    test('fetch converts a Desk HTML description to plain text and stays clean',
        () async {
      fakeProvider.getTodoData = _canned(
          description:
              '<div class="ql-editor read-mode"><p>Inventory: Price List</p></div>');
      final ctrl = ToDoFormController()..name = 'TD-0001';
      ctrl.mode.value = 'edit';

      await ctrl.fetchDocument();

      expect(ctrl.descriptionController.text, 'Inventory: Price List');
      expect(ctrl.isDirty.value, isFalse,
          reason: 'dirty snapshot must be taken AFTER the HTML conversion');
    });

    test('refuses to save when the description is empty (reqd:1 in v15)',
        () async {
      final ctrl = ToDoFormController()..name = '';
      ctrl.mode.value = 'new';
      ctrl.descriptionController.text = '   ';

      await ctrl.saveDocument();

      expect(fakeProvider.lastCreatePayload, isNull);
      expect(ctrl.saveResult.value, SaveResult.error);
      expect(ctrl.isSaving.value, isFalse);
    });
  });
}
