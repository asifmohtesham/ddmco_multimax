import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/batch_age_provider.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';
import 'package:multimax/app/shared/item_sheet/widgets/older_stock_sheet.dart';
import 'package:multimax/main.dart' show buildAppTheme;

OlderBatch _older(String batch, DateTime date, double qty,
        {bool fromReceipt = true, Map<String, double>? byWarehouse}) =>
    OlderBatch(
      batchNo: batch,
      age: BatchAge(date, fromReceipt: fromReceipt),
      availableQty: qty,
      qtyByWarehouse: byWarehouse ?? {'WH-DXB1 - KA': qty},
    );

void main() {
  final lightTheme = buildAppTheme(AppScheme.light, Brightness.light);
  final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);

  Widget app(ThemeData theme, Widget child) => MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: child),
        ),
      );

  Widget sheet({
    List<OlderBatch>? older,
    Future<List<RackStockLine>> Function()? loadRacks,
  }) =>
      OlderStockSheet(
        itemLabel: '1002890 · WALLETS COW',
        refusedBatch: '10028902-4CDQ9W',
        older: older ??
            [_older('10028902-46FTRR', DateTime(2025, 10, 1), 132)],
        loadRacks: loadRacks ??
            () async => const [
                  RackStockLine(
                      warehouse: 'WH-DXB1 - KA',
                      rack: 'KA-WH-DXB1-9C',
                      qty: 936),
                ],
      );

  testWidgets('says what was refused, what ships first and where to look',
      (tester) async {
    await tester.pumpWidget(app(lightTheme, sheet()));
    await tester.pumpAndSettle();

    expect(find.text('Older stock must ship first'), findsOneWidget);
    expect(find.textContaining('10028902-4CDQ9W', findRichText: true),
        findsOneWidget);
    expect(find.text('10028902-46FTRR'), findsOneWidget);
    expect(find.text('132 available'), findsOneWidget);
    expect(find.text('Received 01 Oct 2025'), findsOneWidget);
    expect(find.text('This item is stored in'), findsOneWidget);
    expect(find.text('KA-WH-DXB1-9C'), findsOneWidget);
    expect(find.text('Scan older batch'), findsOneWidget);
    expect(find.textContaining('supervisor'), findsOneWidget);
  });

  testWidgets('a batch with no receipt is "Dated", and each warehouse is shown',
      (tester) async {
    await tester.pumpWidget(app(
      lightTheme,
      sheet(older: [
        _older('10028902-7CY', DateTime(2004, 7, 3), 1136,
            fromReceipt: false,
            byWarehouse: {'WH-DXB1 - KA': 1100, 'WH-DXB3 - KA': 36}),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Dated 03 Jul 2004'), findsOneWidget);
    expect(find.text('1,136 available'), findsOneWidget);
    expect(find.text('WH-DXB1 - KA  ·  1,100'), findsOneWidget);
    expect(find.text('WH-DXB3 - KA  ·  36'), findsOneWidget);
  });

  testWidgets('more than three older batches are counted, not listed',
      (tester) async {
    await tester.pumpWidget(app(
      lightTheme,
      sheet(older: [
        for (var i = 1; i <= 5; i++)
          _older('BATCH-$i', DateTime(2025, i, 1), 10),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('BATCH-1'), findsOneWidget);
    expect(find.text('BATCH-3'), findsOneWidget);
    expect(find.text('BATCH-4'), findsNothing);
    expect(find.text('+ 2 more older batches'), findsOneWidget);
  });

  testWidgets('racks: loading, then the list', (tester) async {
    final racks = Completer<List<RackStockLine>>();
    await tester.pumpWidget(app(lightTheme, sheet(loadRacks: () => racks.future)));
    await tester.pump();

    expect(find.byKey(const ValueKey('older_stock_racks_loading')),
        findsOneWidget);
    // The older batch is already readable while the racks load.
    expect(find.text('10028902-46FTRR'), findsOneWidget);

    racks.complete(const [
      RackStockLine(warehouse: 'WH-DXB1 - KA', rack: 'KA-WH-DXB1-11B', qty: 1092),
      RackStockLine(warehouse: 'WH-DXB1 - KA', rack: '', qty: 36),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('KA-WH-DXB1-11B'), findsOneWidget);
    expect(find.text('No rack recorded'), findsOneWidget);
    expect(find.byKey(const ValueKey('older_stock_racks_loading')),
        findsNothing);
  });

  testWidgets('racks: a failed lookup does not hide the refusal',
      (tester) async {
    await tester.pumpWidget(app(
      lightTheme,
      sheet(loadRacks: () async => throw StateError('offline')),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('older_stock_racks_error')),
        findsOneWidget);
    expect(find.text('10028902-46FTRR'), findsOneWidget);
    expect(find.text('Scan older batch'), findsOneWidget);
  });

  testWidgets('racks: none recorded', (tester) async {
    await tester.pumpWidget(app(lightTheme, sheet(loadRacks: () async => const [])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('older_stock_racks_empty')),
        findsOneWidget);
  });

  testWidgets('"Scan older batch" closes the sheet with true', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showOlderStockSheet(
                  context,
                  itemLabel: '1002890',
                  refusedBatch: '10028902-4CDQ9W',
                  older: [_older('10028902-46FTRR', DateTime(2025, 10, 1), 132)],
                  loadRacks: () async => const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('older_stock_scan_older')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('Older stock must ship first'), findsNothing);
  });

  testWidgets('dark mode: themed surface, no light-mode inks', (tester) async {
    await tester.pumpWidget(app(darkTheme, sheet()));
    await tester.pumpAndSettle();

    final surface = tester
        .widgetList<Container>(find.ancestor(
            of: find.text('Older stock must ship first'),
            matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .whereType<Color>()
        .first;
    expect(surface, darkTheme.colorScheme.surface);

    // The quantity uses the dark-mode step of the status ramp.
    final qty = tester.widget<Text>(find.text('132 available'));
    expect(qty.style?.color, AppColors.red300);
  });

  testWidgets('light mode: the quantity uses the AA step of the ramp',
      (tester) async {
    await tester.pumpWidget(app(lightTheme, sheet()));
    await tester.pumpAndSettle();
    final qty = tester.widget<Text>(find.text('132 available'));
    expect(qty.style?.color, AppColors.red700);
  });

  test('formatOlderStockQty', () {
    expect(formatOlderStockQty(12), '12');
    expect(formatOlderStockQty(1136), '1,136');
    expect(formatOlderStockQty(6.5), '6.5');
  });
}
