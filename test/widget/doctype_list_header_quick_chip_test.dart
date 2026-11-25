import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/header_chip_band.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_cache.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_fields.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_screen.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../support/report_fields_test_kit.dart';

class _ReportCache extends StockAgeingCache {
  _ReportCache({this.populate = false});

  final bool populate;

  @override
  Future<StockAgeingSnapshot?> read(FieldsScope scope) async =>
      StockAgeingSnapshot(
        fetchedAt: DateTime.now(),
        columns: const [
          {'fieldname': 'average_age', 'label': 'Average Age'},
          {'fieldname': 'qty', 'label': 'Available Qty'},
          {'fieldname': 'range1', 'label': 'Age (0 - 90)'},
          {'fieldname': 'item_code', 'label': 'Item Code'},
        ],
        rows: [
          if (populate)
            for (var i = 0; i < 30; i++)
              {'item_code': 'Stock item $i', 'qty': i},
        ],
        defaults: const {},
      );
}

StockAgeingController _stockReport({bool populate = false}) {
  final owner = ReportFieldsTestOwner()..change('https://erp.example', 'Buyer');
  final store = ScopedReportFieldsStore(
    database: ReportFieldsTestConfig(),
    storage: ReportFieldsTestStorage(),
  );
  ScopedReportFieldsController fields(ReportFieldsDefinition definition) =>
      ScopedReportFieldsController(
        definition: definition,
        owner: owner,
        store: store,
      );
  return Get.put(
    StockAgeingController(
      cache: _ReportCache(populate: populate),
      fields: fields(stockAgeingFields()),
      view: fields(stockAgeingView),
      run: ({filters}) => throw StateError('Unexpected report fetch'),
      company: () => '',
      baseUrl: () => '',
    ),
  );
}

Finder _raw(Finder chip) =>
    find.descendant(of: chip, matching: find.byType(RawChip));

ShapeDecoration _decoration(WidgetTester tester, Finder chip) =>
    tester
            .widget<Ink>(find.descendant(of: chip, matching: find.byType(Ink)))
            .decoration!
        as ShapeDecoration;

BorderSide _side(WidgetTester tester, Finder chip) =>
    (_decoration(tester, chip).shape as OutlinedBorder).side;

Finder _headerChip(String label) => find.byWidgetPredicate(
  (widget) => widget is HeaderChipButton && widget.label == label,
);

Iterable<SemanticsNode> _semanticsInTraversalOrder(SemanticsNode node) sync* {
  yield node;
  for (final child in node.debugListChildrenInOrder(
    DebugSemanticsDumpOrder.traversalOrder,
  )) {
    yield* _semanticsInTraversalOrder(child);
  }
}

Future<void> _tapEdges(
  WidgetTester tester,
  Finder chip, {
  required VoidCallback afterTop,
  required VoidCallback afterBottom,
}) async {
  final raw = _raw(chip);
  final rect = tester.getRect(raw);
  final node = tester.getSemantics(raw);
  expect(rect.width, greaterThanOrEqualTo(48));
  expect(rect.height, greaterThanOrEqualTo(48));
  expect(node.rect.width, greaterThanOrEqualTo(48));
  expect(node.rect.height, greaterThanOrEqualTo(48));
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
  await tester.pump(const Duration(milliseconds: 300));
  afterTop();
  final updated = tester.getRect(raw);
  await tester.tapAt(Offset(updated.center.dx, updated.bottom - 1));
  await tester.pump(const Duration(milliseconds: 300));
  afterBottom();
}

