import 'dart:math' as math;
import 'dart:ui' show SemanticsAction, Tristate;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/main.dart' show buildAppTheme;

const _body = ValueKey<String>('list-body');
const _bottom = ValueKey<String>('bottom-content');
const _font = 'HeaderTestInter';
const _longTitle = 'BOM Stock with Customer Code';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize > 24 ? 1.45 : 2);

  @override
  double get textScaleFactor => 2;
}

ThemeData _theme(Brightness brightness) {
  final theme = buildAppTheme(AppScheme.of(brightness), brightness);
  return theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: _font));
}

RenderSliverPersistentHeader _sliver(WidgetTester tester) =>
    tester.renderObject<RenderSliverPersistentHeader>(
      find.byType(SliverPersistentHeader),
    );

Widget _host(
  ScrollController scroll, {
  required TextScaler scaler,
  required DocTypeListHeader header,
  TextDirection direction = TextDirection.ltr,
  double safe = 0,
  bool drawer = false,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: _theme(brightness),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: scaler,
        padding: EdgeInsets.only(top: safe),
      ),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          drawer: drawer ? const Drawer() : null,
          body: CustomScrollView(
            controller: scroll,
            slivers: [
              header,
              const SliverToBoxAdapter(
                child: SizedBox(key: _body, height: 1700),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void _fullTitle(WidgetTester tester, String title, TextScaler scaler) {
  final finder = find.text(title);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final css = paragraph.text.style!;
  expect(
    paragraph.textScaler.scale(css.fontSize!),
    closeTo(scaler.scale(css.fontSize!), .01),
  );
  expect(css.fontSize, anyOf(22, 28));
  expect(paragraph.overflow, TextOverflow.visible);
  for (var index = 0; index < title.length; index++) {
    final glyph = title[index];
    if (glyph.trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    );
    final reason = '“$glyph” at $index in “$title” (${paragraph.size})';
    expect(boxes, isNotEmpty, reason: reason);
    for (final rect in boxes) {
      expect(rect.left, greaterThanOrEqualTo(-1), reason: reason);
      expect(
        rect.right,
        lessThanOrEqualTo(paragraph.size.width + 1),
        reason: reason,
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(paragraph.size.height + 1),
        reason: reason,
      );
    }
  }
}

double _measure(RenderParagraph paragraph, TextStyle style, double maxWidth) {
  final painter = TextPainter(
    text: TextSpan(text: paragraph.text.toPlainText(), style: style),
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(maxWidth: maxWidth);
  final result = painter.height.ceilToDouble();
  painter.dispose();
  return result;
}

void main() {
  setUpAll(() async {
    final loader = FontLoader(_font)
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
    await loader.load();
  });

  testWidgets('sliver extents equal measured children throughout collapse', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final scalers = [
      TextScaler.noScaling,
      const TextScaler.linear(1.3),
      const TextScaler.linear(2),
      const _NonlinearScaler(),
    ];
    final active = <String, dynamic>{'state': 'Draft', 'area': 'North'}.obs;

    for (final width in [320.0, 360.0, 411.0]) {
      tester.view.physicalSize = Size(width, 850);
      for (var index = 0; index < scalers.length; index++) {
        final scale = scalers[index];
        final safe = index.isEven ? 0.0 : 23.0;
        final bottom = [0.0, 48.0, 52.0, 48.0][index];
        final title = [
          'Attendance',
          'Item',
          _longTitle,
          'Monthly Attendance Sheet',
        ][index];
        final pinned = index.isEven;
        final floating = index >= 2;
        await tester.pumpWidget(
          _host(
            scroll,
            scaler: scale,
            safe: safe,
            header: DocTypeListHeader(
              title: title,
              pinnedAppBar: pinned,
              floatingAppBar: floating,
              onFilterTap: index == 0 ? null : () {},
              activeFilters: index >= 2 ? active : null,
              filterChipsBuilder: (_) => [
                FilterChipWidget(
                  icon: Icons.info_outline,
                  label: 'Status: Draft',
                  onTap: () {},
                  onDeleted: () {},
                ),
                FilterChipWidget(
                  icon: Icons.pin_drop,
                  label: 'Area: North',
                  onDeleted: () {},
                ),
              ],
              quickChips: index >= 2
                  ? [ActionChip(label: const Text('View'), onPressed: () {})]
                  : null,
              bottom: bottom == 0
                  ? null
                  : PreferredSize(
                      preferredSize: Size.fromHeight(bottom),
                      child: const ColoredBox(
                        key: _bottom,
                        color: Colors.transparent,
                      ),
                    ),
            ),
          ),
        );
        scroll.jumpTo(0);
        await tester.pumpAndSettle();

        final sliver = _sliver(tester);
        expect(sliver.child, isNotNull);
        final config = tester.widget<SliverPersistentHeader>(
          find.byType(SliverPersistentHeader),
        );
        expect(config.pinned, pinned);
        expect(config.floating, floating);

        final toolbar = tester.getRect(find.byType(NavigationToolbar));
        final row = find.byType(SingleChildScrollView);
        final rowHeight = index == 0 ? 0.0 : tester.getSize(row).height;
        expect(row, index == 0 ? findsNothing : findsOneWidget);
        expect(rowHeight >= 48, index != 0);
        final bottomHeight = bottom == 0
            ? 0.0
            : tester.getSize(find.byKey(_bottom)).height;
        expect(bottomHeight, greaterThanOrEqualTo(bottom));
        final fixed = safe + toolbar.height + bottomHeight + rowHeight;
        final expanded = config.delegate.maxExtent - fixed;
        final compact = config.delegate.minExtent - fixed;
        final travel = expanded - compact;
        final expandedParagraph = tester.renderObject<RenderParagraph>(
          find.text(title),
        );
        final context = tester.element(find.byType(DocTypeListHeader));
        final headingStyle = Theme.of(
          context,
        ).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w600);
        final largeHeight =
            _measure(expandedParagraph, headingStyle, width - 32) + 8;
        expect(
          expanded,
          closeTo(math.max(96, math.max(largeHeight, compact)), 1),
        );
        expect(compact, greaterThanOrEqualTo(0));

        final offsets = {
          0.0,
          math.max(0.0, math.min(travel, expanded - largeHeight - 1)),
          math.max(0.0, math.min(travel, expanded - largeHeight + 1)),
          math.max(0.0, travel / 2 - 1),
          math.min(travel, travel / 2 + 1),
          travel,
        }.toList()..sort();
        for (final offset in offsets) {
          scroll.jumpTo(offset);
          await tester.pumpAndSettle();
          final child = _sliver(tester).child!;
          expect(
            child.size.height,
            closeTo(fixed + expanded - offset, 1),
            reason: '$width / $scale / $title at $offset',
          );
          final bottomBox = index != 0
              ? tester.getRect(row)
              : tester.getRect(find.byType(NavigationToolbar));
          final bottomOfHeader = child
              .localToGlobal(Offset(0, child.size.height))
              .dy;
          expect(bottomBox.bottom, closeTo(bottomOfHeader, 1));
          _fullTitle(tester, title, scale);
          expect(tester.takeException(), isNull);
        }
        if (compact > 0) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(title),
          );
          expect(
            compact,
            closeTo(_measure(paragraph, paragraph.text.style!, width - 32), 1),
          );
        }
      }
    }
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'large Item actions remain reachable at 320 and 411 dp in ${direction.name}',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final showPhotos = true.obs;
        final query = 'bolts'.obs;
        final filters = <String, dynamic>{'status': 'Draft'}.obs;
        final selected = false.obs;
        var toggles = 0;
        final header = DocTypeListHeader(
          title: 'Item',
          automaticallyImplyLeading: false,
          activeFilters: filters,
          onFilterTap: () {},
          searchQuery: query,
          onSearchChanged: (_) {},
          extraActions: [
            IconButton(
              onPressed: () {},
              tooltip: 'Add item',
              icon: const Icon(Icons.add),
            ),
            Obx(
              () => showPhotos.value
                  ? IconButton(
                      onPressed: () {},
                      tooltip: 'Items from Photos',
                      icon: const Icon(Icons.add_a_photo),
                    )
                  : const SizedBox.shrink(),
            ),
            Obx(
              () => IconButton(
                isSelected: selected.value,
                onPressed: () {
                  toggles++;
                  selected.toggle();
                },
                tooltip: 'Contains serial numbers',
                icon: const Icon(Icons.tag),
              ),
            ),
          ],
        );
        const scale = TextScaler.linear(2);
        final more = find.byTooltip('More actions');
        for (final width in [320.0, 411.0]) {
          tester.view.physicalSize = Size(width, 850);
          await tester.pumpWidget(
            _host(
              scroll,
              scaler: scale,
              direction: direction,
              drawer: true,
              header: header,
            ),
          );
          final delegate = tester
              .widget<SliverPersistentHeader>(
                find.byType(SliverPersistentHeader),
              )
              .delegate;
          scroll.jumpTo(delegate.maxExtent - delegate.minExtent);
          await tester.pumpAndSettle();
          _fullTitle(tester, 'Item', scale);
          expect(more, width == 320 ? findsOneWidget : findsNothing);
          if (width == 320) {
            final photos = find.byTooltip('Items from Photos');
            final toggle = find.byTooltip('Contains serial numbers');
            expect(photos, findsNothing);
            await tester.tap(more);
            await tester.pumpAndSettle();
            expect(photos, findsOneWidget);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(toggles, 1);
            expect(
              tester
                  .widget<IconButton>(
                    find.ancestor(
                      of: toggle,
                      matching: find.byType(IconButton),
                    ),
                  )
                  .isSelected,
              isTrue,
            );
            showPhotos.value = false;
            await tester.pumpAndSettle();
            expect(photos, findsNothing);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(toggle, findsNothing);
            expect(
              tester
                  .getSemantics(more)
                  .getSemanticsData()
                  .flagsCollection
                  .isFocused,
              Tristate.isTrue,
            );
            showPhotos.value = true;
          }

          if (width == 411) {
            final photos = find.byTooltip('Items from Photos');
            expect(photos, findsOneWidget);
            showPhotos.value = false;
            await tester.pumpAndSettle();
            expect(photos, findsNothing);
            expect(more, findsNothing);
            _fullTitle(tester, 'Item', scale);
          }

          final filter = find.byTooltip('Filters, 1 active');
          final search = find.byTooltip('Search, current query: bolts');
          final filterRect = tester.getRect(filter);
          final searchRect = tester.getRect(search);
          for (final rect in [
            filterRect,
            searchRect,
            tester.getRect(find.byType(AddFilterChip)),
          ]) {
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          expect(filterRect.overlaps(searchRect), isFalse);
          expect(
            searchRect.center.dx.compareTo(filterRect.center.dx),
            direction == TextDirection.ltr ? 1 : -1,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('short viewport keeps body reachable and discloses full title', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 180);
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const scaler = TextScaler.linear(2);
    final filter = <String, dynamic>{'status': 'Draft'}.obs;
    final query = 'bolts'.obs;
    await tester.pumpWidget(
      _host(
        scroll,
        scaler: scaler,
        drawer: true,
        header: DocTypeListHeader(
          title: _longTitle,
          activeFilters: filter,
          onFilterTap: () {},
          searchQuery: query,
          onSearchChanged: (_) {},
        ),
      ),
    );

    scroll.jumpTo(700);
    await tester.pumpAndSettle();
    final toolbar = find.byType(NavigationToolbar);
    final disclosure = find.byTooltip('Show full title');
    final delegate = tester
        .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
        .delegate;
    final row = find.byType(SingleChildScrollView);
    expect(
      delegate.minExtent,
      tester.getSize(toolbar).height + tester.getSize(row).height,
    );
    expect(scroll.offset, 700);
    expect(tester.getRect(find.byKey(_body)).bottom, greaterThan(180));
    expect(_sliver(tester).geometry!.paintExtent, lessThanOrEqualTo(180 - 48));
    expect(disclosure, findsOneWidget);
    expect(tester.getSize(disclosure), const Size(48, 48));
    final disclosureButton = find.descendant(
      of: disclosure,
      matching: find.byType(TextButton),
    );
    final disclosureData = tester
        .getSemantics(disclosureButton)
        .getSemanticsData();
    expect(disclosureData.flagsCollection.isHeader, isTrue);
    expect(disclosureData.flagsCollection.isButton, isTrue);
    expect(disclosureData.label, _longTitle);
    expect(disclosureData.hint, 'Show full title');
    expect(disclosureData.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(disclosure);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    _fullTitle(tester, _longTitle, scaler);
    final sheetContext = tester.element(find.byType(BottomSheet));
    Navigator.of(sheetContext).pop();
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus,
      same(tester.widget<TextButton>(disclosureButton).focusNode),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned minimum leaves results room even with fixed controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 120);
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        scroll,
        scaler: TextScaler.noScaling,
        header: DocTypeListHeader(
          title: 'Sales Order',
          onFilterTap: () {},
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(52),
            child: SizedBox(),
          ),
        ),
      ),
    );
    final header = tester.widget<SliverPersistentHeader>(
      find.byType(SliverPersistentHeader),
    );
    final render = _sliver(tester);
    expect(header.delegate.minExtent, lessThanOrEqualTo(72));
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    expect(render.geometry!.paintExtent, lessThanOrEqualTo(72));
    expect(
      tester.getRect(find.byKey(_body)).contains(const Offset(160, 72)),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow title disclosure reserves a full target beside More', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 180);
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var addItem = 0;
    await tester.pumpWidget(
      _host(
        scroll,
        scaler: const TextScaler.linear(2),
        drawer: true,
        header: DocTypeListHeader(
          title: 'Item',
          searchQuery: 'bolts'.obs,
          onFilterTap: () {},
          extraActions: [
            IconButton(
              onPressed: () => addItem++,
              tooltip: 'Add item',
              icon: const Icon(Icons.add),
            ),
            for (final icon in [Icons.camera, Icons.tag])
              IconButton(onPressed: () {}, icon: Icon(icon)),
          ],
        ),
      ),
    );
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    final disclosure = find.byTooltip('Show full title');
    expect(tester.getSize(disclosure), const Size(48, 48));
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Search, current query: bolts'), findsOneWidget);
    await tester.tap(find.byTooltip('Add item'));
    expect(addItem, 1);
  });

  testWidgets('dismissed title disclosure stays unfocused after reattachment', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 180);
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    final otherFocus = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(otherFocus.dispose);
    await tester.pumpWidget(
      _host(
        scroll,
        scaler: const TextScaler.linear(2),
        drawer: true,
        header: DocTypeListHeader(
          title: _longTitle,
          onFilterTap: () {},
          extraActions: [
            IconButton(
              focusNode: otherFocus,
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    final disclosure = find.byTooltip('Show full title');
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(700, 550);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expect(disclosure, findsNothing);
    otherFocus.requestFocus();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 180);
    await tester.pumpAndSettle();
    expect(disclosure, findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(otherFocus));
  });

  testWidgets('open title sheet gets its ink from the live theme', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 180);
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(scroll.dispose);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: mode,
        builder: (context, themeMode, child) => MaterialApp(
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: child,
        ),
        child: Scaffold(
          drawer: const Drawer(),
          body: CustomScrollView(
            controller: scroll,
            slivers: [
              DocTypeListHeader(title: _longTitle, onFilterTap: () {}),
              const SliverToBoxAdapter(child: SizedBox(height: 1600)),
            ],
          ),
        ),
      ),
    );
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show full title'));
    await tester.pumpAndSettle();
    final heading = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(_longTitle),
    );
    expect(tester.widget<Text>(heading).style!.color, AppScheme.light.text);
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(heading).style!.color, AppScheme.dark.text);
  });
}
