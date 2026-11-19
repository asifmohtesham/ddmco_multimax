import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/model/ageing_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/fix_code_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/reading_strip.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/review_list.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/stock_card_details.dart';
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
  Set<String> openCards = const {},
  Map<String, AgeingState> ageing = const {},
  void Function(String)? onToggleCard,
  void Function(String)? onRetryAgeing,
}) => ReviewList(
  entries: entries,
  thumbnails: thumbnails,
  onReorder: onReorder ?? (_, _) {},
  onToggle: (_, _) {},
  onFix: (_) {},
  onRetryCheck: (_) {},
  onRemove: onRemove ?? (_) => true,
  removeEnabled: removeEnabled,
  openCards: openCards,
  ageing: ageing,
  onToggleCard: onToggleCard ?? (_) {},
  onRetryAgeing: onRetryAgeing ?? (_) {},
);

/// The item code of [_twoRackEntry] (see [_item]).
const _a = '1234567';

/// Racks KA-WH-DXB1-20D 300 and stock on no rack 84: 384 in all.
const _inStock = ItemStock(
  total: 384,
  racks: [
    RackQty(rack: 'KA-WH-DXB1-20D', qty: 300),
    RackQty(rack: null, qty: 84),
  ],
);

final _twoRackEntry = ReviewEntry(
  path: 'two',
  items: [_item('12345670', _inStock)],
);

