import 'dart:ui' show SemanticsAction;

// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/main.dart' show buildAppTheme;

void main() {
  _wideBadgeContracts();

  for (final size in [
    const Size(360, 800),
    const Size(800, 360),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'filter badge stays inside toolbar at ${size.width} × ${size.height}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const title = 'Item Variant Details';
        final filters = <String, dynamic>{'item_group': 'Belts'}.obs;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  DocTypeListHeader(
                    title: title,
                    automaticallyImplyLeading: false,
                    activeFilters: filters,
                    onFilterTap: () {},
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                ],
              ),
            ),
          ),
        );

        void expectBadgeInsideToolbar() {
          final toolbar = tester.getRect(find.byType(NavigationToolbar));
          final badge = tester.getRect(find.byType(CountBadge));
          expect(badge.left, greaterThanOrEqualTo(toolbar.left));
          expect(badge.right, lessThanOrEqualTo(toolbar.right));
          expect(badge.right, lessThanOrEqualTo(size.width));
          expect(badge.top, greaterThanOrEqualTo(toolbar.top));
          expect(badge.bottom, lessThanOrEqualTo(toolbar.bottom));
        }

        expect(
          find.descendant(
            of: find.byType(NavigationToolbar),
            matching: find.text(title),
          ),
          findsNothing,
        );
        expectBadgeInsideToolbar();

        await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(NavigationToolbar),
            matching: find.text(title),
          ),
          findsOneWidget,
        );
        expectBadgeInsideToolbar();
      },
    );
  }
}

const filterSlot = ValueKey<String>('list-header-filter-slot');
const searchDot = ValueKey<String>('list-header-search-dot');

class _Routes extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void _wideBadgeContracts() {
  for (final width in [320.0, 411.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final direction in TextDirection.values) {
        for (final brightness in Brightness.values) {
          testWidgets(
            'wide badges and active dots stay inside the tappable slot at '
            '$width dp, ${scale}x, ${direction.name}, ${brightness.name}',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = Size(width, 800);
              addTearDown(tester.view.reset);
              final navigator = GlobalKey<NavigatorState>();
              final routes = _Routes();
              final scroll = ScrollController();
              addTearDown(scroll.dispose);
              final filters = <String, dynamic>{}.obs;
              final query = 'bolts'.obs;
              var filterTaps = 0;
              await tester.pumpWidget(
                MaterialApp(
                  navigatorKey: navigator,
                  navigatorObservers: [routes],
                  theme: buildAppTheme(AppScheme.of(brightness), brightness),
                  home: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: Directionality(
                        textDirection: direction,
                        child: Scaffold(
                          body: CustomScrollView(
                            controller: scroll,
                            slivers: [
                              DocTypeListHeader(
                                title: 'Item',
                                activeFilters: filters,
                                onFilterTap: () => filterTaps++,
                                searchQuery: query,
                                onSearchChanged: (_) {},
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 1600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );

              const searchLabel = 'Search, current query: bolts';
              final badge = find.byType(CountBadge);
              final slot = find.byKey(filterSlot);
              final dot = find.byKey(searchDot);
              final search = find.byTooltip(searchLabel);
              int expectedFilterTaps = 0;

              void expectWithin(Rect outer, Rect inner) {
                expect(inner.left, greaterThanOrEqualTo(outer.left));
                expect(inner.right, lessThanOrEqualTo(outer.right));
                expect(inner.top, greaterThanOrEqualTo(outer.top));
                expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
              }

              void verifyGeometry() {
                final slotRect = tester.getRect(slot);
                final badgeRect = tester.getRect(badge);
                final searchRect = tester.getRect(search);
                final dotRect = tester.getRect(dot);
                final rtl = direction == TextDirection.rtl;
                expectWithin(slotRect, badgeRect);
                expectWithin(searchRect, dotRect);
                expect(slotRect.overlaps(searchRect), isFalse);
                expect(slotRect.left, greaterThanOrEqualTo(0));
                expect(slotRect.right, lessThanOrEqualTo(width));
                expect(slotRect.width, greaterThanOrEqualTo(48));
                expect(slotRect.height, greaterThanOrEqualTo(48));
                expect(
                  rtl
                      ? badgeRect.left - slotRect.left
                      : slotRect.right - badgeRect.right,
                  closeTo(2, 1),
                );
                expect(
                  rtl
                      ? dotRect.left - searchRect.left
                      : searchRect.right - dotRect.right,
                  closeTo(6, 1),
                );
                expect(
                  find.byIcon(Icons.filter_alt).hitTestable(),
                  findsOneWidget,
                );
              }

              for (final collapsed in [false, true]) {
                scroll.jumpTo(collapsed ? 370 : 0);
                await tester.pumpAndSettle();
                for (final count in [1, 44, 444, 1]) {
                  filters.assignAll({
                    for (var i = 0; i < count; i++) 'field $i': i,
                  });
                  await tester.pump();
                  verifyGeometry();
                  await tester.pump(const Duration(milliseconds: 40));
                  verifyGeometry();
                  await tester.pumpAndSettle();
                  final filter = find.byTooltip('Filters, $count active');
                  expect(find.text('$count'), findsOneWidget);
                  final filterData = tester
                      .getSemantics(filter)
                      .getSemanticsData();
                  expect(filterData.flagsCollection.isButton, isTrue);
                  expect(filterData.hasAction(SemanticsAction.tap), isTrue);
                  expect(
                    tester.semantics.simulatedAccessibilityTraversal().where(
                      (node) => node.label == '$count',
                    ),
                    isEmpty,
                  );
                  await tester.tapAt(tester.getCenter(badge));
                  expect(filterTaps, ++expectedFilterTaps);
                }

                final activeRoutes = routes.pushes;
                await tester.tapAt(tester.getCenter(dot));
                await tester.pumpAndSettle();
                expect(routes.pushes, activeRoutes + 1);
                expect(filterTaps, expectedFilterTaps);
                navigator.currentState!.pop();
                await tester.pumpAndSettle();
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
}
