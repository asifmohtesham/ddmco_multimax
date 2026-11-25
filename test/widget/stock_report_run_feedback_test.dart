import 'dart:async';

// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_pages.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_binding.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_controller.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_screen.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

import '../support/report_fields_test_kit.dart';

typedef _StockBalanceResult = ({
  List<Map<String, dynamic>> columns,
  List<Map<String, dynamic>> rows,
});

class _StockApi extends ApiProvider {
  final batchItems = <String>[];
  final stockWarehouses = <List<String>>[];
  Completer<void>? pending;

  @override
  Future<BatchWiseBalanceResult> getBatchWiseBalanceReport({
    required String itemCode,
    String? batchNo,
    String? warehouse,
    String? fromDate,
    String? toDate,
  }) async {
    batchItems.add(itemCode);
    await pending?.future;
    return ApiProvider.parseBatchWiseBalanceReport({
      'columns': [
        {'fieldname': 'item', 'label': 'Item'},
        {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
      ],
      'result': [
        {'item': itemCode, 'balance_qty': 3},
      ],
    });
  }

  @override
  Future<_StockBalanceResult> getStockBalanceReport({
    required String fromDate,
    required String toDate,
    List<String>? itemCodes,
    List<String>? warehouses,
    String? itemGroup,
    String? warehouseType,
    String? rack,
    String? includeUom,
    bool showDimensionWise = false,
    bool showVariantAttributes = false,
    bool showStockAgeing = false,
    bool ignoreClosingBalance = false,
    bool includeZeroStockItems = false,
  }) async {
    stockWarehouses.add([...?warehouses]);
    await pending?.future;
    return (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
  }

  @override
  Future<List<String>> searchLinkOptions(
    String doctype, {
    String query = '',
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async => doctype == 'Warehouse' ? ['Warehouse B'] : [];
}

class _StockPermissions extends PermissionService {
  final enabled = true.obs;

  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) =>
      enabled.value &&
      permType == 'report' &&
      const {'Batch', 'Stock Entry'}.contains(doctype);
}

class _StockStorage extends ReportFieldsTestStorage {
  final _ownerListeners = <VoidCallback>{};
  String? site;
  User? user;

  @override
  String? getBaseUrl() => site;

  @override
  User? getUser() => user;

  @override
  Future<void> saveBaseUrl(String url) async {
    site = url;
    for (final listener in _ownerListeners.toList()) {
      listener();
    }
  }

  @override
  VoidCallback watchReportFieldsOwner(VoidCallback onChange) {
    _ownerListeners.add(onChange);
    return () => _ownerListeners.remove(onChange);
  }

  @override
  bool getSbHideEmpty() => false;

  @override
  bool getSbShowImages() => true;
}

void main() {
  late _StockApi api;
  late ReportFieldsTestOwner owner;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => r'C:\temp\stock_report_run_feedback',
        );
  });

  setUp(() {
    Get.testMode = true;
    api = Get.put<ApiProvider>(_StockApi(), permanent: true) as _StockApi;
    Get.put<StorageService>(_StockStorage(), permanent: true);
    Get.put(AuthenticationController(), permanent: true);
    Get.put<PermissionService>(_StockPermissions(), permanent: true);
    owner = ReportFieldsTestOwner();
    Get.put<ReportOwnerSource>(owner, permanent: true);
  });
  tearDown(Get.reset);

