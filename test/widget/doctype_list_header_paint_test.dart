import 'dart:typed_data';
import 'dart:ui' as ui;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show FontLoader, LogicalKeyboardKey, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../unit/theme_contrast_test.dart' show contrast;

class _Pixels {
  const _Pixels(this.bytes, this.width);

  final ByteData bytes;
  final int width;

  int rgba(int x, int y) => bytes.getUint32((y * width + x) * 4);

  Color color(int x, int y) {
    final pixel = rgba(x, y);
    return Color(((pixel & 0xff) << 24) | (pixel >> 8));
  }

  static Future<_Pixels> capture(
    WidgetTester tester,
    GlobalKey key,
    double ratio,
  ) async {
    final result = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: ratio);
      try {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return _Pixels(bytes!, image.width);
      } finally {
        image.dispose();
      }
    });
    return result!;
  }

  void expectInkPreserved(
    _Pixels active,
    Rect bounds,
    Color ink,
    double ratio, {
    Color? inside,
  }) {
    var inkPixels = 0;
    final overwritten = <(int, int, String)>[];
    for (var y = (bounds.top * ratio).ceil(); y < bounds.bottom * ratio; y++) {
      var start = (bounds.left * ratio).ceil();
      var end = (bounds.right * ratio).ceil();
      if (inside != null) {
        // The badge's ring and surrounding surface also use the numeral ink.
        // Inspect only pixels between the colored edges of the badge fill.
        while (start < end && color(start, y) != inside) {
          start++;
        }
        while (end > start && color(end - 1, y) != inside) {
          end--;
        }
      }
      for (var x = start; x < end; x++) {
        if (color(x, y) != ink) continue;
        inkPixels++;
        final activeColor = active.color(x, y);
        if (contrast(activeColor, ink) > 1.05) {
          overwritten.add((x, y, active.rgba(x, y).toRadixString(16)));
        }
      }
    }
    expect(inkPixels, greaterThan(0), reason: 'the fixture renders opaque ink');
    expect(
      overwritten,
      isEmpty,
      reason: 'opaque glyph and indicator pixels survive raster rounding',
    );
  }
}

void _showKeyboardFocus() {
  final manager = FocusManager.instance;
  final previous = manager.highlightStrategy;
  manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => manager.highlightStrategy = previous);
}

