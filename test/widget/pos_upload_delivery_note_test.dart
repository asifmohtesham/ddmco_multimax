import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pos_upload_delivery.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_binding.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_screen.dart';

import '../helpers/auth_fakes.dart';

const _uploadName = 'ML-POS-0001';
const _note = 'DN-0001';
const _revision = '2026-11-25 10:11:12.000001';
const _draft = 'DN-0002';
const _form = '/pos-upload-form';
const _fulfillment = '/fulfillment';

class _FakeApi extends FakeApiProvider {
  String status = 'To Deliver';
  DioException? transitionError;
  final statusWrites = <Map<String, dynamic>>[];
  List<String> submitted = [];
  List<String> drafts = [];
  bool denyList = false;
  bool denyDraftList = false;
  bool denyDetail = false;
  Future<Response>? nextNoteQuery;
  final noteReads = <String>[];
  final noteQueries =
      <({int limit, Map<String, dynamic>? filters, List<String>? fields})>[];

  Map<String, dynamic> get upload => {
    'name': _uploadName,
    'status': status,
    'modified': _revision,
  };

  @override
  Future<Response> getPosUpload(String name) async =>
      jsonResponse({'data': upload});

  @override
  Future<Response> callMethod(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    final error = transitionError;
    if (method == 'frappe.model.workflow.get_transitions' && error != null) {
      throw error;
    }
    return jsonResponse({'message': [], 'docinfo': <String, dynamic>{}});
  }

  @override
  Future<Response> hasDocPermission(
    String doctype,
    String name,
    String ptype,
  ) async => jsonResponse({'message': {'has_permission': 1}});

  @override
  Future<Response> getDocTypeMeta(String doctype) async => jsonResponse({
    'docs': [
      {
        'doctype': 'DocType',
        'name': 'POS Upload',
        'fields': [
          {'fieldname': 'status'},
        ],
      },
    ],
  });

  @override
  Future<Response> updateDocument(
    String doctype,
    String name,
    Map<String, dynamic> data,
  ) async {
    expect(doctype, 'POS Upload');
    expect(name, _uploadName);
    statusWrites.add(data);
    status = data['status'] as String;
    return jsonResponse({'data': upload});
  }

  @override
  Future<Response> getDocumentList(
    String doctype, {
    int limit = 20,
    int limitStart = 0,
    List<String>? fields,
    String? groupBy = '',
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
    Map<String, dynamic>? orFilters,
    List<List<dynamic>>? orFilterTuples,
    String orderBy = 'modified desc',
  }) async {
    if (doctype != 'Delivery Note') return jsonResponse({'data': []});
    noteQueries.add((limit: limit, filters: filters, fields: fields));
    if (denyList || (denyDraftList && filters?['docstatus'] == 0)) {
      throw httpError(403);
    }
    final pending = nextNoteQuery;
    nextNoteQuery = null;
    if (pending != null) return pending;
    final names = filters?['docstatus'] == 1 ? submitted : drafts;
    return jsonResponse({
      'data': [
        for (final name in names) {'name': name},
      ],
    });
  }

  @override
  Future<Response> getDeliveryNote(String name) async {
    noteReads.add(name);
    return denyDetail
        ? jsonResponse({}, status: 403)
        : jsonResponse({
            'data': {'name': name, 'docstatus': name == _draft ? 0 : 1},
          });
  }
}

class _OfflineFormController extends PosUploadFormController {
  @override
  Future<void> initRealtimeSync() async {}
}

class _OfflineDataWedge extends DataWedgeService {
  @override
  // The dashboard fixture does not subscribe to the native scanner channel.
  // ignore: must_call_super
  void onInit() {}
}

void _expectQuery(
  ({int limit, Map<String, dynamic>? filters, List<String>? fields}) query, {
  int docstatus = 1,
  int limit = 2,
}) {
  expect(query.limit, limit);
  expect(query.fields, ['name']);
  expect(query.filters, {
    'po_no': _uploadName,
    'docstatus': docstatus,
    'is_return': 0,
  });
}

