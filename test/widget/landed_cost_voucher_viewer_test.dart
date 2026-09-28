import 'dart:async';

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
import '../helpers/fake_lcv_provider.dart';

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
    Get.put<LandedCostVoucherProvider>(FakeLcvProvider());
  });
  tearDown(Get.reset);

  test('model keeps each item\'s allocated charge', () {
    final v = LandedCostVoucher.fromJson(sampleLcv());
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

  testWidgets('a submitted voucher has no save and shows allocated charges',
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

  testWidgets('a draft shows editing controls; save appears once dirty',
      (tester) async {
    (Get.find<LandedCostVoucherProvider>() as FakeLcvProvider).voucher =
        sampleLcv(docstatus: 0);
    final c = Get.put(LandedCostVoucherFormController(
        name: 'MAT-LCV-2026-00001', mode: 'edit', defaultCompany: 'KA'));
    await tester.pumpWidget(
        const GetMaterialApp(home: LandedCostVoucherFormScreen()));
    await tester.pumpAndSettle();

    DocTypeFormHeader header() =>
        tester.widget<DocTypeFormHeader>(find.byType(DocTypeFormHeader));
    expect(header().canSave, isFalse);
    expect(header().canSubmit, isTrue);

    await tester.tap(find.text('Purchase Receipts'));
    await tester.pumpAndSettle();
    expect(find.text('Add Purchase Receipt'), findsOneWidget);

    await tester.tap(find.text('Taxes'));
    await tester.pumpAndSettle();
    expect(find.text('Add Charge'), findsOneWidget);

    c.removeCharge(0);
    await tester.pump();
    expect(header().canSave, isTrue);
    expect(header().canSubmit, isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a manually distributed draft explains why it is read-only',
      (tester) async {
    (Get.find<LandedCostVoucherProvider>() as FakeLcvProvider).voucher =
        sampleLcv(docstatus: 0, distribute: 'Distribute Manually');
    Get.put(LandedCostVoucherFormController(
        name: 'MAT-LCV-2026-00001', mode: 'edit', defaultCompany: 'KA'));
    await tester.pumpWidget(
        const GetMaterialApp(home: LandedCostVoucherFormScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('distributed manually'), findsOneWidget);
    final header =
        tester.widget<DocTypeFormHeader>(find.byType(DocTypeFormHeader));
    expect(header.onSave, isNull);
    expect(header.canSubmit, isFalse);
    await tester.tap(find.text('Taxes'));
    await tester.pumpAndSettle();
    expect(find.text('Add Charge'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  // ── Fix round 1, Finding 1 (round 1b: stay visible, disable) ────────────

  testWidgets(
      'edit controls stay visible but disable while a save is in flight',
      (tester) async {
    final fake = Get.find<LandedCostVoucherProvider>() as FakeLcvProvider;
    fake.voucher = sampleLcv(docstatus: 0);
    final c = Get.put(LandedCostVoucherFormController(
        name: 'MAT-LCV-2026-00001', mode: 'edit', defaultCompany: 'KA'));
    await tester.pumpWidget(
        const GetMaterialApp(home: LandedCostVoucherFormScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Taxes'));
    await tester.pumpAndSettle();

    OutlinedButton addChargeButton() => tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Add Charge'));
    expect(addChargeButton().onPressed, isNotNull);

    // Make the draft dirty (still valid — receipts/charges non-empty) and
    // hold the save mid-flight.
    c.upsertCharge(LandedCostTaxesAndCharges(
      description: 'Insurance',
      amount: 30,
      expenseAccount: 'Insurance - KA',
      exchangeRate: 1,
      baseAmount: 30,
    ));
    await tester.pump();
    fake.saveGate = Completer<void>();
    final saveFuture = c.saveDocument();
    await tester.pump();

    expect(c.isSaving.value, isTrue);
    // The controller silently rejects mutations while saving (Task 3), so
    // the "Add Charge" button must stay visible (no layout jump) but its
    // onPressed must be disabled — not merely a `canSave`-style advisory
    // state that leaves it tappable.
    expect(find.widgetWithText(OutlinedButton, 'Add Charge'), findsOneWidget);
    expect(addChargeButton().onPressed, isNull);

    fake.saveGate!.complete();
    await saveFuture;
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Add Charge'), findsOneWidget);
    expect(addChargeButton().onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 5));
  });
}
