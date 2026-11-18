import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/fix_code_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/rack_chips.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/review_list.dart';
import 'package:multimax/main.dart' show buildAppTheme;

ReviewItem _item(String barcode, ItemStock? stock) => ReviewItem(
  code: ClassifiedCode(itemCode: barcode.substring(0, 7), barcode: barcode),
  info: ItemInfo(
    itemCode: barcode.substring(0, 7),
    itemName: 'Item $barcode',
    variantOf: 'Parent',
  ),
  stock: stock,
);

const _twoRacks = ItemStock(
  total: 377,
  racks: [
    RackQty(rack: 'KA-WH-DXB1-21A', qty: 305),
    RackQty(rack: 'KA-WH-DXB1-14D', qty: 72),
  ],
);

Widget _app(Widget child, {Brightness brightness = Brightness.light}) {
  final theme = buildAppTheme(
    brightness == Brightness.dark ? AppScheme.dark : AppScheme.light,
    brightness,
  );
  return GetMaterialApp(
    theme: theme,
    darkTheme: theme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(body: child),
  );
}

ReviewList _list(
  List<ReviewEntry> entries, {
  void Function(int, int)? onReorder,
  void Function(int)? onRemove,
  bool removeEnabled = true,
}) => ReviewList(
  entries: entries,
  thumbnails: const <String, Uint8List>{},
  onReorder: onReorder ?? (_, _) {},
  onToggle: (_, _) {},
  onToggleItem: (_, _, _) {},
  onFix: (_, _) {},
  onRetryCheck: (_) {},
  onRemove: onRemove ?? (_) {},
  removeEnabled: removeEnabled,
);

