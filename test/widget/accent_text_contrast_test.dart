import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../support/recent_search_test_box.dart';

/// The accent primaries are tuned for white-on-fill. As small text on the
/// tinted search, sheet and dialog surfaces some of them fall below WCAG AA
/// (light Blue 3.86 and light Purple 3.92 on `surfaceContainerHigh`, dark
/// Maroon 4.48). Every accent in both modes must keep the text here at 4.5:1.
void main() {
  const user = 'search@example.com';
  const doctype = 'Sales Order';

  for (final accent in AppAccent.all) {
    for (final brightness in Brightness.values) {
      final tag = '[${brightness.name}, ${accent.name}]';
      ThemeData theme() =>
          buildAppTheme(AppScheme.of(brightness), brightness, accent: accent);

      test('accent text ink clears AA on every text surface $tag', () {
        final t = theme();
        final scheme = AppScheme.of(brightness);
        final ink = accentTextFor(t.colorScheme, scheme);
        for (final surface in [
          scheme.fg,
          scheme.bg,
          scheme.subtle,
          t.colorScheme.surfaceContainerLow,
          t.colorScheme.surfaceContainer,
          t.colorScheme.surfaceContainerHigh,
          // Accent-tinted badges (BalanceChip, info pills) on cards and the
          // scaffold.
          Color.alphaBlend(
            t.colorScheme.primary.withValues(alpha: .15),
            scheme.fg,
          ),
          Color.alphaBlend(
            t.colorScheme.primary.withValues(alpha: .15),
            scheme.bg,
          ),
        ]) {
          expect(contrastRatio(ink, surface), greaterThanOrEqualTo(4.5));
        }
        expect(
          t.textButtonTheme.style?.foregroundColor?.resolve({}),
          ink,
          reason: 'text buttons draw in the accent text ink',
        );
        expect(t.tabBarTheme.labelColor, ink, reason: 'tab labels too');
        expect(
          t.outlinedButtonTheme.style?.foregroundColor?.resolve({}),
          ink,
          reason: 'outlined buttons too',
        );
      });

      testWidgets('section titles, tabs and balance chips $tag', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme(),
            home: DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  bottom: const TabBar(
                    tabs: [
                      Tab(text: 'Open'),
                      Tab(text: 'Closed'),
                    ],
                  ),
                ),
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      const DocSectionCard(title: 'Items', children: []),
                      BalanceChip(
                        isLoading: false,
                        color: context.accentText,
                        textOverride: 'Rack Balance: 12',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        _expectReadable(tester, ['Items', 'Rack Balance: 12']);
        // Tab labels take the theme's accent text ink.
        final tab = find.text('Open');
        final ink = DefaultTextStyle.of(tester.element(tab)).style.color!;
        expect(ink, theme().tabBarTheme.labelColor);
      });

      group('search views $tag', () {
        late StorageService storage;

        setUp(() async {
          storage = StorageService.withStorage(RecentSearchTestBox());
          await storage.addRecentSearch(doctype, user, 'Blue widgets');
          await storage.addRecentSearch('/local-list', user, 'Blue widgets');
          await storage.addRecentSearch('global', user, 'Blue widgets');
        });

        DocTypeSearchDelegate apiDelegate({
          Future<List<GlobalSearchItem>> Function(String, String)? searcher,
        }) => DocTypeSearchDelegate(
          doctype: doctype,
          targetRoute: '/result',
          recentSearchStore: (storage: storage, user: user),
          searcher: searcher ?? (_, __) async => [],
        );

        testWidgets('list search recents and Clear all dialog', (tester) async {
          await _openSearch(tester, apiDelegate(), theme());
          _expectReadable(tester, [
            'Recent searches',
            'Clear all',
            'Blue widgets',
          ]);

          await tester.tap(find.text('Clear all'));
          await tester.pumpAndSettle();
          _expectReadable(tester, [
            'Clear recent searches?',
            'Cancel',
            'Clear',
          ]);
        });

        testWidgets('list search empty results', (tester) async {
          await _openSearch(tester, apiDelegate(), theme(), query: 'Steel');
          _expectReadable(tester, ['No $doctype found matching "Steel"']);
        });

        testWidgets('list search failure message', (tester) async {
          await _openSearch(
            tester,
            apiDelegate(searcher: (_, __) async => throw Exception('down')),
            theme(),
            query: 'Steel',
          );
          _expectReadable(tester, ['Search failed. Please try again.']);
        });

        testWidgets('local list search recents', (tester) async {
          await _openSearch(
            tester,
            DocTypeSearchDelegate(
              recentSearchKey: '/local-list',
              recentSearchStore: (storage: storage, user: user),
              onSearchChanged: (_) {},
            ),
            theme(),
          );
          _expectReadable(tester, ['Recent searches', 'Clear all']);
        });

        testWidgets('global document search recents', (tester) async {
          await _openSearch(
            tester,
            GlobalDocumentSearchDelegate(
              recentSearchStore: (storage: storage, user: user),
            ),
            theme(),
          );
          _expectReadable(tester, ['Recent searches', 'Clear all']);
        });
      });

      testWidgets('status inks on cards and their chip tints $tag', (
        tester,
      ) async {
        late Color warning, success;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme(),
            home: Builder(
              builder: (context) {
                warning = context.warningInk;
                success = context.successInk;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        final fg = AppScheme.of(brightness).fg;
        for (final ink in [warning, success]) {
          expect(contrastRatio(ink, fg), greaterThanOrEqualTo(4.5));
          // BalanceChip fills with its ink at 15%.
          final chip = Color.alphaBlend(ink.withValues(alpha: .15), fg);
          expect(contrastRatio(ink, chip), greaterThanOrEqualTo(4.5));
        }
      });

      testWidgets('outlined button in a dialog $tag', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      actions: [
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Keep editing'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        _expectReadable(tester, ['Keep editing']);
      });

      testWidgets('filter sheet headings and actions $tag', (tester) async {
        await tester.pumpWidget(
          GetMaterialApp(
            theme: theme(),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        );
        Get.bottomSheet(
          GlobalFilterBottomSheet(
            sortOptions: const [SortOption('Name', 'name')],
            currentSortField: 'name',
            currentSortOrder: 'asc',
            onSortChanged: (_, __) {},
            filterWidgets: const [],
            onApply: () {},
            onClear: () {},
          ),
          isScrollControlled: true,
        );
        await tester.pumpAndSettle();
        _expectReadable(tester, [
          'Sort & Filter',
          'Reset',
          'Sort By',
          'Filter Options',
          'Show Results',
        ]);
      });
    }
  }
}

Future<void> _openSearch(
  WidgetTester tester,
  SearchDelegate<void> delegate,
  ThemeData theme, {
  String? query,
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showSearch(context: context, delegate: delegate, query: query),
            child: const Text('Open search'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open search'));
  await tester.pumpAndSettle();
}

/// Each label's ink against the first opaque surface painted behind it.
/// Transparent Materials (text buttons, the search route's own shell) are
/// skipped; they would compare the ink with nothing.
void _expectReadable(WidgetTester tester, List<String> labels) {
  for (final label in labels) {
    final text = find.text(label);
    expect(text, findsOneWidget, reason: label);
    final element = tester.element(text);
    final surface = _surfaceBehind(element);
    final style = DefaultTextStyle.of(
      element,
    ).style.merge(tester.widget<Text>(text).style);
    final ink = Color.alphaBlend(style.color!, surface);
    expect(
      contrastRatio(ink, surface),
      greaterThanOrEqualTo(4.5),
      reason:
          '"$label" ${ink.toARGB32().toRadixString(16)} on '
          '${surface.toARGB32().toRadixString(16)}',
    );
  }
}

Color _surfaceBehind(Element element) {
  Color? found;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Material && (widget.color?.a ?? 0) == 1) {
      found = ElevationOverlay.applySurfaceTint(
        widget.color!,
        widget.surfaceTintColor,
        widget.elevation,
      );
    } else if (widget is ColoredBox && widget.color.a == 1) {
      found = widget.color;
    } else if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      final color = (widget.decoration as BoxDecoration).color;
      if (color != null && color.a == 1) found = color;
    }
    return found == null;
  });
  return found!;
}
