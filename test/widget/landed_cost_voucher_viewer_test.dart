import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_screen.dart';
import 'package:multimax/app/modules/landed_cost_voucher/landed_cost_voucher_controller.dart';
import 'package:multimax/app/modules/landed_cost_voucher/landed_cost_voucher_screen.dart';

final _voucher = {
  'name': 'MAT-LCV-2026-00001',
  'company': 'KA',
  'docstatus': 1,
  'status': 'Submitted',
  'posting_date': '2026-09-26',
  'distribute_charges_based_on': 'Qty',
  'total_taxes_and_charges': 150.0,
  'purchase_receipts': [
    {'receipt_document_type': 'Purchase Receipt', 'receipt_document': 'MAT-PRE-0001',
      'supplier': 'Acme', 'grand_total': 1000.0},
  ],
  'items': [
    {'item_code': 'WATCH-001', 'description': 'Steel watch',
      'receipt_document_type': 'Purchase Receipt', 'receipt_document': 'MAT-PRE-0001',
      'qty': 10, 'rate': 100.0, 'amount': 1000.0, 'applicable_charges': 150.0},
  ],
  'taxes': [
    {'description': 'Freight', 'amount': 150.0, 'expense_account': 'Freight - KA'},
  ],
};

Response<dynamic> _ok(dynamic data) => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {'data': data},
    );

class _FakeLcvProvider implements LandedCostVoucherProvider {
  @override
  Future<Response> getLandedCostVouchers({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async =>
      _ok([_voucher]);

  @override
  Future<Response> getLandedCostVoucher(String name) async => _ok(_voucher);
}

class _StubPermissionService extends PermissionService {
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => true;
}

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(AuthenticationController());
    Get.put<PermissionService>(_StubPermissionService());
    Get.put<LandedCostVoucherProvider>(_FakeLcvProvider());
  });
  tearDown(Get.reset);

  test('model keeps each item\'s allocated charge', () {
    final v = LandedCostVoucher.fromJson(_voucher);
    expect(v.items.single.applicableCharges, 150.0);
    expect(v.totalTaxesAndCharges, 150.0);
    expect(v.purchaseReceipts.single.receiptDocument, 'MAT-PRE-0001');
  });

  test('vouchers are reachable from global search', () {
    // Search targets are derived from kNavCatalog entries that carry a
    // formRoute; without one the voucher silently drops out of search.
    final target = kGlobalSearchTargets
        .where((t) => t.doctype == 'Landed Cost Voucher')
        .single;
    expect(target.route, AppRoutes.LANDED_COST_VOUCHER_FORM);
  });

  testWidgets('list is view-only and follows the list conventions',
      (tester) async {
    Get.put(LandedCostVoucherController());
    await tester.pumpWidget(const GetMaterialApp(home: LandedCostVoucherScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('MAT-LCV-2026-00001'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(ListEndFooter), findsOneWidget);
  });

  testWidgets('voucher view has no save and shows allocated charges',
      (tester) async {
    Get.put(LandedCostVoucherFormController());
    await tester.pumpWidget(
        const GetMaterialApp(home: LandedCostVoucherFormScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final header =
        tester.widget<DocTypeFormHeader>(find.byType(DocTypeFormHeader));
    expect(header.onSave, isNull);
    expect(header.canSave, isFalse);

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();
    expect(find.text('WATCH-001'), findsOneWidget);
    expect(find.textContaining('150'), findsWidgets);
  });
}
