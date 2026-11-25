import 'dart:ui' show SemanticsAction, Tristate;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/main.dart' show buildAppTheme;

SemanticsNode _action(WidgetTester tester, String name) =>
    tester.semantics.simulatedAccessibilityTraversal().singleWhere((node) {
      final data = node.getSemanticsData();
      return data.label == name || data.tooltip == name;
    });

void _activate(
  SemanticsNode node, [
  SemanticsAction action = SemanticsAction.tap,
]) {
  node.owner!.performAction(node.id, action);
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

class _Routes extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

class _Chip {
  const _Chip(this.id, this.label, {this.editable = true});

  final String id;
  final String label;
  final bool editable;
}

class _Fixture {
  _Fixture(List<_Chip> initial) : chips = initial.obs;

  final RxList<_Chip> chips;
  final filters = <String, dynamic>{'state': 'Draft'}.obs;
  final query = 'bolts'.obs;
  final enabled = ValueNotifier(true);
  final scroll = ScrollController();
  final operations = <String>[];
  final runFocus = FocusNode(debugLabel: 'Run report');
  final bottomFocus = FocusNode(debugLabel: 'Bottom control');
  late void Function(_Chip) reset = (chip) => chips.remove(chip);
  VoidCallback? bulkReset;
  final resetNodes = <String, FocusNode>{};
  final resetHooks = <String, VoidCallback>{};

  Widget host(
    Brightness brightness, {
    TextDirection direction = TextDirection.ltr,
    bool hasAdd = true,
    bool leading = false,
    bool includeBottom = false,
    bool hasQuick = true,
    List<NavigatorObserver> observers = const [],
  }) => MaterialApp(
    navigatorObservers: observers,
    theme: buildAppTheme(AppScheme.of(brightness), brightness),
    home: Directionality(
      textDirection: direction,
      child: Scaffold(
        drawer: leading ? const Drawer(child: Text('Drawer contents')) : null,
        body: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, enabled, child) => CustomScrollView(
            controller: scroll,
            slivers: [
              DocTypeListHeader(
                title: 'Item',
                activeFilters: filters,
                filtersEnabled: enabled,
                searchDoctype: 'Item',
                searchQuery: query,
                onSearchChanged: (text) => operations.add('Search $text'),
                onFilterTap: hasAdd ? () => operations.add('Filter') : null,
                onClearAllFilters: () {
                  operations.add('Bulk');
                  bulkReset?.call();
                },
                bottom: includeBottom
                    ? PreferredSize(
                        preferredSize: const Size.fromHeight(48),
                        child: TextButton(
                          focusNode: bottomFocus,
                          onPressed: () => operations.add('Bottom'),
                          child: const Text('Bottom control'),
                        ),
                      )
                    : null,
                extraActions: [
                  IconButton(
                    focusNode: runFocus,
                    tooltip: 'Run report',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => operations.add('Run'),
                  ),
                ],
                filterChipsBuilder: (_) => [
                  for (final chip in chips)
                    FilterChipWidget(
                      key: ValueKey(chip.id),
                      icon: Icons.label_outline,
                      label: chip.label,
                      resetFocusNode: resetNodes[chip.id],
                      onResetInvoked: resetHooks[chip.id],
                      onTap: chip.editable
                          ? () => operations.add('Edit ${chip.id}')
                          : null,
                      onDeleted: () {
                        operations.add('Reset ${chip.id}');
                        reset(chip);
                      },
                      resetSemanticLabel: chip.id == 'dismissable'
                          ? 'Remove warehouse filter'
                          : null,
                      dismissesChip: chip.id == 'dismissable',
                    ),
                ],
                quickChips: hasQuick
                    ? [
                        ChoiceChip(
                          label: const Text('View by item'),
                          selected: true,
                          onSelected: (_) => operations.add('View'),
                        ),
                      ]
                    : null,
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 1600)),
            ],
          ),
        ),
      ),
    ),
  );

  void dispose() {
    scroll.dispose();
    enabled.dispose();
    runFocus.dispose();
    bottomFocus.dispose();
  }
}

