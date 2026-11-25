import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/link_title_cache.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';

import '../support/report_fields_test_kit.dart';

// An Employee filter shows and searches by employee name; the controller —
// and so the report filter — keeps the Employee ID.

const _employees = [
  {'name': 'HR-EMP-00007', 'employee_name': 'Jawwad Bilgi'},
  {'name': 'HR-EMP-00011', 'employee_name': 'Arif Khan'},
];

class _FakeApi extends ApiProvider {
  final listCalls = <Map<String, Object?>>[];
  Future<Iterable<Map<String, String>>> Function()? readEmployees;

  @override
  Future<Response> getDocTypeMeta(String doctype) async => Response(
    requestOptions: RequestOptions(path: '/'),
    statusCode: 200,
    data: const {'docs': []},
  );

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
    listCalls.add({
      'doctype': doctype,
      'fields': fields,
      'filters': filters,
      'orFilters': orFilters,
      'orderBy': orderBy,
    });
    Iterable<Map<String, String>> rows =
        await readEmployees?.call() ?? _employees;
    final name = filters?['name'];
    if (name is String) rows = rows.where((r) => r['name'] == name);
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/$doctype'),
      statusCode: 200,
      data: {'data': rows.toList()},
    );
  }
}

class _FakeStorage extends StorageService {
  _FakeStorage() : super.withStorage(null);
  @override
  String? getBaseUrl() => null;
}

const _field = ReportFilterField(
  key: 'employee',
  label: 'Employee',
  type: ReportFilterType.doctypeLink,
  linkDoctype: 'Employee',
  linkTitleField: 'employee_name',
);

