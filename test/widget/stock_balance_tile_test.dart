import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';

// Renders the redesigned Stock Balance tile across its four health states, in
// both light and dark themes, on a narrow phone-width viewport — guarding the
// dense layout against overflow and confirming each state surfaces its key
// figures and (for dimension-wise rows) the rack. The report emits ERPNext's
// `bal_qty` / `bal_val` / `val_rate` / `reserved_stock` fieldnames, so the rows
// below use those — exercising the same path that previously leaked into chips.
void main() {
  // A dimension-wise report row: the rack column has an instance-defined
  // fieldname (`rack`) and arrives among the attribute columns.
  Map<String, dynamic> row({
    required num bal,
    required num opening,
    num inQty = 0,
    num outQty = 0,
    num reserved = 0,
    num rate = 0,
    num value = 0,
    String? rack,
  }) =>
      {
        'item_code': '2002855',
        'item_name': 'BELTS FORMAL AUTO CP',
        'stock_uom': 'Nos',
        'warehouse': 'WH-DXB3 - KA',
        'bal_qty': bal,
        'opening_qty': opening,
        'in_qty': inQty,
        'out_qty': outQty,
        'reserved_stock': reserved,
        'val_rate': rate,
        'bal_val': value,
        'customer_code': '5067049',
        if (rack != null) 'rack': rack,
      };

  final rackCol = <Map<String, dynamic>>[
    {'fieldname': 'rack', 'label': 'Rack'},
  ];

  Future<void> pumpTile(
    WidgetTester tester, {
    required Map<String, dynamic> data,
    required List<Map<String, dynamic>> attrCols,
    required Brightness brightness,
    bool showImage = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2490EF),
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: buildStockBalanceTileForTest(
              row: data,
              attrCols: attrCols,
              showImage: showImage,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    testWidgets('healthy row renders ledger, rack and availability ($mode)',
        (tester) async {
      await pumpTile(
        tester,
        data: row(bal: 12, opening: 12, rack: 'KA-WH-DXB3-BLOCK 1'),
        attrCols: rackCol,
        brightness: brightness,
      );

      expect(find.text('BELTS FORMAL AUTO CP'), findsOneWidget);
      expect(find.text('OPENING'), findsOneWidget);
      expect(find.text('BALANCE'), findsOneWidget);
      // Rack surfaced on the location line, not as a chip.
      expect(find.textContaining('BLOCK 1'), findsOneWidget);
      expect(find.text('Rack: KA-WH-DXB3-BLOCK 1'), findsNothing);
      // Availability bar labels for a free, healthy item.
      expect(find.textContaining('Available'), findsOneWidget);
      expect(find.textContaining('Reserved'), findsOneWidget);
    });

    testWidgets('heavily-reserved row → watch state with split ($mode)',
        (tester) async {
      await pumpTile(
        tester,
        data: row(
          bal: 220,
          opening: 180,
          inQty: 64,
          outQty: 24,
          reserved: 200,
          rate: 38.5,
          value: 8470,
          rack: 'BLOCK 3',
        ),
        attrCols: rackCol,
        brightness: brightness,
      );

      expect(find.text('+64'), findsOneWidget);
      expect(find.text('−24'), findsOneWidget); // U+2212
      expect(find.textContaining('Available'), findsOneWidget);
    });

    testWidgets('negative row shows the negative-stock note ($mode)',
        (tester) async {
      await pumpTile(
        tester,
        data: row(bal: -6, opening: 4, outQty: 10, rack: 'BLOCK 2'),
        attrCols: rackCol,
        brightness: brightness,
      );

      expect(find.textContaining('Negative stock'), findsOneWidget);
      // No availability bar in the negative state.
      expect(find.textContaining('Available'), findsNothing);
    });

    testWidgets('zero-balance row shows the out-of-stock note ($mode)',
        (tester) async {
      await pumpTile(
        tester,
        // No rack column at all → "No rack assigned" fallback.
        data: row(bal: 0, opening: 0),
        attrCols: const [],
        brightness: brightness,
      );

      expect(find.textContaining('Out of stock'), findsOneWidget);
      expect(find.textContaining('No rack assigned'), findsOneWidget);
    });
  }

  testWidgets('showImage with no image URL falls back to item initials',
      (tester) async {
    await pumpTile(
      tester,
      data: row(bal: 12, opening: 12, rack: 'BLOCK 1'), // no item_image key
      attrCols: rackCol,
      brightness: Brightness.light,
      showImage: true,
    );
    // "BELTS FORMAL AUTO CP" → initials "BF" (first letters of first 2 words).
    expect(find.text('BF'), findsOneWidget);
  });

  testWidgets('a long rack is never truncated — it wraps, no ellipsis',
      (tester) async {
    const longRack = 'KA-WH-DXB3-BLOCK 1-SHELF 4-BIN 27';
    await pumpTile(
      tester,
      data: row(bal: 5, opening: 5, rack: longRack),
      attrCols: rackCol,
      brightness: Brightness.light,
    );
    // The rack Text must allow wrapping (no maxLines cap, not ellipsis-clipped)
    // so the operator can always read the full pick location.
    final rackText = tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (t) => (t.textSpan?.toPlainText() ?? '').contains(longRack),
        );
    expect(rackText.overflow, isNot(TextOverflow.ellipsis));
    expect(rackText.maxLines, isNull);
  });

  testWidgets('tapping the warehouse fires the warehouse-filter callback',
      (tester) async {
    var tappedWith = '';
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: buildStockBalanceTileForTest(
              row: row(bal: 12, opening: 12, rack: 'BLOCK 1'),
              attrCols: rackCol,
              onWarehouseTap: () => tappedWith = 'tapped',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('WH-DXB3'));
    expect(tappedWith, 'tapped');
  });

  testWidgets('drill-down taps: card→ledger, reserved→reserved, cust→customer',
      (tester) async {
    var ledger = false, reserved = false, customer = false;
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: buildStockBalanceTileForTest(
              // balance>0 with reservation → availability bar with Reserved;
              // the row helper already sets customer_code 5067049.
              row: row(bal: 220, opening: 180, reserved: 50, rack: 'BLOCK 3'),
              attrCols: rackCol,
              onLedgerTap: () => ledger = true,
              onReservedTap: () => reserved = true,
              onCustomerTap: () => customer = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Reserved'));
    expect(reserved, isTrue);

    await tester.tap(find.textContaining('5067049'));
    expect(customer, isTrue);

    // Tapping the ledger strip (card body) opens the ledger.
    await tester.tap(find.text('OPENING'));
    expect(ledger, isTrue);
  });
}