void main() {
  const stockFont = 'StockHeaderInter';
  setUpAll(() async {
    final inter = FontLoader(stockFont)
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Medium.ttf'));
    await inter.load();
  });
  testWidgets('all four Stock Ageing sorts respond at both vertical edges', (
    tester,
  ) async {
    final controller = _stockReport();
    addTearDown(Get.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          AppScheme.dark,
          Brightness.dark,
          accent: AppAccent.purple,
        ),
        home: const StockAgeingScreen(),
      ),
    );
    await tester.pumpAndSettle();

    for (final id in ['age', 'qty', 'old', 'code']) {
      final quick = find.byKey(ValueKey(id));
      final action = find.descendant(
        of: quick,
        matching: find.byType(TextButton),
      );
      expect(
        tester.widget<HeaderQuickChip>(quick).role,
        HeaderQuickRole.choice,
      );
      for (final top in [true, false]) {
        controller.setSort(id == 'age' ? 'qty' : 'age');
        await tester.pump();
        final rect = tester.getRect(action);
        final node = tester.getSemantics(action);
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, 48);
        expect(node.rect.height, rect.height);
        expect(node.rect.width, rect.width);
        expect(
          node.getSemanticsData().flagsCollection.isSelected,
          Tristate.isFalse,
        );
        await tester.tapAt(
          Offset(rect.center.dx, top ? rect.top + 1 : rect.bottom - 1),
        );
        await tester.pump();
        expect(controller.sort.value, id);
        expect(tester.getRect(action), rect);
        expect(
          tester
              .getSemantics(action)
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
      }
    }
  });

  testWidgets(
    'Stock Ageing puts the Average Age check above its scaled caption in a narrow RTL pane',
    (tester) async {
      addTearDown(Get.reset);
      final controller = _stockReport();
      final theme = buildAppTheme(AppScheme.light, Brightness.light);
      final stockTheme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: stockFont),
      );
      await tester.pumpWidget(
        MaterialApp(theme: stockTheme, home: const StockAgeingScreen()),
      );
      await tester.pumpAndSettle();

      final averageAge = find.byKey(const ValueKey('age'));
      final choice = tester.widget<HeaderQuickChip>(averageAge);
      await tester.pumpWidget(
        MaterialApp(
          theme: stockTheme,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 84,
                      child: CustomScrollView(
                        slivers: [
                          DocTypeListHeader(title: 'A', quickChips: [choice]),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 1000),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tick = find.descendant(
        of: averageAge,
        matching: find.byIcon(Icons.check),
      );
      final caption = find.descendant(
        of: averageAge,
        matching: find.text('Average Age'),
      );
      expect(controller.sort.value, 'age');
      expect(tick, findsOneWidget);
      expect(caption, findsOneWidget);
      final text = tester.renderObject<RenderParagraph>(caption);
      expect(text.didExceedMaxLines, isFalse);
      expect(
        tester.getRect(tick).bottom,
        lessThanOrEqualTo(tester.getRect(caption).top),
      );
      expect(
        tester.getRect(averageAge).contains(tester.getRect(caption).center),
        isTrue,
      );
    },
  );

  testWidgets('Stock Ageing moves the tooltip with directional Edit focus', (
    tester,
  ) async {
    addTearDown(Get.reset);
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final focus = FocusManager.instance;
    final highlightStrategy = focus.highlightStrategy;
    focus.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => focus.highlightStrategy = highlightStrategy);
    final controller = _stockReport(populate: true);
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: stockFont),
        ),
        home: const StockAgeingScreen(),
      ),
    );
    await tester.pumpAndSettle();
    const item = 'Item: 100';
    const warehouse = 'Warehouse-wise: off';
    controller.activeFilters.assignAll({
      'item_code': item,
      'show_warehouse_wise_stock': warehouse,
    });
    await tester.pumpAndSettle();

    FocusNode editFocus(String caption) => tester
        .widget<HeaderChipButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is HeaderChipButton && widget.label == 'Edit $caption',
          ),
        )
        .focusNode!;
    Finder overlayCaption(String caption) => find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == caption,
    );

    final itemEdit = editFocus(item);
    final warehouseEdit = editFocus(warehouse);
    itemEdit.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.primaryFocus, same(itemEdit));
    expect(overlayCaption(item), findsNWidgets(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focus.primaryFocus, same(warehouseEdit));
    expect(overlayCaption(item), findsOneWidget);
    expect(overlayCaption(warehouse), findsNWidgets(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focus.primaryFocus, same(itemEdit));
    expect(overlayCaption(item), findsNWidgets(2));
    expect(overlayCaption(warehouse), findsOneWidget);
  });

  for (final scale in [.85, 1.0, 1.3]) {
    testWidgets('Stock Ageing exposes all wraps before gestures at ${scale}x', (
      tester,
    ) async {
      const dpr = 2.625;
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = const Size(411 * dpr, 914 * dpr);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(Get.reset);
      final controller = _stockReport(populate: true);
      final theme = buildAppTheme(AppScheme.light, Brightness.light);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: stockFont),
          ),
          home: const StockAgeingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final sliverFinder = find.byType(SliverPersistentHeader);
      final band = find.byKey(const ValueKey('list-header-chip-band'));
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      final scroll = tester.state<ScrollableState>(scrollable.first).position;
      final all = <String, String>{
        'item_code': 'Item: 1002890',
        'show_warehouse_wise_stock': 'Warehouse-wise: off',
      };
      for (final count in [0, 1, 2]) {
        scroll.jumpTo(0);
        controller.activeFilters.assignAll(
          Map.fromEntries(all.entries.take(count)),
        );
        await tester.pump();
        final header = tester.widget<SliverPersistentHeader>(sliverFinder);
        expect(header.pinned, isTrue);
        final height = tester.getSize(band).height;
        expect(height, greaterThanOrEqualTo(100));
        if (count == 2 && scale == 1) {
          expect(height, 204);
          expect(header.delegate.maxExtent, 356);
          expect(header.delegate.minExtent, 260);
        }
        for (final offset in [0.0, 35.0, 120.0]) {
          scroll.jumpTo(offset);
          await tester.pump();
          final bounds = tester.getRect(band);
          final sliver = tester.renderObject<RenderSliverPersistentHeader>(
            sliverFinder,
          );
          expect(
            bounds.bottom,
            closeTo(
              sliver.child!
                  .localToGlobal(Offset(0, sliver.child!.size.height))
                  .dy,
              .01,
            ),
          );
          expect(
            find.descendant(of: band, matching: find.byType(Scrollable)),
            findsNothing,
          );
          final buttons = find.descendant(
            of: band,
            matching: find.byType(TextButton),
          );
          expect(buttons, findsNWidgets(5 + 2 * count + (count == 2 ? 1 : 0)));
          for (final action in buttons.evaluate()) {
            final target = find.byElementPredicate(
              (element) => identical(element, action),
            );
            final rect = tester.getRect(target);
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.left, greaterThanOrEqualTo(bounds.left + 12 - .01));
            expect(rect.right, lessThanOrEqualTo(bounds.right - 12 + .01));
            expect(bounds.inflate(.01).contains(rect.bottomRight), isTrue);
            expect(target.hitTestable(), findsOneWidget);
            final semanticRect = tester.getSemantics(target).rect;
            expect(semanticRect.size, rect.size);
          }
          for (final caption in [
            'Average Age',
            'Available Qty',
            'Age (0 - 90)',
            'Item Code',
            ...all.values.take(count),
          ]) {
            final text = find.descendant(
              of: band,
              matching: find.text(caption),
            );
            expect(text.hitTestable(), findsOneWidget);
            expect(
              tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
              isFalse,
            );
          }
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  Future<StockAgeingController> pumpStock(
    WidgetTester tester, {
    required Size size,
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(Get.reset);
    final controller = _stockReport(populate: true);
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: stockFont),
        ),
        home: Directionality(
          textDirection: direction,
          child: const StockAgeingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('Stock Ageing reveals wrapped focus in both Tab directions', (
    tester,
  ) async {
    await pumpStock(tester, size: const Size(320, 230), scale: 2);
    final quantity = find.widgetWithText(TextButton, 'Available Qty');
    final oldestBucket = find.widgetWithText(TextButton, 'Age (0 - 90)');
    final itemCode = find.widgetWithText(TextButton, 'Item Code');
    final scrollable = Scrollable.of(
      tester.element(quantity),
      axis: Axis.vertical,
    );
    final scroll = scrollable.position;
    final viewport = tester.getRect(find.byWidget(scrollable.widget));
    // Arrange keyboard traversal from Available Qty at the bottom of the viewport.
    final quantityFocus = Focus.of(
      tester.element(
        find.descendant(of: quantity, matching: find.text('Available Qty')),
      ),
    );
    quantityFocus.requestFocus();
    scroll.jumpTo(
      scroll.pixels + tester.getRect(quantity).bottom - viewport.bottom,
    );
    await tester.pumpAndSettle();

    void expectVisible(Finder action) {
      final focus = Focus.of(
        tester.element(
          find.descendant(of: action, matching: find.byType(Text)),
        ),
      );
      expect(focus.hasPrimaryFocus, isTrue);
      final rect = tester.getRect(action);
      expect(rect.top, greaterThanOrEqualTo(viewport.top - .01));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + .01));
    }

    expectVisible(quantity);
    for (final action in [oldestBucket, itemCode]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectVisible(action);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (final action in [oldestBucket, quantity]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectVisible(action);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  for (final direction in TextDirection.values) {
    testWidgets('Stock Ageing exports band order in ${direction.name}', (
      tester,
    ) async {
      final controller = await pumpStock(
        tester,
        size: const Size(411, 800),
        direction: direction,
      );
      final root = tester
          .binding
          .renderViews
          .single
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!;
      List<String> labels(List<String> expected) => _semanticsInTraversalOrder(
        root,
      ).map((node) => node.label).where(expected.contains).toList();
      const sorts = [
        'Sort by Average Age',
        'Sort by Available Qty',
        'Sort by Age (0 - 90)',
        'Sort by Item Code',
      ];
      expect(labels(sorts), sorts);

      tester.view.physicalSize = const Size(320, 800);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      controller.activeFilters['item_code'] = 'Item: 1002890';
      await tester.pumpAndSettle();
      const split = ['Add filter', 'Edit Item: 1002890', 'Reset Item: 1002890'];
      expect(labels([...split, ...sorts]), [...split, ...sorts]);
    });
  }

  testWidgets('Stock Ageing tabs into a filter inserted after Add', (
    tester,
  ) async {
    final controller = await pumpStock(tester, size: const Size(411, 800));
    final add = tester
        .widget<HeaderChipButton>(_headerChip('Add filter'))
        .focusNode!;
    add.requestFocus();
    await tester.pumpAndSettle();
    controller.activeFilters['item_code'] = 'Item: 1002890';
    await tester.pumpAndSettle();
    final edit = tester
        .widget<HeaderChipButton>(_headerChip('Edit Item: 1002890'))
        .focusNode!;
    final reset = tester
        .widget<HeaderChipButton>(_headerChip('Reset Item: 1002890'))
        .focusNode!;
    expect(add.hasPrimaryFocus, isTrue);
    for (final node in [edit, reset]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue, reason: node.debugLabel);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (final node in [edit, add]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue, reason: node.debugLabel);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  for (final accent in [AppAccent.purple, AppAccent.brand]) {
    testWidgets(
      'native compact quick chip padding redirects top and bottom taps [dark ${accent.name}]',
      (tester) async {
        final viewFocus = FocusNode(debugLabel: 'View');
        final stockFocus = FocusNode(debugLabel: 'In stock');
        final originalStrategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() {
          FocusManager.instance.highlightStrategy = originalStrategy;
          viewFocus.dispose();
          stockFocus.dispose();
        });
        var inStock = false;
        var savingView = false;
        late StateSetter rebuild;
        final theme = buildAppTheme(
          AppScheme.dark,
          Brightness.dark,
          accent: accent,
        );
        final palette = HeaderPalette(theme);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return CustomScrollView(
                    slivers: [
                      DocTypeListHeader(
                        title: 'Quick filters',
                        quickChips: [
                          FilterChip(
                            key: const ValueKey('stock'),
                            focusNode: stockFocus,
                            selected: inStock,
                            visualDensity: VisualDensity.compact,
                            onSelected: (value) =>
                                setState(() => inStock = value),
                            label: const Text('In Stock'),
                          ),
                          Tooltip(
                            message: 'View',
                            excludeFromSemantics: true,
                            child: ActionChip(
                              key: const ValueKey('view'),
                              focusNode: viewFocus,
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                await showModalBottomSheet<void>(
                                  context: context,
                                  builder: (_) => const Text('View options'),
                                );
                                if (context.mounted) viewFocus.requestFocus();
                              },
                              label: Semantics(
                                label: 'View',
                                value: 'Item, Availability, descending',
                                excludeSemantics: true,
                                child: const Text('Availability ↓'),
                              ),
                              avatar: savingView
                                  ? Semantics(
                                      label: 'Saving View',
                                      liveRegion: true,
                                      child: Center(
                                        child: SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 800)),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final stock = find.byKey(const ValueKey('stock'));
        final view = find.byKey(const ValueKey('view'));
        await _tapEdges(
          tester,
          stock,
          afterTop: () => expect(inStock, isTrue),
          afterBottom: () => expect(inStock, isFalse),
        );
        for (final top in [true, false]) {
          final rect = tester.getRect(_raw(view));
          expect(rect.height, greaterThanOrEqualTo(48));
          await tester.tapAt(
            Offset(rect.center.dx, top ? rect.top + 1 : rect.bottom - 1),
          );
          await tester.pumpAndSettle();
          expect(find.text('View options'), findsOneWidget);
          Navigator.of(tester.element(find.text('View options'))).pop();
          await tester.pumpAndSettle();
          expect(viewFocus.hasPrimaryFocus, isTrue);
        }

        rebuild(() => inStock = true);
        await tester.pumpAndSettle();
        stockFocus.requestFocus();
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(stockFocus));
        expect(
          _decoration(tester, stock).color,
          theme.colorScheme.secondaryContainer,
        );
        expect(_side(tester, stock).width, 2);
        final selected = tester.getSemantics(_raw(stock)).getSemanticsData();
        expect(selected.flagsCollection.isSelected, Tristate.isTrue);
        expect(
          tester.widget<RawChip>(_raw(stock)).showCheckmark ?? true,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(viewFocus));

        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: const Offset(1, 1));
        final center = tester.getCenter(view);
        await pointer.moveTo(center);
        await tester.pumpAndSettle();
        expect(_side(tester, view).width, 2);
        await pointer.down(center);
        await tester.pump(const Duration(milliseconds: 150));
        expect(_side(tester, view).width, 3);
        final nativeTheme = Theme.of(tester.element(_raw(view)));
        expect(nativeTheme.highlightColor, palette.quickPressedLayer);
        expect(nativeTheme.hoverColor, Colors.transparent);
        expect(nativeTheme.focusColor, Colors.transparent);
        expect(nativeTheme.splashFactory, NoSplash.splashFactory);

        rebuild(() => savingView = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(_side(tester, view).width, 3);
        final saving = tester.semantics
            .simulatedAccessibilityTraversal()
            .singleWhere(
              (node) => node.getSemanticsData().label.contains('Saving View'),
            );
        expect(saving.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await pointer.cancel();
        await pointer.removePointer();
        rebuild(() => savingView = false);
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'pricing bottom and form selectable chips share the focus contour',
    (tester) async {
      const pricingKey = ValueKey('pricing');
      const formKey = ValueKey('form');
      final theme = buildAppTheme(AppScheme.dark, Brightness.dark);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                DocTypeListHeader(
                  title: 'Pricing',
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: Center(
                      child: SelectableFilterChip(
                        key: pricingKey,
                        label: 'Selling',
                        selected: false,
                        onSelected: (_) {},
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: SelectableFilterChip(
                      key: formKey,
                      label: 'Pending',
                      selected: false,
                      onSelected: (_) {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final pricing = find.byKey(pricingKey);
      final form = find.byKey(formKey);
      for (final chip in [pricing, form]) {
        final scoped = Theme.of(tester.element(_raw(chip)));
        expect(scoped.highlightColor, HeaderPalette(theme).quickPressedLayer);
        expect(scoped.focusColor, Colors.transparent);
        expect(_side(tester, chip).color, AppScheme.dark.textMuted);
        expect(tester.getSize(_raw(chip)).height, 48);
      }
    },
  );
}
