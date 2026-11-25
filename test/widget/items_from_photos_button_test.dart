import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/item/widgets/item_list_app_bar.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/items_from_photos_button.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../unit/theme_contrast_test.dart' show contrast;

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

class _EmptyItemProvider extends ItemProvider {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getItems({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    String orderBy = '',
  }) async {
    calls++;
    return {'data': []};
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
      GetPage(
        name: '/',
        page: () => Scaffold(body: Center(child: child)),
      ),
      GetPage(
        name: AppRoutes.ITEMS_FROM_PHOTOS,
        page: () => const Scaffold(body: Text('stock sheet')),
      ),
    ],
  );

  testWidgets(
    'shows the icon with the Items from Photos tooltip when allowed',
    (tester) async {
      final perms =
          Get.put<PermissionService>(_StubPermissionService(true))
              as _StubPermissionService;
      await tester.pumpWidget(host(const ItemsFromPhotosButton()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      expect(find.byTooltip('Items from Photos'), findsOneWidget);
      expect(perms.lastDoctype, 'Stock Entry');
      expect(perms.lastPermType, 'report');
    },
  );

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

    expect(Get.currentRoute, AppRoutes.ITEMS_FROM_PHOTOS);
    expect(Get.arguments, isNull);
  });

  testWidgets('BarcodeInputWidget renders trailingActions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeInputWidget(
            onScan: (_) {},
            trailingActions: const [Icon(Icons.star, key: Key('extra'))],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('extra')), findsOneWidget);
  });

  for (final (brightness, accent) in [
    (Brightness.dark, AppAccent.brand),
    (Brightness.light, AppAccent.blue),
  ]) {
    testWidgets(
      'Item header image toggle preserves its primary ink [${brightness.name} ${accent.name}]',
      (tester) async {
        Get.put<PermissionService>(_StubPermissionService(false));
        final provider =
            Get.put<ItemProvider>(_EmptyItemProvider()) as _EmptyItemProvider;
        final controller = Get.put(ItemController());
        final scheme = AppScheme.of(brightness);
        final theme = buildAppTheme(scheme, brightness, accent: accent);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: CustomScrollView(slivers: [ItemListAppBar()]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final icon = find.byIcon(Icons.image);
        final action = find.ancestor(
          of: icon,
          matching: find.byType(IconButton),
        );
        final ink = tester.widget<InkWell>(
          find.descendant(of: action, matching: find.byType(InkWell)),
        );
        final primary = theme.colorScheme.primary;
        expect(IconTheme.of(tester.element(icon)).color, primary);
        expect(tester.getSize(action), const Size.square(48));
        expect(ink.splashFactory, NoSplash.splashFactory);
        var substrate = scheme.fg;
        for (final state in [
          WidgetState.focused,
          WidgetState.hovered,
          WidgetState.pressed,
        ]) {
          substrate = Color.alphaBlend(
            ink.overlayColor!.resolve({state})!,
            substrate,
          );
          expect(contrast(primary, substrate), greaterThanOrEqualTo(3));
        }

        Focus.of(tester.element(icon)).requestFocus();
        await tester.pump();
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: const Offset(1, 1));
        final center = tester.getCenter(action);
        await pointer.moveTo(center);
        await pointer.down(center);
        await tester.pump(const Duration(milliseconds: 150));
        final contour = tester.widget<HeaderActionContour>(
          find.ancestor(of: icon, matching: find.byType(HeaderActionContour)),
        );
        expect(
          contour.states,
          containsAll([
            WidgetState.focused,
            WidgetState.hovered,
            WidgetState.pressed,
          ]),
        );
        expect(IconTheme.of(tester.element(icon)).color, primary);
        await pointer.cancel();
        await pointer.removePointer();
        await tester.pump();

        final before = provider.calls;
        final rect = tester.getRect(action);
        await tester.tapAt(rect.topLeft + const Offset(1, 1));
        await tester.pumpAndSettle();
        expect(controller.showImagesOnly.value, isFalse);
        expect(find.byIcon(Icons.image_outlined), findsOneWidget);
        expect(provider.calls, before + 1);
      },
    );
  }
}
