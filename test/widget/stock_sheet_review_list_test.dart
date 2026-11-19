import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/fix_code_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/reading_strip.dart';
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
  bool Function(int)? onRemove,
  bool removeEnabled = true,
  Map<String, Uint8List> thumbnails = const {},
}) => ReviewList(
  entries: entries,
  thumbnails: thumbnails,
  onReorder: onReorder ?? (_, _) {},
  onToggle: (_, _) {},
  onFix: (_) {},
  onRetryCheck: (_) {},
  onRemove: onRemove ?? (_) => true,
  removeEnabled: removeEnabled,
);

const _codeA = ClassifiedCode(itemCode: '1111111', barcode: '11111115');
const _codeB = ClassifiedCode(itemCode: '2222222', barcode: '22222225');

final _inStockEntry = ReviewEntry(
  path: 'in',
  items: [_item('12345670', _twoRacks)],
);
final _outOfStockEntry = ReviewEntry(
  path: 'out',
  items: [_item('76543210', const ItemStock(total: 0, racks: []))],
);

List<ReviewEntry> _sixStages() => [
  ReviewEntry(path: 'p1', number: 1, stage: ReadStage.notRead),
  ReviewEntry(path: 'p2', number: 2, stage: ReadStage.reading),
  ReviewEntry(path: 'p3', number: 3, stage: ReadStage.waiting),
  ReviewEntry(path: 'p4', number: 4, stage: ReadStage.zooming),
  ReviewEntry(
    path: 'p5',
    number: 5,
    stage: ReadStage.checkingStock,
    codes: const [_codeA],
  ),
  ReviewEntry(
    path: 'p6',
    number: 6,
    stage: ReadStage.waiting,
    codes: const [_codeA, _codeB],
  ),
];

