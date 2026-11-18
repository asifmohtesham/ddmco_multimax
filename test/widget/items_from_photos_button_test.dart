import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/items_from_photos_button.dart';

class _StubPermissionService extends PermissionService {
  final Rx<bool?> grant;
  String? lastDoctype;
  String? lastPermType;
  _StubPermissionService(bool? value) : grant = Rx<bool?>(value);

  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) {
    lastDoctype = doctype;
    lastPermType = permType;
    return grant.value;
  }
}

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => Directory.systemTemp.path,
    );
  });

  // PermissionService's constructor needs an ApiProvider.
  setUp(() => Get.put(ApiProvider()));
  tearDown(Get.reset);

  Widget host(Widget child) => GetMaterialApp(
        initialRoute: '/',
        getPages: [
          GetPage(name: '/', page: () => Scaffold(body: Center(child: child))),
          GetPage(
              name: AppRoutes.STOCK_SHEET,
              page: () => const Scaffold(body: Text('stock sheet'))),
        ],
      );

  testWidgets('shows the icon with the Items from Photos tooltip when allowed',
      (tester) async {
    final perms = Get.put<PermissionService>(_StubPermissionService(true))
        as _StubPermissionService;
    await tester.pumpWidget(host(const ItemsFromPhotosButton()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    expect(find.byTooltip('Items from Photos'), findsOneWidget);
    expect(perms.lastDoctype, 'Stock Entry');
    expect(perms.lastPermType, 'report');
  });

  testWidgets('hidden without Stock Entry report permission', (tester) async {
    Get.put<PermissionService>(_StubPermissionService(false));
    await tester.pumpWidget(host(const ItemsFromPhotosButton()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
  });

  testWidgets('tapping opens the screen with no photos', (tester) async {
    Get.put<PermissionService>(_StubPermissionService(true));
    await tester.pumpWidget(host(const ItemsFromPhotosButton()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.photo_library_outlined));
    await tester.pumpAndSettle();

    expect(Get.currentRoute, AppRoutes.STOCK_SHEET);
    expect(Get.arguments, isNull);
  });

  testWidgets('BarcodeInputWidget renders trailingActions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BarcodeInputWidget(
          onScan: (_) {},
          trailingActions: const [Icon(Icons.star, key: Key('extra'))],
        ),
      ),
    ));
    expect(find.byKey(const Key('extra')), findsOneWidget);
  });
}