void main() {
  testWidgets('swiping a row end-to-start calls onRemove with its index', (
    tester,
  ) async {
    final removed = <int>[];
    final entries = [
      ReviewEntry(path: 'a', items: [_item('12345670', null)]),
      ReviewEntry(path: 'b', items: [_item('76543210', null)]),
    ];
    await tester.pumpWidget(_app(_list(entries, onRemove: removed.add)));

    await tester.drag(find.text('Item 76543210'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(removed, [1]);
  });

  testWidgets('no swipe when removeEnabled is false', (tester) async {
    final removed = <int>[];
    final entries = [
      ReviewEntry(path: 'a', items: [_item('12345670', null)]),
    ];
    await tester.pumpWidget(
      _app(_list(entries, onRemove: removed.add, removeEnabled: false)),
    );

    await tester.drag(find.text('Item 12345670'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(removed, isEmpty);
    expect(find.text('Item 12345670'), findsOneWidget);
  });

  testWidgets('rack chips show the total and full rack names', (tester) async {
    await tester.pumpWidget(_app(const RackChips(stock: _twoRacks)));
    expect(find.text('377'), findsOneWidget);
    expect(find.text('KA-WH-DXB1-21A 305'), findsOneWidget);
    expect(find.text('KA-WH-DXB1-14D 72'), findsOneWidget);
  });

  testWidgets('five racks show three chips and +2', (tester) async {
    const stock = ItemStock(
      total: 15,
      racks: [
        RackQty(rack: 'R1', qty: 5),
        RackQty(rack: 'R2', qty: 4),
        RackQty(rack: 'R3', qty: 3),
        RackQty(rack: 'R4', qty: 2),
        RackQty(rack: null, qty: 1),
      ],
    );
    await tester.pumpWidget(_app(const RackChips(stock: stock)));
    expect(find.text('R1 5'), findsOneWidget);
    expect(find.text('R3 3'), findsOneWidget);
    expect(find.text('R4 2'), findsNothing);
    expect(find.text('+2'), findsOneWidget);

    await tester.tap(find.text('+2'));
    await tester.pumpAndSettle();
    expect(find.text('R4'), findsOneWidget);
    expect(find.text('No rack'), findsOneWidget);
  });

  testWidgets('out of stock shows the pill and no chips', (tester) async {
    await tester.pumpWidget(
      _app(const RackChips(stock: ItemStock(total: 0, racks: []))),
    );
    expect(find.text('Out of stock · 0'), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('no Stock Balance row (null stock) shows the pill', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const RackChips(stock: null)));
    expect(find.text('Out of stock · 0'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        _list([
          ReviewEntry(path: 'a', items: [_item('1234567', null)]),
        ]),
      ),
    );
    expect(find.text('Out of stock · 0'), findsOneWidget);
  });

  testWidgets('racks given smallest first show largest first', (tester) async {
    const stock = ItemStock(
      total: 10,
      racks: [
        RackQty(rack: 'R1', qty: 1),
        RackQty(rack: 'R2', qty: 2),
        RackQty(rack: 'R3', qty: 3),
        RackQty(rack: 'R4', qty: 4),
      ],
    );
    await tester.pumpWidget(_app(const RackChips(stock: stock)));
    expect(find.text('R1 1'), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    final x = [
      for (final label in ['R4 4', 'R3 3', 'R2 2'])
        tester.getTopLeft(find.text(label)).dx,
    ];
    expect(x[0], lessThan(x[1]));
    expect(x[1], lessThan(x[2]));
  });

  test('formatQty rounds to three decimals and drops trailing zeros', () {
    expect(formatQty(305), '305');
    expect(formatQty(2.5), '2.5');
    expect(formatQty(0.1 + 0.2), '0.3');
    expect(formatQty(1.23456), '1.235');
    expect(formatQty(-2), '-2');
    expect(formatQty(4.9999999), '5');
  });

  testWidgets('dragging the handle down one place calls onReorder(0, 2)', (
    tester,
  ) async {
    final calls = <(int, int)>[];
    final entries = [
      ReviewEntry(path: 'a', items: [_item('1234567', _twoRacks)]),
      ReviewEntry(path: 'b', items: [_item('7654321', _twoRacks)]),
    ];
    await tester.pumpWidget(
      _app(_list(entries, onReorder: (o, n) => calls.add((o, n)))),
    );
    final handle = find.byIcon(Icons.drag_indicator).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, [(0, 2)]);
  });

  testWidgets('the switch on an unresolved row is disabled', (tester) async {
    await tester.pumpWidget(
      _app(_list([ReviewEntry(path: 'a', decodeFailed: true)])),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(find.text('Unreadable photo'), findsOneWidget);
    expect(find.text('✎ Type or scan code'), findsOneWidget);
  });

  testWidgets('typed, unchecked and leftover notes', (tester) async {
    final entries = [
      ReviewEntry(
        path: 'a',
        typed: true,
        unchecked: true,
        notInErp: const ['9999999'],
        items: [_item('1234567', null)],
      ),
    ];
    await tester.pumpWidget(_app(_list(entries)));
    expect(find.text('Typed'), findsOneWidget);
    expect(find.text('Retry check'), findsOneWidget);
    expect(find.text('Also read: 9999999 · not in ERP'), findsOneWidget);
    expect(find.text('1234567 · Parent'), findsOneWidget);
  });

  testWidgets('End of list is present', (tester) async {
    await tester.pumpWidget(_app(_list([ReviewEntry(path: 'a')])));
    expect(find.text('End of list'), findsOneWidget);
  });

  testWidgets('dark mode rows use the themed surface, never white', (
    tester,
  ) async {
    final entries = [
      ReviewEntry(path: 'a', items: [_item('1234567', _twoRacks)]),
      ReviewEntry(path: 'b', decodeFailed: true),
    ];
    await tester.pumpWidget(_app(_list(entries), brightness: Brightness.dark));
    final ctx = tester.element(find.byType(ReviewList));
    final fg = ctx.scheme.fg;
    final colours = <Color>[];
    for (final c in tester.widgetList<Container>(find.byType(Container))) {
      final d = c.decoration;
      if (d is BoxDecoration && d.color != null) colours.add(d.color!);
    }
    expect(colours, contains(fg));
    expect(colours, isNot(contains(Colors.white)));
  });

  group('fix code sheet', () {
    Future<void> open(
      WidgetTester tester,
      Future<String?> Function(String) onSubmit,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showFixCodeSheet(
                context,
                onSubmit: onSubmit,
                scan: (_) async => null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the error inline and stays open', (tester) async {
      await open(tester, (_) async => 'Not in ERP');
      await tester.enterText(find.byType(TextField), '1234567');
      await tester.tap(find.text('Use code'));
      await tester.pumpAndSettle();
      expect(find.text('Not in ERP'), findsOneWidget);
      expect(find.text('Use code'), findsOneWidget);
    });

    testWidgets('typing clears the error; Scan is a button only', (
      tester,
    ) async {
      await open(tester, (_) async => 'Not in ERP');
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1234567');
      await tester.tap(find.text('Use code'));
      await tester.pumpAndSettle();
      expect(find.text('Not in ERP'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '12345678');
      await tester.pump();
      expect(find.text('Not in ERP'), findsNothing);
    });

    testWidgets('closes when the result is null', (tester) async {
      await open(tester, (_) async => null);
      await tester.enterText(find.byType(TextField), '1234567');
      await tester.tap(find.text('Use code'));
      await tester.pumpAndSettle();
      expect(find.text('Use code'), findsNothing);
    });
  });
}