const _ageingA = ItemAgeing(
  availableQty: 384,
  averageAge: 120.5,
  earliest: 400,
  latest: 3,
  buckets: [
    (label: '0 - 90', qty: 200),
    (label: '91 - 180', qty: 0),
    (label: '181 - 360', qty: 50),
    (label: '361 - 720', qty: 50),
    (label: '721 - Above', qty: 84),
  ],
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
    expect(find.text('Rack-Wise Stock Balance'), findsNothing);
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

  testWidgets('a null stock (no Stock Balance row) shows Out of stock', (
    tester,
  ) async {
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

  group('the card', () {
    testWidgets(
      'a tap opens the card to the rack table at once and the ageing when it arrives',
      (tester) async {
        String? toggled;
        Widget list(Set<String> open, Map<String, AgeingState> ageing) => _app(
          _list(
            [_twoRackEntry],
            openCards: open,
            ageing: ageing,
            onToggleCard: (id) => toggled = id,
          ),
        );
        await tester.pumpWidget(list(const {}, const {}));
        expect(find.text('Rack-Wise Stock Balance'), findsNothing);
        await tester.tap(find.text('In stock'));
        expect(toggled, _twoRackEntry.id);

        await tester.pumpWidget(
          list(
            {_twoRackEntry.id},
            {_a: const AgeingState(AgeingStatus.loading)},
          ),
        );
        expect(find.text('Rack-Wise Stock Balance'), findsOneWidget);
        expect(find.text('Rack'), findsOneWidget);
        expect(find.text('Balance Qty'), findsOneWidget);
        expect(find.text('KA-WH-DXB1-20D'), findsOneWidget);
        expect(find.text('No rack'), findsOneWidget);
        expect(find.text('384'), findsOneWidget); // the total: two lines
        expect(find.text('Fetching Stock Ageing…'), findsOneWidget);

        await tester.pumpWidget(
          list(
            {_twoRackEntry.id},
            {
              _a: const AgeingState(AgeingStatus.ready, [_ageingA]),
            },
          ),
        );
        for (final label in [
          'Stock Ageing',
          'Available Qty',
          'Average Age',
          'Earliest',
          'Latest',
          'Age (0 - 90)',
          'Age (721 - Above)',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text('120.5'), findsOneWidget);
        expect(find.text('400'), findsOneWidget);
        expect(find.textContaining('Value'), findsNothing);

        // A tap on the open card closes it.
        toggled = null;
        await tester.tap(find.text('In stock'));
        expect(toggled, _twoRackEntry.id);
      },
    );

    testWidgets('a single rack has no total line, largest rack first', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const StockCardDetails(
            stock: ItemStock(total: 7, racks: [RackQty(rack: 'R1', qty: 7)]),
            ageing: null,
            onRetry: _noop,
          ),
        ),
      );
      expect(find.text('7'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          const StockCardDetails(stock: _inStock, ageing: null, onRetry: _noop),
        ),
      );
      expect(
        tester.getTopLeft(find.text('KA-WH-DXB1-20D')).dy,
        lessThan(tester.getTopLeft(find.text('No rack')).dy),
      );
    });

    testWidgets('the other ageing states say what they are', (tester) async {
      for (final (state, text) in [
        (
          const AgeingState(AgeingStatus.missing),
          'Not in the Stock Ageing report.',
        ),
        (const AgeingState(AgeingStatus.failed), "Couldn't load Stock Ageing."),
        (
          const AgeingState(AgeingStatus.denied),
          "You don't have access to Stock Ageing.",
        ),
      ]) {
        await tester.pumpWidget(
          _app(
            StockCardDetails(stock: _inStock, ageing: state, onRetry: () {}),
          ),
        );
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('Retry'), findsNothing); // denied: no retry
      await tester.pumpWidget(
        _app(const StockCardDetails(stock: null, ageing: null, onRetry: _noop)),
      );
      expect(find.text('No stock in Finished Goods - KA.'), findsOneWidget);
      expect(
        find.text('Not in the Stock Ageing report: nothing in stock.'),
        findsOneWidget,
      );
    });

    testWidgets('Retry on a failure asks again', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _app(
          StockCardDetails(
            stock: _inStock,
            ageing: const AgeingState(AgeingStatus.failed),
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('several warehouses each show under their name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: StockCardDetails(
              stock: _inStock,
              ageing: const AgeingState(AgeingStatus.ready, [
                ItemAgeing(
                  warehouse: 'Rack A - KA',
                  availableQty: 1,
                  averageAge: 1,
                  earliest: 1,
                  latest: 1,
                  buckets: [(label: '0 - 90', qty: 1)],
                ),
                ItemAgeing(
                  warehouse: 'Rack B - KA',
                  availableQty: 2,
                  averageAge: 2,
                  earliest: 2,
                  latest: 2,
                  buckets: [(label: '0 - 90', qty: 2)],
                ),
              ]),
              onRetry: _noop,
            ),
          ),
        ),
      );
      expect(find.text('Rack A - KA'), findsOneWidget);
      expect(find.text('Rack B - KA'), findsOneWidget);
      expect(find.text('Available Qty'), findsNWidgets(2));
    });

    testWidgets('a swipe or a drag by the handle does not open the card', (
      tester,
    ) async {
      var toggles = 0;
      await tester.pumpWidget(
        _app(
          _list(
            [_inStockEntry, _outOfStockEntry],
            onToggleCard: (_) => toggles++,
            onRemove: (_) => false,
          ),
        ),
      );
      await tester.drag(find.text('In stock'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(toggles, 0);

      final handle = find.byIcon(Icons.drag_indicator).first;
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(toggles, 0);

      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(toggles, 0);
    });

    testWidgets('only a settled row with an item opens', (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        _app(
          _list([
            ReviewEntry(path: 'p1', number: 1, stage: ReadStage.notRead),
            ReviewEntry(path: 'b', decodeFailed: true),
          ], onToggleCard: (_) => toggles++),
        ),
      );
      await tester.tap(find.text('Not read yet'));
      await tester.tap(find.text('Unreadable photo'));
      expect(toggles, 0);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets(
      'the arrow is a button for Rack-Wise Stock Balance and Stock Ageing',
      (tester) async {
        final handle = tester.ensureSemantics();
        String? toggled;
        Widget list(Set<String> open) => _app(
          _list(
            [_twoRackEntry],
            openCards: open,
            onToggleCard: (id) => toggled = id,
          ),
        );
        const label = 'Rack-Wise Stock Balance and Stock Ageing';
        await tester.pumpWidget(list(const {}));
        final arrow = find.bySemanticsLabel(label);
        expect(arrow, findsOneWidget);
        var data = tester.getSemantics(arrow).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isExpanded, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isTrue);

        await tester.pumpWidget(list({_twoRackEntry.id}));
        data = tester.getSemantics(arrow).getSemanticsData();
        expect(data.flagsCollection.isExpanded, Tristate.isTrue);

        tester.semantics.tap(find.semantics.byLabel(label));
        expect(toggled, _twoRackEntry.id);
        handle.dispose();
      },
    );

    testWidgets('dark mode: the open card keeps text at 4.5:1 or more', (
      tester,
    ) async {
      final entries = [
        _twoRackEntry,
        ReviewEntry(path: 'f', items: [_item('76543210', _inStock)]),
        ReviewEntry(path: 'o', items: [_item('55555550', null)]),
      ];
      // Tall enough for all three open cards to be built.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          _list(
            entries,
            openCards: {for (final e in entries) e.id},
            ageing: {
              _a: const AgeingState(AgeingStatus.ready, [_ageingA]),
              '7654321': const AgeingState(AgeingStatus.failed),
            },
          ),
          brightness: Brightness.dark,
        ),
      );
      expect(find.text('Age (0 - 90)'), findsOneWidget);
      expect(find.text("Couldn't load Stock Ageing."), findsOneWidget);
      expect(find.text('No stock in Finished Goods - KA.'), findsOneWidget);
      final ctx = tester.element(find.byType(ReviewList));
      final surface = ctx.scheme.fg;
      final colours = <Color>[];
      for (final c in tester.widgetList<Container>(find.byType(Container))) {
        final d = c.decoration;
        if (d is BoxDecoration && d.color != null) colours.add(d.color!);
      }
      expect(colours, isNot(contains(Colors.white)));
      var checked = 0;
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final style = t.style;
        final data = t.data;
        if (style?.color == null || data == null) continue;
        if (data == 'End of list') continue;
        final ink = style!.color!;
        final bg = (data == 'In stock' || data == 'Out of stock')
            ? Color.alphaBlend(ink.withValues(alpha: 0.13), surface)
            : surface;
        final over = Color.alphaBlend(ink, bg);
        final l1 = over.computeLuminance();
        final l2 = bg.computeLuminance();
        final ratio =
            (l1 > l2 ? l1 + 0.05 : l2 + 0.05) /
            (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '"$data" on $bg');
        checked++;
      }
      expect(checked, greaterThan(20));
    });
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

void _noop() {}
