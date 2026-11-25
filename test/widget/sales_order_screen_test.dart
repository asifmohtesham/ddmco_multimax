import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_screen.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/main.dart' show buildAppTheme;

class _EmptySalesOrders extends SalesOrderProvider {
  @override
  Future<Response> getSalesOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
    String orderBy = 'modified desc',
  }) async => Response(
    requestOptions: RequestOptions(path: '/'),
    statusCode: 200,
    data: {'data': []},
  );
}

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => r'C:\temp\test_cookies',
        );
  });

  setUp(() {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(AuthenticationController());
    Get.put(PermissionService());
    Get.put<SalesOrderProvider>(_EmptySalesOrders());
    Get.put(UserProvider());
    Get.put(SalesOrderController());
  });
  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, {TextScaler? appScaler}) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: buildAppTheme(AppScheme.light, Brightness.light),
        builder: appScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: appScaler),
                child: child!,
              ),
        home: const SalesOrderScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  RenderParagraph caption(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.text(label));

  testWidgets('the fixed bar sees the incoming app preset scaler', (
    tester,
  ) async {
    final theme = Get.put(
      ThemeController(persist: (_, _) async {}, restore: (_) async => null),
    );
    await theme.setTextSize(AppTextSize.large);
    final preset = AppTextSize.large.factor;
    await pump(tester, appScaler: TextScaler.linear(preset));

    final heading = tester.renderObject<RenderParagraph>(
      find.text('Sales Order').last,
    );
    expect(heading.textScaler.scale(12), closeTo(24 * preset, 0.01));
    expect(caption(tester, 'Everyone').textScaler.scale(12), 12 * preset);
    expect(caption(tester, 'Draft').textScaler.scale(14), 14 * preset);
  });

  testWidgets('the fixed bar fits scope and status captions at 200%', (
    tester,
  ) async {
    await pump(tester);

    for (final label in ['Everyone', 'Draft']) {
      final paragraph = caption(tester, label);
      expect(paragraph.textScaler.scale(12), 24);
      final line = paragraph.getDryLayout(
        BoxConstraints.tightFor(width: paragraph.size.width),
      );
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(line.height),
        reason: 'the complete $label line fits within the bar',
      );
    }
  });
}