void main() {
  late _FakeApi api;
  late TextEditingController employee;
  late ReportFieldsTestOwner owner;
  late ScopedReportFieldsController titleOwner;
  const scope = (site: 'https://a.example', user: 'employee-reader');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => r'C:\temp\test_cookies',
        );
  });

  setUp(() {
    Get.testMode = true;
    LinkTitleCache.clear();
    Get.put<StorageService>(_FakeStorage());
    api = Get.put<ApiProvider>(_FakeApi()) as _FakeApi;
    employee = TextEditingController();
    owner = ReportFieldsTestOwner()..change(scope.site, scope.user);
    titleOwner = ScopedReportFieldsController(
      definition: const ReportFieldsDefinition(
        id: 'link-test',
        fields: [],
        sections: [],
        alwaysShown: '',
      ),
      owner: owner,
      store: null,
    );
  });
  tearDown(() {
    titleOwner.dispose();
    employee.dispose();
    Get.reset();
  });

  Future<void> open(WidgetTester tester) async {
    await titleOwner.bind();
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => FilledButton(
              onPressed: () => showReportFilterSheet(
                context: ctx,
                title: 'Filters',
                fields: const [_field],
                controllers: {'employee': employee},
                onRun: () {},
                titleOwner: titleOwner,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a preset ID is shown as the employee name, ID beneath', (
    tester,
  ) async {
    employee.text = 'HR-EMP-00007';
    await open(tester);

    expect(find.text('Jawwad Bilgi'), findsOneWidget);
    expect(find.text('HR-EMP-00007'), findsOneWidget); // helper text
    expect(employee.text, 'HR-EMP-00007');
    expect(api.listCalls.single['filters'], {'name': 'HR-EMP-00007'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picker lists names with IDs, searches both, keeps the ID', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.widgetWithText(TextField, 'Employee'));
    await tester.pumpAndSettle();

    // Listed by name, ordered by name, ID as the subtitle.
    final initial = api.listCalls.last;
    expect(initial['fields'], ['name', 'employee_name']);
    expect(initial['orderBy'], 'employee_name asc');
    expect(find.widgetWithText(ListTile, 'Arif Khan'), findsOneWidget);
    expect(find.text('HR-EMP-00011'), findsOneWidget);
    expect(find.text('Search Employee by name or ID…'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search Employee by name or ID…'),
      'jaw',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(api.listCalls.last['orFilters'], {
      'name': ['like', '%jaw%'],
      'employee_name': ['like', '%jaw%'],
    });

    await tester.tap(find.widgetWithText(ListTile, 'Jawwad Bilgi'));
    await tester.pumpAndSettle();

    expect(employee.text, 'HR-EMP-00007'); // the report filters by the ID
    expect(find.widgetWithText(TextField, 'Jawwad Bilgi'), findsOneWidget);
    expect(
      LinkTitleCache.peek('Employee', 'HR-EMP-00007', scope: scope),
      'Jawwad Bilgi',
    );
    expect(tester.takeException(), isNull);
  });

  group('LinkTitleCache', () {
    test(
      'parseLinkOptions drops blank names; display falls back to the ID',
      () {
        final options = parseLinkOptions(
          jsonDecode(
            jsonEncode([
              {'name': 'A', 'employee_name': 'Alpha'},
              {'name': 'B', 'employee_name': ''},
              {'name': 'C', 'employee_name': 'C'},
              {'name': ' ', 'employee_name': 'Ghost'},
              'junk',
            ]),
          ),
          'employee_name',
        );
        expect(options.map((o) => o.display), ['Alpha', 'B', 'C']);
        expect(options.map((o) => o.hasDistinctTitle), [true, false, false]);
      },
    );

    test(
      'unknown IDs read as themselves; concurrent lookups share a request',
      () async {
        expect(
          LinkTitleCache.peek('Employee', 'HR-EMP-00011', scope: scope),
          isNull,
        );
        final results = await Future.wait([
          LinkTitleCache.resolve(
            'Employee',
            'employee_name',
            'HR-EMP-00011',
            api,
            scope: scope,
          ),
          LinkTitleCache.resolve(
            'Employee',
            'employee_name',
            'HR-EMP-00011',
            api,
            scope: scope,
          ),
        ]);
        expect(results, ['Arif Khan', 'Arif Khan']);
        expect(api.listCalls, hasLength(1));
        expect(
          LinkTitleCache.peek('Employee', 'HR-EMP-00011', scope: scope),
          'Arif Khan',
        );
      },
    );
  });

  testWidgets('a mounted employee field separates stale and current lookups', (
    tester,
  ) async {
    final first = Completer<Iterable<Map<String, String>>>();
    final second = Completer<Iterable<Map<String, String>>>();
    final reads = [first.future, second.future];
    api.readEmployees = () => reads.removeAt(0);
    employee.text = 'HR-EMP-00007';
    await open(tester);
    expect(find.widgetWithText(TextField, 'HR-EMP-00007'), findsOneWidget);

    const newSite = 'https://b.example';
    owner.change(newSite, scope.user);
    await tester.pumpAndSettle();
    expect(api.listCalls, hasLength(2));
    first.complete(_employees);
    await tester.pumpAndSettle();
    expect(find.text('Jawwad Bilgi'), findsNothing);
    expect(find.widgetWithText(TextField, 'HR-EMP-00007'), findsOneWidget);
    second.complete([
      {'name': 'HR-EMP-00007', 'employee_name': 'Site B Employee'},
    ]);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Site B Employee'), findsOneWidget);

    const newUser = 'other-reader';
    api.readEmployees = () async => [
      {'name': 'HR-EMP-00007', 'employee_name': 'Other User Employee'},
    ];
    owner.change(newSite, newUser);
    await tester.pumpAndSettle();
    expect(api.listCalls, hasLength(3));
    expect(find.text('Site B Employee'), findsNothing);
    expect(
      find.widgetWithText(TextField, 'Other User Employee'),
      findsOneWidget,
    );
  });

  testWidgets(
    'an open employee picker only publishes results for its current site',
    (tester) async {
      final first = Completer<Iterable<Map<String, String>>>();
      final second = Completer<Iterable<Map<String, String>>>();
      final reads = [first.future, second.future];
      api.readEmployees = () => reads.removeAt(0);
      await open(tester);
      await tester.tap(find.widgetWithText(TextField, 'Employee'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.listCalls, hasLength(1));

      const newSite = 'https://b.example';
      owner.change(newSite, scope.user);
      await tester.pump();
      expect(api.listCalls, hasLength(2));
      first.complete(_employees);
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Jawwad Bilgi'), findsNothing);
      expect(
        LinkTitleCache.peek(
          'Employee',
          'HR-EMP-00007',
          scope: (site: newSite, user: scope.user),
        ),
        isNull,
      );
      second.complete([
        {'name': 'HR-EMP-00007', 'employee_name': 'Site B Employee'},
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Site B Employee'));
      await tester.pumpAndSettle();
      expect(employee.text, 'HR-EMP-00007');
      expect(find.widgetWithText(TextField, 'Site B Employee'), findsOneWidget);
    },
  );
}
