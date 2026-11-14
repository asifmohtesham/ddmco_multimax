import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_controller.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_screen.dart';

class _FakeBox {
  final Map<String, dynamic> _m = {};
  T? read<T>(String key) => _m[key] as T?;
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  bool hasData(String key) => _m.containsKey(key);
  Future<void> remove(String key) async => _m.remove(key);
}

/// Skips the network `load()` so the screen renders from injected state.
class _TestController extends SessionDefaultsController {
  _TestController(StorageService s) : super(storage: s);
  // Intentionally skips super.onInit() to avoid the network load() during the widget test.
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  final theme = buildAppTheme(AppScheme.light, Brightness.light);
  tearDown(Get.reset);

  testWidgets('shows Default Warehouse field and opens the picker',
      (tester) async {
    final c = _TestController(StorageService.withStorage(_FakeBox()))
      ..isLoading.value = false
      ..isLoadingWarehouses.value = false
      ..warehouses.assignAll(['Stores - M', 'Finished Goods - M']);
    Get.put<SessionDefaultsController>(c);

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: const SessionDefaultsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Default Warehouse'), findsOneWidget);
    expect(find.text('Select warehouse (optional)'), findsOneWidget);

    // Tapping the field opens the searchable picker sheet.
    await tester.tap(find.text('Select warehouse (optional)'));
    await tester.pumpAndSettle();
    expect(find.byType(WarehousePickerSheet), findsOneWidget);

    // Selecting a warehouse reflects back into the field.
    await tester.tap(find.text('Stores - M').last);
    await tester.pumpAndSettle();
    expect(c.selectedWarehouse.value, 'Stores - M');
    expect(find.text('Stores - M'), findsOneWidget);
  });
}
