import 'dart:async';

import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
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
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/common/services/awesome_bar_recent_store.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/home/widgets/rack_contents_sheet.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/report_fields_test_kit.dart';

const _rackCode = 'KA-WH-DXB1-121D';
const _itemJson = {
  'name': '1004883',
  'item_code': '1004883',
  'item_name': 'POUCH LEATHER',
};

Response _response(Object data, {int status = 200}) =>
    Response(requestOptions: RequestOptions(), data: data, statusCode: status);

class _FakeApiProvider implements ApiProvider {
  final posUploads = <String>[];

  @override
  bool Function() hasActiveSession = () => false;

  @override
  void Function() onSessionExpired = () {};

  @override
  String get baseUrl => 'https://example.test';

  @override
  int get rackWarehouseSession => 0;

  @override
  Future<Response> getDocument(String doctype, String name) async {
    expect(doctype, 'Item');
    expect(name, '1004883');
    return _response({'data': _itemJson});
  }

  @override
  Future<Response> getPosUpload(String name) async {
    posUploads.add(name);
    return _response({}, status: 404);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeScanService extends ScanService {
  final codes = <String>[];
  late ScanResult Function(String) resolve;

  @override
  Future<ScanResult> processScan(
    String barcode, {
    String? contextItemCode,
  }) async {
    codes.add(barcode);
    return resolve(barcode);
  }
}

class _FakeRackLoader extends ItemProvider {
  final queries = <({String warehouse, String? rack})>[];
  var rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>>? columns;
  final detailQueries = <List<String>>[];
  List<Map<String, dynamic>> details = [];
  Object? detailError;
  Object? error;
  Future<void>? pending;

  @override
  Future<Response> getWarehouseStock(
    String warehouse, {
    String? rack,
    DateTime? asOf,
  }) async {
    queries.add((warehouse: warehouse, rack: rack));
    await pending;
    if (error case final failure?) throw failure;
    return _response({
      'message': {'result': rows, if (columns != null) 'columns': columns},
    });
  }

  @override
  Future<Response> getItemFieldsByCodes(
    List<String> itemCodes,
    List<String> fields,
  ) async {
    detailQueries.add(itemCodes);
    if (detailError case final failure?) throw failure;
    return _response({'data': details});
  }
}

class _TrackingRackOwner extends ReportFieldsTestOwner {
  int watched = 0;
  int stopped = 0;

  @override
  Unsubscribe watch(void Function() onChange) {
    watched++;
    final stop = super.watch(onChange);
    return () {
      stopped++;
      stop();
    };
  }
}

void main() {
  late _FakeApiProvider api;
  late _FakeScanService scans;
  late _FakeRackLoader rackLoader;
  late HomeController home;
  late int startingScanRevision;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ddmco.multimax/scan'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({});
    api = _FakeApiProvider();
    Get.put<ApiProvider>(api);
    rackLoader = _FakeRackLoader();
    scans = _FakeScanService();
    Get.put<ItemProvider>(rackLoader);
    Get.put<ScanService>(scans);
    Get.put<JobCardProvider>(JobCardProvider());
    Get.put<UserProvider>(UserProvider());
    Get.put<PosUploadProvider>(PosUploadProvider());
    Get.put<StockEntryProvider>(StockEntryProvider());
    Get.put<DeliveryNoteProvider>(DeliveryNoteProvider());
    Get.put<ToDoProvider>(ToDoProvider());
    Get.put<StorageService>(StorageService.withStorage(null));
    Get.put<DataWedgeService>(DataWedgeService());
    Get.put<AuthenticationController>(AuthenticationController());
    Get.put<PermissionService>(PermissionService());
    // Construct directly to keep Dashboard startup requests out of these tests.
    home = HomeController();
    startingScanRevision = AwesomeBarRecentStore.scanRevision;
  });