void main() {
  testWidgets('each stage shows its line', (tester) async {
    await tester.pumpWidget(_app(_list(_sixStages())));
    expect(find.text('Not read yet'), findsOneWidget);
    expect(find.text('Reading…'), findsOneWidget);
    expect(find.text('Waiting to zoom in'), findsNWidgets(2));
    expect(find.text('Zooming in…'), findsOneWidget);
    expect(find.text('Checking stock…'), findsOneWidget);
    expect(find.text(_codeA.barcode), findsOneWidget);
    expect(find.text('Photo 6 · 2 items so far'), findsOneWidget);
    expect(
      tester.widgetList<Switch>(find.byType(Switch)).every(
        (s) => s.onChanged == null,
      ),
      isTrue,
    );
  });

  testWidgets('a ready row shows one pill and no quantity or rack', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_list([_inStockEntry, _outOfStockEntry])));
    expect(find.text('In stock'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.textContaining('KA-WH-'), findsNothing);
    expect(find.textContaining('Out of stock · 0'), findsNothing);
    expect(find.text('377'), findsNothing);
    expect(find.byType(RackChips), findsNothing);
  });

  testWidgets('a row that is not read yet can be swiped away', (tester) async {
    var removed = -1;
    await tester.pumpWidget(
      _app(
        _list(
          [ReviewEntry(path: 'p1', number: 1, stage: ReadStage.notRead)],
          onRemove: (i) {
            removed = i;
            return true;
          },
        ),
      ),
    );
    await tester.drag(find.text('Not read yet'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(removed, 0);
  });

  testWidgets('the strip follows the list and goes when all is settled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ReadingStrip(
          entries: [
            ReviewEntry(path: 'p1', number: 1),
            ReviewEntry(path: 'p2', number: 2, stage: ReadStage.zooming),
          ],
        ),
      ),
    );
    expect(find.text('Zooming in on photo 2 of 2…'), findsOneWidget);
    expect(find.text('1 read · 1 to go'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(
      _app(ReadingStrip(entries: [ReviewEntry(path: 'p1', number: 1)])),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('the dashed outline covers the whole row, like a solid border', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _list([
          ReviewEntry(path: 'p1', number: 1, stage: ReadStage.notRead),
          _inStockEntry,
        ]),
      ),
    );
    final outline = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.foregroundPainter.runtimeType.toString() == '_DashedOutline',
    );
    expect(outline, findsOneWidget);
    final dismissibles = find.byType(Dismissible);
    final dashedRow = tester.getRect(dismissibles.at(0));
    final solidRow = tester.getRect(dismissibles.at(1));
    final outlineRect = tester.getRect(outline);
    // The row's outer box is the Dismissible less its 8 px bottom margin.
    expect(outlineRect.left, dashedRow.left);
    expect(outlineRect.top, dashedRow.top);
    expect(outlineRect.width, dashedRow.width);
    expect(outlineRect.height, dashedRow.height - 8);
    // The same width as a settled row's bordered box.
    final solidBox = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(AppRadius.lg),
    );
    expect(tester.getSize(solidBox).width, outlineRect.width);
    expect(solidRow.width, dashedRow.width);
  });

  testWidgets('the strip is one live region that reads label then tally', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        ReadingStrip(
          entries: [
            ReviewEntry(path: 'p1', number: 1),
            ReviewEntry(path: 'p2', number: 2, stage: ReadStage.zooming),
          ],
        ),
      ),
    );
    final live = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.liveRegion == true,
    );
    final data = tester.getSemantics(live.first).getSemanticsData();
    expect(data.flagsCollection.isLiveRegion, isTrue);
    expect(data.label, contains('Zooming in on photo 2 of 2…'));
    expect(data.label, contains('1 read · 1 to go'));
    handle.dispose();
  });

  testWidgets('a zooming row has a spinner, a not-read row none', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _list([
          ReviewEntry(path: 'p1', number: 1, stage: ReadStage.notRead),
          ReviewEntry(path: 'p2', number: 2, stage: ReadStage.zooming),
        ]),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('dark mode: stage rows and pills keep text at 4.5:1 or more', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _list([..._sixStages(), _inStockEntry, _outOfStockEntry]),
        brightness: Brightness.dark,
      ),
    );
    final ctx = tester.element(find.byType(ReviewList));
    final surface = ctx.scheme.fg;
    // The page behind the dashed (unfilled) rows is the scaffold.
    final page = Theme.of(ctx).scaffoldBackgroundColor;
    var checked = 0;
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final style = t.style;
      final data = t.data;
      if (style?.color == null || data == null) continue;
      if (data == 'End of list') continue;
      final ink = style!.color!;
      final bg = (data == 'In stock' || data == 'Out of stock' ||
              data == 'Zooming in…')
          ? Color.alphaBlend(ink.withValues(alpha: 0.13), surface)
          : surface;
      for (final b in [bg, page]) {
        final over = Color.alphaBlend(ink, b);
        final l1 = over.computeLuminance();
        final l2 = b.computeLuminance();
        final ratio = (l1 > l2 ? l1 + 0.05 : l2 + 0.05) /
            (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '"$data" on $b');
      }
      checked++;
    }
    expect(checked, greaterThan(10));
  });

  testWidgets('swiping a row end-to-start calls onRemove with its index', (
    tester,
  ) async {
    final removed = <int>[];
    final entries = [
      ReviewEntry(path: 'a', items: [_item('12345670', null)]),
      ReviewEntry(path: 'b', items: [_item('76543210', null)]),
    ];
    await tester.pumpWidget(
      _app(
        _list(
          entries,
          onRemove: (i) {
            removed.add(i);
            return true;
          },
        ),
      ),
    );

    await tester.drag(find.text('Item 76543210'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(removed, [1]);
  });

  testWidgets('a refused removal keeps the row', (tester) async {
    final entries = [
      ReviewEntry(path: 'a', items: [_item('12345670', null)]),
    ];
    await tester.pumpWidget(_app(_list(entries, onRemove: (_) => false)));

    await tester.drag(find.text('Item 12345670'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Item 12345670'), findsOneWidget);
  });

  testWidgets('screen readers get a Remove item action', (tester) async {
    final handle = tester.ensureSemantics();
    final removed = <int>[];
    final entries = [
      ReviewEntry(path: 'a', items: [_item('12345670', null)]),
    ];
    await tester.pumpWidget(
      _app(
        _list(
          entries,
          onRemove: (i) {
            removed.add(i);
            return true;
          },
        ),
      ),
    );

    final node = tester.getSemantics(find.text('Item 12345670'));
    final data = node.getSemanticsData();
    final ids = data.customSemanticsActionIds ?? const <int>[];
    final labels = [
      for (final id in ids) CustomSemanticsAction.getAction(id)?.label,
    ];
    expect(labels, contains('Remove item'));
    final id = ids[labels.indexOf('Remove item')];
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      id,
    );
    expect(removed, [0]);
    handle.dispose();
  });

  testWidgets('a row with no item gets a Remove photo action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(_list([ReviewEntry(path: 'a', decodeFailed: true)])),
    );
    final data = tester
        .getSemantics(find.text('Unreadable photo'))
        .getSemanticsData();
    final labels = [
      for (final id in data.customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)?.label,
    ];
    expect(labels, contains('Remove photo'));
    handle.dispose();
  });

  testWidgets('no Remove action while removal is disabled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final entries = [
      ReviewEntry(path: 'a', items: [_item('12345670', null)]),
    ];
    await tester.pumpWidget(_app(_list(entries, removeEnabled: false)));

    final data = tester
        .getSemantics(find.text('Item 12345670'))
        .getSemanticsData();
    final labels = [
      for (final id in data.customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)?.label,
    ];
    expect(labels, isNot(contains('Remove item')));
    expect(labels, isNot(contains('Remove photo')));
    handle.dispose();
  });

  testWidgets('no swipe when removeEnabled is false', (tester) async {
    final removed = <int>[];
    final entries = [
      ReviewEntry(path: 'a', items: [_item('12345670', null)]),
    ];
    await tester.pumpWidget(
      _app(
        _list(
          entries,
          onRemove: (i) {
            removed.add(i);
            return true;
          },
          removeEnabled: false,
        ),
      ),
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
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Out of stock · 0'), findsNothing);
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

  testWidgets('typed and unchecked markers', (tester) async {
    final entries = [
      ReviewEntry(
        path: 'a',
        typed: true,
        unchecked: true,
        items: [_item('1234567', null)],
      ),
    ];
    await tester.pumpWidget(_app(_list(entries)));
    expect(find.text('Typed'), findsOneWidget);
    expect(find.text('Retry check'), findsOneWidget);
    expect(find.text('1234567 · Parent'), findsOneWidget);
  });

  testWidgets('rows of one photo list side by side', (tester) async {
    final entries = [
      ReviewEntry(path: 'a', id: 'a#0', items: [_item('12345670', null)]),
      ReviewEntry(path: 'a', id: 'a#1', items: [_item('76543210', null)]),
      ReviewEntry(path: 'a', id: 'a#2', notInErp: const ['99999995']),
    ];
    await tester.pumpWidget(_app(_list(entries)));
    expect(tester.takeException(), isNull);
    expect(find.text('Item 12345670'), findsOneWidget);
    expect(find.text('Item 76543210'), findsOneWidget);
    expect(find.text('Not in ERP: 99999995'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
  });

  testWidgets('an item shows its ERP image, a row with no item its photo', (
    tester,
  ) async {
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 4, height: 4)),
    );
    final entries = [
      // The photo has a thumbnail, the item none: a placeholder.
      ReviewEntry(path: 'a', items: [_item('12345670', null)]),
      ReviewEntry(path: 'b', items: [_item('76543210', null)]),
      ReviewEntry(path: 'c', decodeFailed: true),
    ];
    await tester.pumpWidget(
      _app(
        _list(
          entries,
          thumbnails: {
            'a': jpeg,
            ItemInfo.thumbnailKey('7654321'): jpeg,
            'c': jpeg,
          },
        ),
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
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