void main() {
  late _FakeApi api;

  setUp(() {
    Get.testMode = true;
    api = _FakeApi();
    Get.put<ApiProvider>(api);
  });
  tearDown(Get.reset);

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: Text('Dashboard')),
        getPages: [
          GetPage(
            name: _form,
            page: () => const PosUploadFormScreen(),
            binding: PosUploadFormBinding(),
          ),
          GetPage(name: _fulfillment, page: () => const Scaffold()),
          GetPage(
            name: AppRoutes.DELIVERY_NOTE_FORM,
            page: () =>
                Scaffold(body: Text('Open DN ${Get.arguments['name']}')),
          ),
        ],
      ),
    );
  }

  Future<void> pumpForm(WidgetTester tester) async {
    await pumpApp(tester);
    Get.lazyPut<PosUploadFormController>(_OfflineFormController.new);
    Get.toNamed<void>(_form, arguments: {'name': _uploadName, 'mode': 'edit'});
    await tester.pumpAndSettle();
    _expectQuery(api.noteQueries.first);
  }

  Future<void> chooseFromDashboard(WidgetTester tester) async {
    Get.put<AuthenticationController>(AuthenticationController());
    Get.put<ItemProvider>(ItemProvider());
    Get.put<JobCardProvider>(JobCardProvider());
    Get.put<UserProvider>(UserProvider());
    Get.put<PosUploadProvider>(PosUploadProvider());
    Get.put<StockEntryProvider>(StockEntryProvider());
    Get.put<DeliveryNoteProvider>(DeliveryNoteProvider());
    Get.put<ToDoProvider>(ToDoProvider());
    Get.put<StorageService>(FakeStorageService());
    Get.put<ScanService>(ScanService());
    Get.put<DataWedgeService>(_OfflineDataWedge());
    final controller = HomeController();
    addTearDown(controller.barcodeController.dispose);
    await pumpApp(tester);
    Get.toNamed<void>(_fulfillment);
    await tester.pumpAndSettle();
    await controller.handleFulfillmentSelection(PosUpload.fromJson(api.upload));
    await tester.pumpAndSettle();
    _expectQuery(api.noteQueries.first);
  }

  testWidgets('form opens the unique submitted Delivery Note', (tester) async {
    api.submitted = [_note];
    await pumpForm(tester);

    final link = find.text('Delivery Note: $_note');
    expect(link, findsOneWidget);
    expect(api.noteReads, [_note]);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Open DN $_note'), findsOneWidget);
  });

  testWidgets('live missing workflow keeps manual status and the DN link', (
    tester,
  ) async {
    api
      ..status = 'Pending'
      ..submitted = [_note]
      ..transitionError = httpError(
        404,
        data: {
          'exc_type': 'DoesNotExistError',
          '_server_messages': jsonEncode([
            jsonEncode({
              'message': 'Workflow None not found',
              'as_table': false,
              'title': 'Message',
              'indicator': 'red',
              'raise_exception': 1,
              '__frappe_exc_id':
                  '0c32f0e51d8a5dc60aed8f54512c153e548436eff85d04a11cecb246',
            }),
          ]),
        },
      );
    await pumpForm(tester);

    expect(find.byTooltip('Retry delivery actions'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Workflow None not found'), findsNothing);
    for (final action in PosDeliveryAction.values) {
      expect(find.byKey(ValueKey(action)), findsNothing);
    }
    final dropdown = find.byType(DropdownButton<String>);
    final statusField = tester.widget<DropdownButton<String>>(dropdown);
    expect(statusField.onChanged, isNotNull);
    expect(statusField.items!.map((item) => item.value), [
      'Pending',
      'In Progress',
      'Completed',
      'Cancelled',
    ]);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Progress').last);
    await tester.pumpAndSettle();
    expect(api.statusWrites, [
      {'status': 'In Progress', 'modified': _revision},
    ]);
    expect(
      tester.widget<DropdownButton<String>>(dropdown).value,
      'In Progress',
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final link = find.text('Delivery Note: $_note');
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Open DN $_note'), findsOneWidget);
  });

  testWidgets('an unrelated missing document keeps workflow retry available', (
    tester,
  ) async {
    api
      ..status = 'Pending'
      ..submitted = [_note]
      ..transitionError = httpError(
        404,
        data: {
          'exc_type': 'DoesNotExistError',
          '_server_messages': jsonEncode([
            jsonEncode({'message': 'POS Upload $_uploadName not found'}),
          ]),
        },
      );
    await pumpForm(tester);

    expect(find.byTooltip('Retry delivery actions'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged,
      isNull,
    );
  });

  testWidgets('dashboard opens the unique submitted Delivery Note', (
    tester,
  ) async {
    api.submitted = [_note];
    await chooseFromDashboard(tester);
    expect(find.text('Open DN $_note'), findsOneWidget);
  });

  for (final (description, notes, denied, notice) in [
    ('zero matches', <String>[], false, 'No submitted Delivery Note'),
    (
      'multiple matches',
      [_note, _draft],
      false,
      'Multiple submitted Delivery Notes. Ask Stock Manager to reconcile them.',
    ),
    ('permission denied', <String>[], true, 'Unable to read Delivery Notes'),
  ]) {
    testWidgets('form shows $description with no DN link', (tester) async {
      api.submitted = notes;
      api.denyList = denied;
      await pumpForm(tester);

      expect(find.text(notice), findsOneWidget);
      expect(api.noteQueries, hasLength(1));
      expect(api.noteReads, isEmpty);
      expect(find.textContaining('Delivery Note: DN'), findsNothing);
    });

    testWidgets('dashboard shows $description with no DN link', (tester) async {
      api.submitted = notes;
      api.denyList = denied;
      await chooseFromDashboard(tester);

      expect(find.text(notice), findsOneWidget);
      expect(api.noteQueries, hasLength(1));
      expect(find.textContaining('Open DN'), findsNothing);
    });
  }

  testWidgets('form suppresses the DN link when the detail read fails', (
    tester,
  ) async {
    api.submitted = [_note];
    api.denyDetail = true;
    await pumpForm(tester);

    expect(find.text('Unable to read Delivery Notes'), findsOneWidget);
    expect(find.text('Delivery Note: $_note'), findsNothing);
  });

  testWidgets('POS reload supersedes an older submitted DN lookup', (
    tester,
  ) async {
    api.submitted = [_note];
    await pumpForm(tester);
    expect(find.text('Delivery Note: $_note'), findsOneWidget);

    final controller = Get.find<PosUploadFormController>();
    final pending = Completer<Response>();
    api.nextNoteQuery = pending.future;
    final stale = controller.fetchLinkedDocument();
    api.submitted = [_note, _draft];
    await controller.fetchPosUpload();
    pending.complete(
      jsonResponse({
        'data': [
          {'name': _note},
        ],
      }),
    );
    await stale;
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Multiple submitted Delivery Notes'),
      findsOneWidget,
    );
    expect(find.text('Delivery Note: $_note'), findsNothing);
    expect(api.noteReads, [_note]);
  });

  testWidgets('form retains a separate draft link during preparation', (
    tester,
  ) async {
    api.status = 'In Progress';
    api.drafts = [_draft];
    await pumpForm(tester);

    _expectQuery(api.noteQueries.last, docstatus: 0, limit: 1);
    expect(find.text('Draft Delivery Note: $_draft'), findsOneWidget);
  });

  testWidgets('dashboard resumes a draft only during preparation', (
    tester,
  ) async {
    api.status = 'Pending';
    api.drafts = [_draft];
    await chooseFromDashboard(tester);

    _expectQuery(api.noteQueries.last, docstatus: 0, limit: 1);
    expect(find.text('Open DN $_draft'), findsOneWidget);
  });

  testWidgets('dashboard does not start a new DN after a failed draft read', (
    tester,
  ) async {
    api.status = 'Pending';
    api.denyDraftList = true;
    await chooseFromDashboard(tester);

    _expectQuery(api.noteQueries.last, docstatus: 0, limit: 1);
    expect(find.text('Unable to read Delivery Notes'), findsOneWidget);
    expect(find.textContaining('Open DN'), findsNothing);
  });
}