  tearDown(() => Get.reset());

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(
          name: '/',
          page: () => const Scaffold(body: Text('Dashboard')),
        ),
        GetPage(
          name: AppRoutes.ITEM,
          page: () => const Scaffold(body: Text('Filtered Item List')),
        ),
      ],
    ),
  );

  Future<AwesomeBarOption> expectRecorded(
    String code,
    ScanType kind,
    ScanOutcome outcome, {
    int times = 1,
  }) async {
    expect(AwesomeBarRecentStore.scanRevision, startingScanRevision + times);
    final recent = (await AwesomeBarRecentStore.read()).single;
    expect(recent.value, code);
    expect(recent.scanKind, kind);
    expect(recent.scanOutcome, outcome);
    expect(home.isScanning.value, isFalse);
    return recent;
  }

  for (final batchNo in <String?>[null, '10048832-009']) {
    final kind = batchNo == null ? ScanType.item : ScanType.batch;
    testWidgets('${kind.name} opens the Item sheet and records once', (
      tester,
    ) async {
      const code = ' 10048832 ';
      scans.resolve = (raw) => ScanResult.item(
        rawCode: raw.trim(),
        itemData: Item.fromJson(_itemJson),
        batchNo: batchNo,
      );
      await mount(tester);
      await home.onScan(code);
      await tester.pumpAndSettle();

      expect(scans.codes, [code]);
      expect(find.byType(ItemFormScreen), findsOneWidget);
      expect(Get.find<ItemFormController>().highlightedBatchNo.value, batchNo);
      expect(
        (await expectRecorded(code, kind, ScanOutcome.ok)).label,
        'POUCH LEATHER',
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });
  }

  for (final detailsFailed in [false, true]) {
    testWidgets('rack scan keeps batch rows when Item details '
        '${detailsFailed ? 'fail' : 'load'}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(470, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      scans.resolve = ScanResult.rack;
      rackLoader.rows = [
        for (final (batch, qty) in [('B-01', 4), ('B-02', 6)])
          {
            ..._itemJson,
            'rack': _rackCode,
            'stock_uom': 'Each',
            'batch_no': batch,
            'bal_qty': qty,
          },
      ];
      rackLoader.columns = [
        {'fieldname': 'bal_qty', 'label': 'Bilanzmenge'},
        {'fieldname': 'batch_no', 'label': 'Charge'},
      ];
      rackLoader.details = [
        {..._itemJson, 'disabled': 1},
      ];
      if (detailsFailed) {
        rackLoader.detailError = StateError('Item unavailable');
      }
      await mount(tester);
      await home.onScan(_rackCode);
      await tester.pumpAndSettle();

      expect(rackLoader.queries, [
        (warehouse: 'WH-DXB1 - KA', rack: _rackCode),
      ]);
      expect(rackLoader.detailQueries, [
        ['1004883'],
      ]);
      expect(find.byType(RackContentsSheet), findsOneWidget);
      expect(
        (await expectRecorded(_rackCode, ScanType.rack, ScanOutcome.ok)).label,
        'Rack $_rackCode',
      );
      for (final (batch, qty) in [('B-01', '4'), ('B-02', '6')]) {
        final card = find
            .ancestor(of: find.text(batch), matching: find.byType(InkWell))
            .first;
        for (final text in [
          'POUCH LEATHER',
          '1004883',
          'Charge',
          'Bilanzmenge',
          qty,
        ]) {
          expect(
            find.descendant(of: card, matching: find.text(text)),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(of: card, matching: find.text('Disabled')),
          detailsFailed ? findsNothing : findsOneWidget,
        );
      }
      expect(
        find.text('Item details could not be loaded.'),
        detailsFailed ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('End of list · 2 items · Bilanzmenge 10 Each'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Fields'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(CheckboxListTile, 'Bilanzmenge'),
        findsOneWidget,
      );
      expect(rackLoader.queries, hasLength(1));
    });
  }

  testWidgets('rack drops results when its owner changes before modal mount', (
    tester,
  ) async {
    final owner = _TrackingRackOwner()..change('https://a.example', 'reader');
    Get.put<ReportOwnerSource>(owner);
    addTearDown(home.onClose);
    scans.resolve = ScanResult.rack;
    rackLoader.rows = [
      {..._itemJson, 'rack': _rackCode, 'bal_qty': 4},
    ];
    rackLoader.columns = [
      {'fieldname': 'bal_qty', 'label': 'Site A balance'},
    ];
    await mount(tester);
    await home.onScan(_rackCode);
    expect(find.byType(RackContentsSheet), findsNothing);

    owner.change('https://b.example', 'reader');
    await tester.pumpAndSettle();
    expect(find.byType(RackContentsSheet), findsOneWidget);
    expect(find.text('POUCH LEATHER'), findsNothing);
    expect(find.text('Reload rack contents'), findsOneWidget);
    await tester.tap(find.byTooltip('Fields'));
    await tester.pumpAndSettle();
    expect(find.text('Site A balance'), findsNothing);
  });

  testWidgets('Home stops listening while a rack scan is still pending', (
    tester,
  ) async {
    final owner = _TrackingRackOwner()..change('https://a.example', 'reader');
    Get.put<ReportOwnerSource>(owner);
    final pending = Completer<void>();
    rackLoader.pending = pending.future;
    scans.resolve = ScanResult.rack;
    rackLoader.rows = [
      {..._itemJson, 'rack': _rackCode, 'bal_qty': 4},
    ];
    await mount(tester);
    final scan = home.onScan(_rackCode);
    await tester.pump();
    expect(rackLoader.queries, hasLength(1));
    expect(owner.watched, 1);
    expect(owner.stopped, 0);

    home.onDelete();
    expect(owner.stopped, 1);
    owner.change('https://b.example', 'reader');
    pending.complete();
    await scan;
    await tester.pumpAndSettle();
    expect(owner.stopped, 1);
    expect(find.byType(RackContentsSheet), findsNothing);
  });

  testWidgets('variant opens the filtered list and records once', (
    tester,
  ) async {
    const code = 'Template';
    scans.resolve = ScanResult.variantOf;
    await mount(tester);
    await home.onScan(code);
    await tester.pumpAndSettle();

    expect(find.text('Filtered Item List'), findsOneWidget);
    expect(Get.arguments['filters'], {
      'variant_of': ['like', '%Template%'],
    });
    expect(
      (await expectRecorded(code, ScanType.variant_of, ScanOutcome.ok)).label,
      'Variants of Template',
    );
  });

  testWidgets('multiple matches open the selection sheet and record once', (
    tester,
  ) async {
    const code = 'Matches';
    scans.resolve = (raw) => ScanResult(
      type: ScanType.multiple,
      rawCode: raw,
      candidates: [Item.fromJson(_itemJson)],
    );
    await mount(tester);
    await home.onScan(code);
    await tester.pumpAndSettle();

    expect(find.byType(MultiItemSelectionSheet), findsOneWidget);
    await expectRecorded(code, ScanType.multiple, ScanOutcome.ok);
  });

  testWidgets('repeating a missing code updates its outcome in place', (
    tester,
  ) async {
    const code = 'Template';
    scans.resolve = (raw) =>
        ScanResult.error(raw, 'Missing', outcome: ScanOutcome.notFound);
    await mount(tester);
    await home.onScan(code);
    await tester.pumpAndSettle();

    expect(find.text('Not Found: Missing'), findsOneWidget);
    await expectRecorded(code, ScanType.error, ScanOutcome.notFound);

    scans.resolve = ScanResult.variantOf;
    await home.onScan(code);
    await tester.pumpAndSettle();

    expect(scans.codes, [code, code]);
    expect(find.text('Filtered Item List'), findsOneWidget);
    await expectRecorded(code, ScanType.variant_of, ScanOutcome.ok, times: 2);
  });

  testWidgets('an unresolved code records not found once', (tester) async {
    scans.resolve = (raw) => ScanResult(type: ScanType.unknown, rawCode: raw);
    await mount(tester);
    await home.onScan('missing');
    await tester.pumpAndSettle();

    expect(find.text('Not Found: Item not found'), findsOneWidget);
    await expectRecorded('missing', ScanType.unknown, ScanOutcome.notFound);
  });

  for (final throws in [false, true]) {
    testWidgets('${throws ? 'Thrown' : 'Returned'} scan error records once', (
      tester,
    ) async {
      scans.resolve = (raw) {
        if (throws) throw StateError('Network down');
        return ScanResult.error(raw, 'Network down');
      };
      await mount(tester);
      await home.onScan('offline');
      await tester.pumpAndSettle();

      expect(find.textContaining('Scan Error:'), findsOneWidget);
      await expectRecorded(
        'offline',
        throws ? ScanType.unknown : ScanType.error,
        ScanOutcome.error,
      );
    });
  }

  for (final (outcome, code, message) in [
    (ScanOutcome.invalid, 'KA-WH-DXB1', 'Invalid Rack QR'),
    (ScanOutcome.empty, _rackCode, 'Empty Rack'),
    (ScanOutcome.error, _rackCode, 'Rack Look-up Failed'),
  ]) {
    testWidgets('rack ${outcome.name} is recorded once', (tester) async {
      scans.resolve = ScanResult.rack;
      if (outcome == ScanOutcome.error) {
        rackLoader.error = StateError('Stock report unavailable');
      }
      await mount(tester);
      await home.onScan(code);
      await tester.pumpAndSettle();

      expect(find.textContaining(message), findsOneWidget);
      expect(
        rackLoader.queries,
        hasLength(outcome == ScanOutcome.invalid ? 0 : 1),
      );
      expect(home.isRackScanning.value, isFalse);
      await expectRecorded(code, ScanType.rack, outcome);
    });
  }

  testWidgets('empty input and POS Upload labels do not record', (
    tester,
  ) async {
    await mount(tester);
    await home.onScan('');
    await home.onScan('   ');
    await home.onScan(' ML-2026-02011 ');
    await tester.pumpAndSettle();

    expect(api.posUploads, ['ML-2026-02011']);
    expect(scans.codes, isEmpty);
    expect(AwesomeBarRecentStore.scanRevision, startingScanRevision);
    expect(await AwesomeBarRecentStore.read(), isEmpty);
  });
}
