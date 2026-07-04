import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/warehouse_stock_line.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';

void main() {
  final theme = buildAppTheme(AppScheme.light, Brightness.light);
  Widget app(Widget child) =>
      GetMaterialApp(theme: theme, home: Scaffold(body: child));

  testWidgets('renders header + rows and fires onTap', (tester) async {
    WarehouseStockLine? tapped;
    await tester.pumpWidget(app(Builder(
      builder: (context) => buildStockBalanceSection(
        context,
        'Stores - M',
        const [
          WarehouseStockLine(
              itemCode: 'FG-1', itemName: 'Blue Strap', balanceQty: 12, uom: 'Nos'),
        ],
        onTap: (l) => tapped = l,
      ),
    )));

    expect(find.text('STOCK BALANCE · STORES - M'), findsOneWidget);
    expect(find.text('Blue Strap'), findsOneWidget);
    expect(find.text('12 Nos'), findsOneWidget);

    await tester.tap(find.text('Blue Strap'));
    expect(tapped?.itemCode, 'FG-1');
  });

  testWidgets('loading state shows a visible progress indicator',
      (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) =>
          buildStockBalanceSection(context, 'Stores - M', null),
    )));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('empty state shows a message', (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) =>
          buildStockBalanceSection(context, 'Stores - M', const []),
    )));
    expect(find.textContaining('No stock for matching items'), findsOneWidget);
  });
}