void main() {
  testWidgets(
    'Add reset-all funnel and search hit at their visible and padded edges',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 850);
      addTearDown(tester.view.reset);
      final fixture = _Fixture([
        const _Chip('state', 'Status: Draft'),
        const _Chip('area', 'Warehouse: Main'),
      ]);
      fixture.filters['area'] = 'Main';
      fixture.reset = (_) {};
      addTearDown(fixture.dispose);
      final routes = _Routes();
      await tester.pumpWidget(
        fixture.host(Brightness.light, hasQuick: false, observers: [routes]),
      );
      await tester.pumpAndSettle();

      final first = find.byKey(const ValueKey('state'));
      final edit = find.ancestor(
        of: find.text('Status: Draft'),
        matching: find.byType(TextButton),
      );
      final reset = find.ancestor(
        of: find.descendant(of: first, matching: find.byIcon(Icons.close)),
        matching: find.byType(TextButton),
      );
      final add = find.descendant(
        of: find.byType(AddFilterChip),
        matching: find.byType(TextButton),
      );
      final bulk = find.widgetWithText(TextButton, 'Reset filters');
      final funnel = find.byTooltip('Filters, 2 active');
      final search = find.byTooltip('Search Item, current query: bolts');

      for (final offset in [0.0, 180.0]) {
        fixture.scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        final actions = [
          (finder: edit, name: 'Edit Status: Draft', operation: 'Edit state'),
          (
            finder: reset,
            name: 'Reset Status: Draft',
            operation: 'Reset state',
          ),
          (finder: add, name: 'Add filter', operation: 'Filter'),
          (finder: bulk, name: 'Reset filters', operation: 'Bulk'),
          (finder: funnel, name: 'Filters, 2 active', operation: 'Filter'),
          (
            finder: search,
            name: 'Search Item, current query: bolts',
            operation: null,
          ),
        ];

        final targetRects = actions
            .map((action) => tester.getRect(action.finder))
            .toList();
        for (var index = 0; index < targetRects.length; index++) {
          final target = targetRects[index];
          for (final neighbor in targetRects.skip(index + 1)) {
            expect(target.overlaps(neighbor), isFalse);
          }
        }

        for (final action in actions) {
          final rect = tester.getRect(action.finder);
          final semanticsRect = _action(tester, action.name).rect;
          for (final size in [rect.size, semanticsRect.size]) {
            expect(size.width, greaterThanOrEqualTo(48), reason: action.name);
            expect(size.height, greaterThanOrEqualTo(48), reason: action.name);
          }
          final inside = rect.deflate(1);
          final points = [
            rect.center,
            inside.topLeft,
            inside.topRight,
            inside.bottomLeft,
            inside.bottomRight,
            if (action.finder == funnel)
              tester.getCenter(find.byType(CountBadge)),
            if (action.finder == search)
              tester.getCenter(
                find.byKey(const ValueKey('list-header-search-dot')),
              ),
          ];
          for (final point in points) {
            expect(rect.contains(point), isTrue);
            final before = fixture.operations.length;
            final pushes = routes.pushes;
            await tester.tapAt(point);
            await tester.pumpAndSettle();
            if (action.operation case final operation?) {
              expect(fixture.operations.skip(before), [
                operation,
              ], reason: action.name);
              expect(routes.pushes, pushes);
            } else {
              expect(routes.pushes, pushes + 1);
              final textBox = find.byType(EditableText);
              expect(textBox, findsOneWidget);
              Navigator.of(tester.element(textBox)).pop();
              await tester.pumpAndSettle();
              expect(fixture.operations, hasLength(before));
            }
          }
        }
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'one heading and one named button per action in ${brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        addTearDown(tester.view.reset);
        final fixture = _Fixture([
          const _Chip('state', 'Status: Draft'),
          const _Chip('dismissable', 'Warehouse: Main', editable: false),
        ]);
        addTearDown(fixture.dispose);
        await tester.pumpWidget(fixture.host(brightness));
        await tester.pumpAndSettle();

        for (final offset in [0.0, 46.0, 170.0]) {
          fixture.scroll.jumpTo(offset);
          await tester.pumpAndSettle();
          final headings = tester.semantics
              .simulatedAccessibilityTraversal()
              .where(
                (node) => node.getSemanticsData().flagsCollection.isHeader,
              );
          expect(headings.map((node) => node.label), ['Item']);
          expect(find.text('Item'), findsOneWidget);
        }

        for (final name in [
          'Run report',
          'Filters, 1 active',
          'Search Item, current query: bolts',
          'Edit Status: Draft',
          'Reset Status: Draft',
          'Remove warehouse filter',
          'Add filter',
          'Reset filters',
        ]) {
          final node = _action(tester, name);
          final data = node.getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue, reason: name);
          expect(data.flagsCollection.isSelected, Tristate.none, reason: name);
          expect(data.hasAction(SemanticsAction.tap), isTrue, reason: name);
          expect(node.rect.width, greaterThanOrEqualTo(48), reason: name);
          expect(node.rect.height, greaterThanOrEqualTo(48), reason: name);
        }

        final readOnly = _action(tester, 'Warehouse: Main').getSemanticsData();
        expect(readOnly.flagsCollection.isButton, isFalse);
        expect(readOnly.hasAction(SemanticsAction.tap), isFalse);
        final selected = _action(tester, 'View by item').getSemanticsData();
        expect(selected.flagsCollection.isSelected, Tristate.isTrue);
        expect(
          _action(
            tester,
            'Reset Status: Draft',
          ).getSemanticsData().hasAction(SemanticsAction.dismiss),
          isFalse,
        );
        final remove = _action(tester, 'Remove warehouse filter');
        expect(
          remove.getSemanticsData().hasAction(SemanticsAction.dismiss),
          isTrue,
        );

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        _activate(_action(tester, 'Edit Status: Draft'));
        await tester.pumpAndSettle();
        expect(fixture.operations, ['Edit state']);

        fixture.enabled.value = false;
        await tester.pumpAndSettle();
        for (final name in [
          'Filters, 1 active',
          'Edit Status: Draft',
          'Reset Status: Draft',
          'Remove warehouse filter',
          'Add filter',
          'Reset filters',
        ]) {
          final node = _action(tester, name);
          final data = node.getSemanticsData();
          expect(
            data.flagsCollection.isEnabled,
            Tristate.isFalse,
            reason: name,
          );
          expect(data.hasAction(SemanticsAction.tap), isFalse, reason: name);
          expect(
            data.hasAction(SemanticsAction.dismiss),
            isFalse,
            reason: name,
          );
        }
        _activate(_action(tester, 'Run report'));
        _activate(_action(tester, 'View by item'));
        await tester.tap(find.byType(AddFilterChip));
        expect(fixture.operations, ['Edit state', 'Run', 'View']);

        fixture.enabled.value = true;
        await tester.pumpAndSettle();
        _activate(
          _action(tester, 'Remove warehouse filter'),
          SemanticsAction.dismiss,
        );
        await tester.pumpAndSettle();
        expect(find.text('Warehouse: Main'), findsNothing);
        expect(fixture.operations.last, 'Reset dismissable');
      },
    );

    final direction = brightness == Brightness.light
        ? TextDirection.ltr
        : TextDirection.rtl;
    testWidgets(
      'Tab, Shift+Tab, Enter and Space traverse and activate in logical order '
      'in ${direction.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(411, 850);
        addTearDown(tester.view.reset);
        final fixture = _Fixture([
          const _Chip('a', 'Status: Draft'),
          const _Chip('b', 'Warehouse: Main'),
        ]);
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          fixture.host(
            brightness,
            direction: direction,
            leading: true,
            includeBottom: true,
          ),
        );
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(
          () => FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.automatic,
        );
        await tester.pumpAndSettle();

        double trailingGap(Rect from, Rect to) => direction == TextDirection.ltr
            ? to.left - from.right
            : from.left - to.right;

        final firstChip = find.byKey(const ValueKey('a'));
        final secondChip = find.byKey(const ValueKey('b'));
        final pill = find.descendant(
          of: firstChip,
          matching: find.byType(HeaderPill),
        );
        expect(
          trailingGap(tester.getRect(pill), tester.getRect(secondChip)),
          6,
        );
        final add = tester.getRect(find.byType(AddFilterChip));
        final bulk = tester.getRect(
          find.widgetWithText(TextButton, 'Reset filters'),
        );
        expect(trailingGap(add, bulk), 6);
        final divider = find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.margin ==
                    const EdgeInsetsDirectional.only(start: 2, end: 8),
          ),
          matching: find.byType(ColoredBox),
        );
        final dividerBounds = tester.getRect(divider);
        final quick = tester.getRect(find.byType(ChoiceChip));
        expect(dividerBounds.size, const Size(1, 20));
        expect(trailingGap(bulk, dividerBounds), 2);
        expect(trailingGap(dividerBounds, quick), 8);

        final order = [
          'Open navigation menu',
          'Run report',
          'Filters, 1 active',
          'Search Item, current query: bolts',
          'Bottom control',
          'Edit Status: Draft',
          'Reset Status: Draft',
          'Edit Warehouse: Main',
          'Reset Warehouse: Main',
          'Add filter',
          'Reset filters',
          'View by item',
        ];
        for (final label in order) {
          await _key(tester, LogicalKeyboardKey.tab);
          expect(
            _action(tester, label).getSemanticsData().flagsCollection.isFocused,
            Tristate.isTrue,
            reason: label,
          );
          expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue);
        }
        final verticalOffset = fixture.scroll.offset;
        await _key(tester, LogicalKeyboardKey.space);
        expect(fixture.operations, ['View']);
        expect(fixture.scroll.offset, verticalOffset);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await _key(tester, LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(
          _action(
            tester,
            'Reset filters',
          ).getSemanticsData().flagsCollection.isFocused,
          Tristate.isTrue,
        );
        await _key(tester, LogicalKeyboardKey.enter);
        expect(fixture.operations, ['View', 'Bulk']);
      },
    );
  }

  testWidgets(
    'nonreactive header actions remain available without a chip row',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                DocTypeListHeader(
                  title: 'Dashboard',
                  extraActions: [
                    IconButton(
                      onPressed: () => calls++,
                      tooltip: 'Open report',
                      icon: const Icon(Icons.list),
                    ),
                  ],
                  filterChipsBuilder: (_) => const [
                    Chip(label: Text('Unavailable')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Unavailable'), findsNothing);
      expect(find.byType(AddFilterChip), findsNothing);
      _activate(_action(tester, 'Open report'));
      expect(calls, 1);
    },
  );

  testWidgets(
    'removing a focused chip restores focus after the committed change',
    (tester) async {
      final a = const _Chip('a', 'One');
      final b = const _Chip('b', 'Two');
      final c = const _Chip('c', 'Three', editable: false);
      final fixture = _Fixture([a, b, c]);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.host(Brightness.light));
      await tester.pumpAndSettle();

      final reset = find.ancestor(
        of: find.descendant(
          of: find.byKey(const ValueKey('b')),
          matching: find.byIcon(Icons.close),
        ),
        matching: find.byType(TextButton),
      );
      final resetFocus = tester.widget<TextButton>(reset).focusNode!;
      resetFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, resetFocus);

      fixture.reset = (_) {};
      await _key(tester, LogicalKeyboardKey.enter);
      expect(FocusManager.instance.primaryFocus, resetFocus);
      expect(fixture.operations, ['Reset b']);

      fixture.chips.remove(b);
      await tester.pumpAndSettle();
      expect(
        _action(
          tester,
          'Reset Three',
        ).getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
      );
      fixture.reset = (chip) => fixture.chips.remove(chip);
      await _key(tester, LogicalKeyboardKey.space);
      expect(fixture.operations, ['Reset b', 'Reset c']);
      expect(
        _action(
          tester,
          'Add filter',
        ).getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
      );

      final resetOne = find.ancestor(
        of: find.descendant(
          of: find.byKey(const ValueKey('a')),
          matching: find.byIcon(Icons.close),
        ),
        matching: find.byType(TextButton),
      );
      tester.widget<TextButton>(resetOne).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.enter);
      expect(fixture.chips, isEmpty);
      expect(fixture.operations, ['Reset b', 'Reset c', 'Reset a']);
      expect(
        _action(
          tester,
          'Add filter',
        ).getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
      );
    },
  );

  testWidgets(
    'reset keeps distinct duplicate targets and respects later focus and routes',
    (tester) async {
      final first = const _Chip('first', 'Duplicate');
      final second = const _Chip('second', 'Duplicate');
      final fixture = _Fixture([first, second]);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.host(Brightness.light, hasAdd: false));
      await tester.pumpAndSettle();

      FocusNode resetFocus(String id) => tester
          .widget<TextButton>(
            find.ancestor(
              of: find.descendant(
                of: find.byKey(ValueKey(id)),
                matching: find.byIcon(Icons.close),
              ),
              matching: find.byType(TextButton),
            ),
          )
          .focusNode!;

      expect(resetFocus('first'), isNot(same(resetFocus('second'))));
      resetFocus('second').requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.enter);
      expect(fixture.chips, [first]);
      expect(fixture.operations, ['Reset second']);
      expect(
        _action(
          tester,
          'Edit Duplicate',
        ).getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
      );

      fixture.reset = (_) {};
      final stableReset = resetFocus('first');
      stableReset.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.enter);
      fixture.chips[0] = const _Chip('first', 'Restored default');
      await tester.pumpAndSettle();
      expect(resetFocus('first'), same(stableReset));
      expect(FocusManager.instance.primaryFocus, same(stableReset));

      fixture.runFocus.requestFocus();
      await tester.pumpAndSettle();
      fixture.chips.clear();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(fixture.runFocus));

      fixture.chips.add(first);
      await tester.pumpAndSettle();
      resetFocus('first').requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.enter);
      final route = Navigator.of(
        tester.element(find.byType(DocTypeListHeader)),
      );
      final destination = FocusNode(debugLabel: 'New route');
      addTearDown(destination.dispose);
      route.push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            body: TextButton(
              autofocus: true,
              focusNode: destination,
              onPressed: () {},
              child: const Text('New route'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      fixture.chips.clear();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(destination));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'last reset restores a keyboard target when the entire row leaves',
    (tester) async {
      final fixture = _Fixture([const _Chip('one', 'Status: Draft')]);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        fixture.host(Brightness.light, hasAdd: false, hasQuick: false),
      );
      await tester.pumpAndSettle();
      final row = find.byType(SingleChildScrollView);
      expect(row, findsOneWidget);

      final reset = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(TextButton),
      );
      tester.widget<TextButton>(reset).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.enter);
      expect(fixture.operations, ['Reset one']);
      expect(row, findsNothing);

      final focused =
          [
            _action(tester, 'Run report'),
            _action(tester, 'Search Item, current query: bolts'),
          ].where(
            (node) =>
                node.getSemanticsData().flagsCollection.isFocused ==
                Tristate.isTrue,
          );
      expect(focused, hasLength(1));
    },
  );

  testWidgets('keyboard bulk reset moves focus to the surviving Add filter', (
    tester,
  ) async {
    final fixture = _Fixture([
      const _Chip('a', 'One'),
      const _Chip('b', 'Two'),
    ]);
    addTearDown(fixture.dispose);
    fixture.bulkReset = () {
      fixture.filters.clear();
      fixture.query.value = '';
      fixture.chips.clear();
    };
    await tester.pumpWidget(fixture.host(Brightness.light));
    await tester.pumpAndSettle();
    final bulk = find.ancestor(
      of: find.text('Reset filters'),
      matching: find.byType(TextButton),
    );
    Focus.of(tester.element(find.text('Reset filters'))).requestFocus();
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(bulk).getSemanticsData().flagsCollection.isFocused,
      Tristate.isTrue,
    );
    await _key(tester, LogicalKeyboardKey.enter);
    expect(fixture.operations, ['Bulk']);
    expect(bulk, findsNothing);
    expect(
      _action(
        tester,
        'Add filter',
      ).getSemanticsData().flagsCollection.isFocused,
      Tristate.isTrue,
    );
  });

  testWidgets('Back restores focus after the search chip caption changes', (
    tester,
  ) async {
    final query = 'blue'.obs;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              DocTypeListHeader(
                title: 'Sales Order',
                searchQuery: query,
                filterChipsBuilder: (context) => [
                  FilterChipWidget(
                    icon: Icons.search,
                    label: 'Search: ${query.value}',
                    onTap: () => showListSearch(
                      context,
                      query: query.value,
                      onSearchChanged: (value) => query.value = value,
                    ),
                    onDeleted: () => query.value = '',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    Focus.of(tester.element(find.text('Search: blue'))).requestFocus();
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.enter);
    await tester.enterText(find.byType(TextField), 'green');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(query.value, 'green');
    expect(
      _action(
        tester,
        'Edit Search: green',
      ).getSemanticsData().flagsCollection.isFocused,
      Tristate.isTrue,
    );
  });

  testWidgets('external reset nodes and caller hooks participate in recovery', (
    tester,
  ) async {
    final fixture = _Fixture([
      const _Chip('a', 'One'),
      const _Chip('b', 'Two', editable: false),
    ]);
    final external = FocusNode();
    final successor = FocusNode();
    addTearDown(fixture.dispose);
    addTearDown(external.dispose);
    addTearDown(successor.dispose);
    fixture.resetNodes.addAll({'a': external, 'b': successor});
    fixture.resetHooks['a'] = () => fixture.operations.add('Caller hook');
    await tester.pumpWidget(fixture.host(Brightness.light));
    await tester.pumpAndSettle();
    external.requestFocus();
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.enter);
    expect(fixture.operations, ['Caller hook', 'Reset a']);
    expect(FocusManager.instance.primaryFocus, same(successor));
    await tester.pumpWidget(const SizedBox.shrink());
    void listener() {}
    external.addListener(listener);
    successor.addListener(listener);
    external.removeListener(listener);
    successor.removeListener(listener);
  });

  testWidgets(
    'removing a filter while its page leaves disposes its nodes once',
    (tester) async {
      final pages = PageController();
      final filters = {'One': 'A', 'Two': 'B'}.obs;
      addTearDown(pages.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView.builder(
              controller: pages,
              itemCount: 5,
              itemBuilder: (_, index) => index == 0
                  ? CustomScrollView(
                      slivers: [
                        DocTypeListHeader(
                          title: 'List',
                          activeFilters: filters,
                          onFilterTap: () {},
                          filterChipsBuilder: (_) => [
                            for (final name in filters.keys)
                              FilterChipWidget(
                                key: ValueKey(name),
                                label: name,
                                icon: Icons.place,
                                onTap: () {},
                                onDeleted: () => filters.remove(name),
                              ),
                          ],
                        ),
                      ],
                    )
                  : Text('Page $index'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('One'), findsOneWidget);
      filters.remove('One');
      pages.jumpToPage(4);
      await tester.pumpAndSettle();
      expect(find.text('Page 4'), findsOneWidget);
      expect(find.byType(DocTypeListHeader, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('collapse reuses the laid-out chip widgets across offsets', (
    tester,
  ) async {
    final fixture = _Fixture([
      for (var index = 0; index < 10; index++) _Chip('$index', 'Filter $index'),
    ]);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.host(Brightness.light));
    await tester.pumpAndSettle();
    final chips = find.byType(FilterChipWidget);
    final original = tester.widgetList<FilterChipWidget>(chips).toList();
    expect(original, hasLength(10));
    for (final offset in [3.0, 15.0, 35.0, 68.0, 0.0]) {
      fixture.scroll.jumpTo(offset);
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<FilterChipWidget>(chips),
        orderedEquals(original),
      );
    }
  });
}
