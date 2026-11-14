import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/supplier_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_screen.dart';

/// Skips the network fetches (POs/suppliers/users/warehouses) and the search
/// debounce worker — these tests only exercise the widget build.
class _QuietPurchaseOrderController extends PurchaseOrderController {
  // super.onInit() is exactly the network work being skipped; GetX marks
  // _initialized in onStart, not onInit, so an empty override is safe.
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Serves a fixed permission verdict without any network fetch. The value is
/// Rx-backed because DocTypeGuard's internal Obx must observe something.
class _StubPermissionService extends PermissionService {
  final Rx<bool?> grant;
  _StubPermissionService(bool? value) : grant = Rx<bool?>(value);

  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => grant.value;
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
    Get.put(PurchaseOrderProvider());
    Get.put(SupplierProvider());
    Get.put(UserProvider());
    Get.put(WarehouseProvider());
    Get.put<PurchaseOrderController>(_QuietPurchaseOrderController());
  });
  tearDown(Get.reset);

  Future<void> pumpScreen(WidgetTester tester, {required bool? grant}) async {
    Get.put<PermissionService>(_StubPermissionService(grant));
    await tester.pumpWidget(const GetMaterialApp(home: PurchaseOrderScreen()));
    await tester.pump();
  }

  testWidgets('builds without the GetX improper-use error', (tester) async {
    // Regression: the FAB was wrapped in an Obx whose builder read no
    // observables (DocTypeGuard is reactive internally), which makes GetX
    // throw "[Get] the improper use of a GetX has been detected" on every
    // build and paint a full-screen ErrorWidget over the list.
    await pumpScreen(tester, grant: null);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create FAB shows when the create permission is granted',
      (tester) async {
    await pumpScreen(tester, grant: true);
    expect(tester.takeException(), isNull);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('New Purchase Order'), findsOneWidget);
  });

  testWidgets('create FAB stays hidden when the create permission is denied',
      (tester) async {
    await pumpScreen(tester, grant: false);
    expect(tester.takeException(), isNull);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
