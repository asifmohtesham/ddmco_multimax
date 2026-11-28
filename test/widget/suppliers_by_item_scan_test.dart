// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_binding.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_screen.dart';

import '../helpers/auth_fakes.dart';

class _Api extends FakeApiProvider {
  final requests = <SuppliersByItemFilters>[];

  @override
  Future<SuppliersByItemReport> runSuppliersByItemReport(
    SuppliersByItemFilters filters,
  ) async {
    requests.add(filters);
    return const SuppliersByItemReport(nodes: []);
  }
}

class _Scans extends ScanService {
  _Scans(ApiProvider api) : super(apiProvider: api);

  final lookups = <String>[];
  Future<Item?> Function(String barcode) answer = (_) async => null;

  @override
  Future<Item?> resolveItemBarcode(String barcode) {
    lookups.add(barcode);
    return answer(barcode);
  }
}

Item _item(String code, {String? variantOf}) => Item(
  name: code,
  itemName: 'Item $code',
  itemCode: code,
  itemGroup: 'Products',
  variantOf: variantOf,
);

const _preset = SuppliersByItemFilters(
  items: ['OLD-ITEM'],
  suppliers: ['EDGE'],
  warehouses: ['Stores - KA'],
  includeDrafts: false,
  expandBom: true,
);

void main() {
  late _Api api;
  late _Scans scans;
  String? cameraCode;

  setUp(() {
    Get.testMode = true;
    cameraCode = null;
    api = _Api();
    Get.put<ApiProvider>(api, permanent: true);
    Get.put(AuthenticationController(), permanent: true);
    scans = _Scans(api);
    // The scanner's event channel has no platform side in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ddmco.multimax/scan'),
          (_) async => null,
        );
  });
  tearDown(Get.reset);

  Future<void> openReport(
    WidgetTester tester, {
    bool withScanService = true,
    SuppliersByItemFilters? filters = _preset,
    Size size = const Size(390, 780),
  }) async {
    if (withScanService) Get.put<ScanService>(scans);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(),
        getPages: [
          GetPage(
            name: AppRoutes.SUPPLIERS_BY_ITEM,
            page: () => SuppliersByItemScreen(scan: (_) async => cameraCode),
            binding: SuppliersByItemBinding(),
            transition: Transition.noTransition,
          ),
        ],
      ),
    );
    Get.toNamed(AppRoutes.SUPPLIERS_BY_ITEM, arguments: filters);
    await tester.pumpAndSettle();
  }

  final scanButton = find.byTooltip('Scan barcode');

  testWidgets('a camera scan of a variant replaces the Item selection and '
      'keeps the other filters', (tester) async {
    scans.answer = (_) async => _item('2002906', variantOf: 'ALS');
    cameraCode = ' 20029068 ';
    await openReport(tester);
    expect(api.requests, hasLength(1));

    await tester.tap(scanButton);
    await tester.pumpAndSettle();

    expect(scans.lookups, ['20029068']);
    expect(api.requests, hasLength(2));
    expect(api.requests.last.toJson(), {
      'variant_of': ['ALS'],
      'suppliers': ['EDGE'],
      'warehouses': ['Stores - KA'],
      'include_drafts': 0,
      'expand_bom': 1,
    });
    expect(find.text('Variant Of: ALS'), findsOneWidget);
    expect(find.textContaining('OLD-ITEM'), findsNothing);
  });

  testWidgets('a scan of a plain Item replaces a Variant Of selection', (
    tester,
  ) async {
    scans.answer = (_) async => _item('KIT');
    cameraCode = 'KIT-BARCODE';
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(variantOf: ['ALS']),
    );

    await tester.tap(scanButton);
    await tester.pumpAndSettle();

    expect(api.requests.last.toJson(), {
      'items': ['KIT'],
      'include_drafts': 1,
      'expand_bom': 0,
    });
  });

  testWidgets('an unmatched code says so and leaves the report alone', (
    tester,
  ) async {
    cameraCode = '99999999';
    await openReport(tester);

    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump();

    expect(find.text('No Item matches this barcode: 99999999'), findsOneWidget);
    expect(api.requests, hasLength(1));
    expect(find.text('Items: OLD-ITEM'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('a failed lookup says so and leaves the report alone', (
    tester,
  ) async {
    scans.answer = (_) async => throw StateError('offline');
    cameraCode = '20029068';
    await openReport(tester);

    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Could not look up this barcode. Try again.'),
      findsOneWidget,
    );
    expect(api.requests, hasLength(1));
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('a cancelled camera scan does nothing', (tester) async {
    await openReport(tester);

    await tester.tap(scanButton);
    await tester.pumpAndSettle();

    expect(scans.lookups, isEmpty);
    expect(api.requests, hasLength(1));
  });

  testWidgets('a hardware scan applies only while the report is on top', (
    tester,
  ) async {
    scans.answer = (_) async => _item('KIT');
    final wedge = Get.put(DataWedgeService());
    await openReport(tester);

    wedge.injectScan('KIT-BARCODE');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(scans.lookups, ['KIT-BARCODE']);
    expect(api.requests, hasLength(2));
    expect(api.requests.last.items, ['KIT']);

    Get.to<void>(() => const Scaffold(), transition: Transition.noTransition);
    await tester.pumpAndSettle();
    wedge.injectScan('OTHER');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(scans.lookups, ['KIT-BARCODE']);
    expect(api.requests, hasLength(2));
  });

  testWidgets('the scan button shows a spinner while the Item is looked up', (
    tester,
  ) async {
    scans.answer = (_) =>
        Future.delayed(const Duration(seconds: 1), () => _item('KIT'));
    cameraCode = 'KIT-BARCODE';
    await openReport(tester);

    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final button = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(button.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    expect(api.requests, hasLength(2));
  });

  testWidgets('the scan button leaves the header icons in place and the end '
      'of the list clear', (tester) async {
    await openReport(tester, filters: null, size: const Size(320, 640));

    for (final tooltip in ['Fields', 'Refresh report', 'Scan barcode']) {
      expect(
        find.byTooltip(tooltip).hitTestable(),
        findsOneWidget,
        reason: tooltip,
      );
    }
    expect(find.byTooltip('More actions'), findsNothing);
    final end = find.text('End of list');
    await tester.ensureVisible(end);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(end).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(FloatingActionButton)).top),
    );
  });

  testWidgets('there is no scan button without the scan service', (
    tester,
  ) async {
    await openReport(tester, withScanService: false);

    expect(find.byTooltip('Refresh report'), findsOneWidget);
    expect(scanButton, findsNothing);
  });
}
