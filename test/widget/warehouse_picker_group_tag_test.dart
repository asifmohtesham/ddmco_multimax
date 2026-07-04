import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';

void main() {
  final theme = buildAppTheme(AppScheme.light, Brightness.light);
  Widget app(Widget child) =>
      GetMaterialApp(theme: theme, home: Scaffold(body: child));

  testWidgets('tags group warehouses; leaves have no tag', (tester) async {
    await tester.pumpWidget(app(WarehousePickerSheet(
      warehouses: const ['Stores A - M', 'All Warehouses - M'],
      isLoading: false,
      onSelected: (_) {},
      groupNames: const {'All Warehouses - M'},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Stores A - M'), findsOneWidget);
    expect(find.text('All Warehouses - M'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget); // only the group row
  });

  testWidgets('no tags when groupNames is empty (default)', (tester) async {
    await tester.pumpWidget(app(WarehousePickerSheet(
      warehouses: const ['Stores A - M', 'Stores B - M'],
      isLoading: false,
      onSelected: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Group'), findsNothing);
  });
}