void main() {
  const font = 'Header regression Inter';
  const appSurface = Colors.white;
  setUpAll(() async {
    final loader = FontLoader(font);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('lib/assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
  });

  ThemeData theme([AppAccent accent = AppAccent.brand]) {
    final app = buildAppTheme(
      AppScheme.light,
      Brightness.light,
      accent: accent,
    );
    return app.copyWith(
      platform: TargetPlatform.android,
      textTheme: app.textTheme.apply(fontFamily: font),
    );
  }

  testWidgets('focus and held press preserve the applied caption ink', (
    tester,
  ) async {
    _showKeyboardFocus();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 180);
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    final edit = FocusNode();
    addTearDown(edit.dispose);
    final palette = HeaderPalette(theme());
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            backgroundColor: appSurface,
            body: Align(
              alignment: Alignment.topLeft,
              child: FilterChipWidget(
                icon: Icons.label,
                label: 'Status: Draft',
                onDeleted: () {},
                onTap: () {},
                editFocusNode: edit,
              ),
            ),
          ),
        ),
      ),
    );
    final label = find.text('Status: Draft');
    const ratio = 3.0;
    final rest = await _Pixels.capture(tester, boundary, ratio);
    edit.requestFocus();
    await tester.pump();
    expect(edit.hasPrimaryFocus, isTrue);
    rest.expectInkPreserved(
      await _Pixels.capture(tester, boundary, ratio),
      tester.getRect(label),
      palette.appliedInk,
      ratio,
    );
    final pressed = await tester.startGesture(tester.getCenter(label));
    await tester.pump(const Duration(milliseconds: 150));
    rest.expectInkPreserved(
      await _Pixels.capture(tester, boundary, ratio),
      tester.getRect(label),
      palette.appliedInk,
      ratio,
    );
    await pressed.cancel();
  });

  testWidgets('focus and held press preserve the wide badge and search dot', (
    tester,
  ) async {
    _showKeyboardFocus();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 500);
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    final blue = theme(AppAccent.blue);
    final palette = HeaderPalette(blue);
    final filters = <String, int>{
      for (var i = 0; i < 444; i++) 'field $i': i,
    }.obs;
    final query = 'bolts'.obs;
    await tester.pumpWidget(
      MaterialApp(
        theme: blue,
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: CustomScrollView(
                  slivers: [
                    DocTypeListHeader(
                      title: 'Item',
                      activeFilters: filters,
                      onFilterTap: () {},
                      searchQuery: query,
                      onSearchChanged: (_) {},
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 700)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    const ratio = 3.0;
    final rest = await _Pixels.capture(tester, boundary, ratio);
    final funnel = find.byKey(const ValueKey('list-header-filter-slot'));
    tester.widget<HeaderIconAction>(funnel).focusNode!.requestFocus();
    await tester.pump();
    expect(tester.widget<HeaderIconAction>(funnel).focusNode!.hasFocus, isTrue);
    final badge = tester.getRect(find.byType(CountBadge));
    rest.expectInkPreserved(
      await _Pixels.capture(tester, boundary, ratio),
      badge,
      palette.toolbarBadgeInk,
      ratio,
      inside: palette.toolbarBadgeFill,
    );
    final funnelPress = await tester.startGesture(tester.getCenter(funnel));
    await tester.pump(const Duration(milliseconds: 150));
    rest.expectInkPreserved(
      await _Pixels.capture(tester, boundary, ratio),
      badge,
      palette.toolbarBadgeInk,
      ratio,
      inside: palette.toolbarBadgeFill,
    );
    await funnelPress.cancel();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final search = find.byTooltip('Search, current query: bolts');
    expect(
      tester.getSemantics(search).getSemanticsData().flagsCollection.isFocused,
      ui.Tristate.isTrue,
    );
    final dot = tester.getRect(
      find.byKey(const ValueKey('list-header-search-dot')),
    );
    rest.expectInkPreserved(
      await _Pixels.capture(tester, boundary, ratio),
      dot,
      blue.colorScheme.error,
      ratio,
    );
    final searchPress = await tester.startGesture(tester.getCenter(search));
    await tester.pump(const Duration(milliseconds: 150));
    rest.expectInkPreserved(
      await _Pixels.capture(tester, boundary, ratio),
      dot,
      blue.colorScheme.error,
      ratio,
    );
    await searchPress.cancel();
  });

  for (final ratio in [2.0, 3.0]) {
    testWidgets('solid and dashed pills paint 1 dp edges at ${ratio}x DPR', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = const Size(280, 200) * ratio;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme(),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              backgroundColor: appSurface,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AddFilterChip(onTap: () {}),
                  FilterChipWidget(
                    icon: Icons.label,
                    label: 'Status: Draft',
                    onDeleted: () {},
                  ),
                  FilterChipWidget(
                    enabled: false,
                    icon: Icons.label,
                    label: 'Status: Queued',
                    onDeleted: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final rendered = await _Pixels.capture(tester, boundary, ratio);
      final pills = find.byType(HeaderPill);
      expect(pills, findsNWidgets(3));
      for (var index = 0; index < 3; index++) {
        final bounds = tester.getRect(pills.at(index));
        final x = (bounds.center.dx * ratio).round();
        final top = (bounds.top * ratio).round();
        final end = top + ratio.toInt();
        for (var y = top; y < end; y++) {
          final edgeContrast = [
            for (var dx = -8; dx <= 8; dx++)
              contrast(rendered.color(x + dx, y), appSurface),
          ];
          expect(
            edgeContrast.any((value) => value >= 3),
            isTrue,
            reason: 'pill $index, physical row ${y - top}: $edgeContrast',
          );
        }
      }
    });
  }

  for (final selected in [false, true]) {
    testWidgets('held quick chip keeps its layout with selected=$selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme(),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                DocTypeListHeader(
                  title: 'Stock Ageing',
                  quickChips: [
                    ChoiceChip(
                      label: const Text('By Age'),
                      selected: selected,
                      onSelected: (_) {},
                      visualDensity: VisualDensity.compact,
                    ),
                    ChoiceChip(
                      label: const Text('By Quantity'),
                      selected: !selected,
                      onSelected: (_) {},
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 800)),
              ],
            ),
          ),
        ),
      );
      final chip = find.widgetWithText(ChoiceChip, 'By Age');
      final next = find.widgetWithText(ChoiceChip, 'By Quantity');
      final chipBounds = tester.getRect(chip);
      final nextBounds = tester.getRect(next);
      final gesture = await tester.startGesture(chipBounds.center);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getRect(chip), chipBounds);
      expect(tester.getRect(next), nextBounds);
      await gesture.cancel();
    });
  }

  testWidgets(
    'header search and quick-chip popups keep normal interaction colors',
    (tester) async {
      const focus = Color(0xff406db4);
      const hover = Color(0xff935c2e);
      final original = theme().copyWith(focusColor: focus, hoverColor: hover);
      await tester.pumpWidget(
        MaterialApp(
          theme: original,
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                DocTypeListHeader(
                  title: 'Item',
                  extraActions: [
                    SearchAnchor(
                      builder: (context, controller) => IconButton(
                        tooltip: 'Open command search',
                        onPressed: controller.openView,
                        icon: const Icon(Icons.search),
                      ),
                      suggestionsBuilder: (context, controller) => [
                        ListTile(title: const Text('Suggestion'), onTap: () {}),
                      ],
                    ),
                  ],
                  quickChips: [
                    Builder(
                      builder: (context) => ActionChip(
                        label: const Text('View'),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          builder: (_) => ListTile(
                            title: const Text('Expand all'),
                            onTap: () {},
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 800)),
              ],
            ),
          ),
        ),
      );

      for (final (launcher, row) in [
        (find.byTooltip('Open command search'), 'Suggestion'),
        (find.text('View'), 'Expand all'),
      ]) {
        expect(
          Theme.of(tester.element(launcher)).focusColor,
          Colors.transparent,
        );
        await tester.tap(launcher);
        await tester.pumpAndSettle();
        final tile = tester.element(find.widgetWithText(ListTile, row));
        expect(Theme.of(tile).focusColor, focus, reason: row);
        expect(Theme.of(tile).hoverColor, hover, reason: row);
        Navigator.of(tile).pop();
        await tester.pumpAndSettle();
      }
    },
  );
}