  Future<void> mount(WidgetTester tester, String route) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(),
        getPages: [
          for (final page in AppPages.routes)
            if (page.name == AppRoutes.BATCH_WISE_BALANCE ||
                page.name == AppRoutes.STOCK_BALANCE)
              page,
        ],
      ),
    );
    unawaited(Get.toNamed<void>(route));
    await tester.pumpAndSettle();
  }

  BatchWiseBalanceController batch(WidgetTester tester) {
    final route = ModalRoute.of(
      tester.element(find.byType(BatchWiseBalanceScreen)),
    );
    return Get.find(tag: BatchWiseBalanceBinding.tagForRoute(route));
  }

  Future<void> finishAnimation(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(
      find.byTooltip(RegExp(r'filters? active|^Filter$')).hitTestable().first,
    );
    await finishAnimation(tester);
  }

  final runButton = find.widgetWithText(FilledButton, 'Run Report');

  void expectBusyRun(WidgetTester tester) {
    expect(tester.widget<FilledButton>(runButton).onPressed, isNull);
    expect(
      find.descendant(
        of: runButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  }

  testWidgets('drawer round trip gives stacked Batch routes separate state', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 0.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(tester, AppRoutes.BATCH_WISE_BALANCE);
    final driver = WidgetReportFieldsDriver(tester, owner);
    final first = batch(tester);
    first.itemCodeController.text = 'First item';
    await first.runReport();
    await tester.pumpAndSettle();
    await driver.openFields();
    await driver.setVisible('balance_qty', false);
    await driver.dismiss();

    Future<void> selectInDrawer(String name) async {
      await tester.tap(find.byTooltip('Open navigation menu').hitTestable());
      await tester.pumpAndSettle();
      final drawer = find.byType(Drawer);
      final entry = find.descendant(of: drawer, matching: find.text(name));
      if (entry.evaluate().isEmpty) {
        await tester.tap(
          find.descendant(of: drawer, matching: find.text('Stock')),
        );
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
    }

    await selectInDrawer('Stock Balance');
    await selectInDrawer('Batch-Wise Balance History');
    final second = batch(tester);
    expect(second, isNot(same(first)));
    expect(second.scroll, isNot(same(first.scroll)));
    expect(first.scroll.positions, hasLength(1));
    expect(second.scroll.positions, hasLength(1));
    expect(second.reportData, isEmpty);
    second.itemCodeController.text = 'Second item';
    await second.runReport();
    await tester.pumpAndSettle();
    await driver.openFields();
    expect((await driver.read('balance_qty')).value, isTrue);
    await driver.setVisible('balance_qty', false);
    await driver.reset();
    await driver.dismiss();
    expect(second.fields.shows('balance_qty'), isTrue);
    expect(first.fields.shows('balance_qty'), isFalse);

    Get.back<void>();
    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(batch(tester), same(first));
    expect(find.text('First item'), findsOneWidget);
    expect(find.text('Second item'), findsNothing);
    await driver.openFields();
    expect((await driver.read('balance_qty')).value, isFalse);
    await driver.dismiss();
  });

  testWidgets('Batch retains a second Item selection while Run is busy', (
    tester,
  ) async {
    await mount(tester, AppRoutes.BATCH_WISE_BALANCE);
    final controller = batch(tester);
    controller.itemCodeController.text = 'Item A';
    await tester.tap(find.text('Set Filters'));
    await tester.pumpAndSettle();
    api.pending = Completer<void>();
    await tester.tap(runButton);
    await finishAnimation(tester);
    await openFilters(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Item Code *'),
      'Item B',
    );
    await finishAnimation(tester);
    expectBusyRun(tester);
    expect(api.batchItems, ['Item A']);

    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(controller.itemCodeController.text, 'Item B');
    await tester.tap(runButton);
    await tester.pumpAndSettle();
    expect(api.batchItems, ['Item A', 'Item B']);
  });

  testWidgets('a canonical-equivalent site keeps the loaded Batch report', (
    tester,
  ) async {
    final storage = Get.find<StorageService>() as _StockStorage;
    final auth = Get.find<AuthenticationController>();
    storage.user = User.fromJson({'name': 'buyer@example.com'});
    await storage.saveBaseUrl('https://erp.example/Tenant');
    auth.currentUser.value = storage.user;
    auth.isAuthenticated.value = true;
    Get.replace<ReportOwnerSource>(
      StorageReportOwnerSource(auth: auth, storage: storage),
    );
    Get.put<ReportFieldsStore>(
      ScopedReportFieldsStore(
        database: ReportFieldsTestConfig(),
        storage: storage,
      ),
    );
    await mount(tester, AppRoutes.BATCH_WISE_BALANCE);
    final controller = batch(tester);
    controller.itemCodeController.text = 'Keep this row';
    await controller.runReport();
    await tester.pumpAndSettle();
    expect(find.text('Keep this row'), findsOneWidget);

    await storage.saveBaseUrl('https://ERP.EXAMPLE:443/Tenant/');
    await tester.pumpAndSettle();
    expect(find.text('Keep this row'), findsOneWidget);
    expect(controller.hasRun.value, isTrue);
    expect(api.batchItems, ['Keep this row']);

    await storage.saveBaseUrl('https://erp.example/tenant');
    await tester.pumpAndSettle();
    expect(find.text('Keep this row'), findsNothing);
    expect(find.text('Set Filters'), findsOneWidget);
  });

  testWidgets('invalidated Batch request clears the results spinner', (
    tester,
  ) async {
    await mount(tester, AppRoutes.BATCH_WISE_BALANCE);
    final controller = batch(tester);
    controller.itemCodeController.text = 'Item A';
    api.pending = Completer<void>();
    unawaited(controller.runReport());
    await finishAnimation(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final itemChip = find.widgetWithText(FilterChipWidget, 'Item: Item A');
    final delete = find.descendant(
      of: itemChip,
      matching: find.byIcon(Icons.close),
    );
    await tester.ensureVisible(delete);
    await finishAnimation(tester);
    await tester.tap(delete);
    await finishAnimation(tester);
    expect(itemChip, findsNothing);

    api.pending!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Set Filters'), findsOneWidget);
    expect(controller.reportData, isEmpty);
  });

  testWidgets('Stock Balance retains another warehouse while Run is busy', (
    tester,
  ) async {
    await mount(tester, AppRoutes.STOCK_BALANCE);
    final controller = Get.find<StockBalanceController>();
    controller.warehouseController.text = 'Warehouse A';
    api.pending = Completer<void>();
    unawaited(controller.runReport());
    await finishAnimation(tester);
    await openFilters(tester);
    final field = find.ancestor(
      of: find.text('Warehouses'),
      matching: find.byType(InputDecorator),
    );
    final picker = find.descendant(
      of: field,
      matching: find.byType(ActionChip),
    );
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await finishAnimation(tester);
    await tester.tap(find.text('Warehouse B').hitTestable());
    await finishAnimation(tester);
    await tester.tap(find.text('Done').hitTestable());
    await finishAnimation(tester);
    expectBusyRun(tester);
    expect(api.stockWarehouses, [
      ['Warehouse A'],
    ]);

    api.pending!.complete();
    await tester.pumpAndSettle();
    await tester.tap(runButton);
    await tester.pumpAndSettle();
    expect(api.stockWarehouses, [
      ['Warehouse A'],
      ['Warehouse A', 'Warehouse B'],
    ]);
  });
}
