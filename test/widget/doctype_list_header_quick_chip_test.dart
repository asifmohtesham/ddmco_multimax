import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_cache.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_screen.dart';
import 'package:multimax/main.dart' show buildAppTheme;

class _ReportCache extends StockAgeingCache {
  @override
  Future<StockAgeingSnapshot?> read() async => StockAgeingSnapshot(
    fetchedAt: DateTime.now(),
    columns: const [],
    rows: const [],
    defaults: const {},
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
  testWidgets('native Stock Ageing sort chip redirects top and bottom taps', (
    tester,
  ) async {
    final controller = Get.put(
      StockAgeingController(
        cache: _ReportCache(),
        run: ({filters}) => throw StateError('Unexpected report fetch'),
        loadCardFields: () => null,
        company: () => '',
      ),
    );
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

    final quantity = find.widgetWithText(ChoiceChip, 'Quantity');
    expect(controller.sort.value, 'age');
    await _tapEdges(
      tester,
      quantity,
      afterTop: () {
        expect(controller.sort.value, 'qty');
        controller.setSort('age');
      },
      afterBottom: () => expect(controller.sort.value, 'qty'),
    );
    expect(
      tester
          .getSemantics(_raw(quantity))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
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
    'pricing bottom selectable chips use the header interaction theme',
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
                    preferredSize: const Size.fromHeight(40),
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
      final pricedTheme = Theme.of(tester.element(_raw(pricing)));
      final formTheme = Theme.of(tester.element(_raw(form)));
      expect(
        pricedTheme.highlightColor,
        HeaderPalette(theme).quickPressedLayer,
      );
      expect(pricedTheme.focusColor, Colors.transparent);
      expect(_side(tester, pricing).color, AppScheme.dark.textMuted);
      expect(tester.getSize(_raw(pricing)).height, lessThanOrEqualTo(40));
      expect(formTheme.highlightColor, theme.highlightColor);
      expect(formTheme.focusColor, theme.focusColor);
    },
  );
}
