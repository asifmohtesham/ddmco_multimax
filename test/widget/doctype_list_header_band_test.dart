import 'dart:ui' show ImageByteFormat, SemanticsAction, Tristate;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/header_chip_band.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../unit/theme_contrast_test.dart' show contrast;

const _bandKey = ValueKey('list-header-chip-band');
const _surfaceKey = ValueKey('header-surface');
const _resultKey = ValueKey('result');
final _band = find.byKey(_bandKey);

Widget _host({
  required DocTypeListHeader header,
  required ScrollController scroll,
  double? paneWidth,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? buildAppTheme(AppScheme.light, Brightness.light),
  home: Scaffold(
    body: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: Directionality(
          textDirection: direction,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: paneWidth,
              child: RepaintBoundary(
                key: _surfaceKey,
                child: CustomScrollView(
                  controller: scroll,
                  slivers: [
                    header,
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 1200, key: _resultKey),
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

MeasuredHeaderChip _fixedChip(
  int id,
  double width, {
  FocusNode? focus,
  String? caption,
  VoidCallback? action,
}) => MeasuredHeaderChip(
  key: ValueKey(id),
  measure: (context, maxWidth) => (
    width: width.clamp(0, maxWidth),
    height: 48,
    paintHeight: 34,
    stackedReset: false,
    stackedChoice: false,
    maxLines: 1,
    ellipsized: caption != null,
  ),
  builder: (_, _) => HeaderQuickChip(
    caption: caption ?? 'Q$id',
    label: caption ?? 'Quick $id',
    role: HeaderQuickRole.command,
    focusNode: focus,
    onPressed: action ?? () {},
  ),
);

Finder _control(int id) => find.descendant(
  of: find.byKey(ValueKey(id)),
  matching: find.byType(TextButton),
);

void main() {
  testWidgets('shared quick choice captions stay centred on selection', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const label = 'Quantity';
    const key = ValueKey(label);
    final button = find.descendant(
      of: find.byKey(key),
      matching: find.byType(TextButton),
    );
    for (final direction in TextDirection.values) {
      for (final scale in [1.0, 2.0]) {
        Rect? restingTarget;
        for (final selected in [false, true]) {
          await tester.pumpWidget(
            _host(
              scroll: scroll,
              paneWidth: 411,
              scaler: TextScaler.linear(scale),
              direction: direction,
              header: DocTypeListHeader(
                title: 'Stock Ageing',
                quickChips: [
                  HeaderQuickChip(
                    key: key,
                    caption: label,
                    label: label,
                    role: HeaderQuickRole.choice,
                    active: selected,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          );
          final target = tester.getRect(button);
          restingTarget ??= target;
          expect(target, restingTarget);
          final caption = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          final textBounds = caption
              .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length),
              )
              .single
              .toRect()
              .shift(caption.localToGlobal(Offset.zero));
          expect(textBounds.center.dx, closeTo(target.center.dx, .5));
          final check = find.descendant(
            of: button,
            matching: find.byIcon(Icons.check),
          );
          expect(check, selected ? findsOneWidget : findsNothing);
          if (selected) {
            expect(tester.getRect(check).overlaps(textBounds), isFalse);
          }
        }
      }
    }
  });

  testWidgets(
    'packing uses local width, exact fit, custom caps and zero through five runs',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final key = GlobalKey();

      Future<void> pump(
        double width,
        int count, {
        TextDirection direction = TextDirection.ltr,
      }) => tester.pumpWidget(
        _host(
          scroll: scroll,
          paneWidth: width,
          direction: direction,
          header: DocTypeListHeader(
            title: 'List',
            sliverKey: key,
            quickChips: [for (var i = 0; i < count; i++) _fixedChip(i, 125)],
          ),
        ),
      );

      await pump(411, 0);
      expect(_band, findsNothing);
      for (final (width, count, runs) in [
        (411.0, 3, 1),
        (410.0, 3, 2),
        (411.0, 7, 3),
        (411.0, 10, 4),
        (410.0, 10, 5),
      ]) {
        await pump(width, count);
        final band = tester.getRect(_band);
        final delegate = tester
            .widget<SliverPersistentHeader>(find.byKey(key))
            .delegate;
        expect(band.width, width);
        expect(band.height, 48 * runs + 4 * (runs - 1));
        expect(delegate.minExtent, band.height + 56);
        expect(delegate.maxExtent, band.height + 56 + 96);
        expect(tester.getRect(_control(0)).left, band.left + 12);
        final first = tester.getRect(_control(0));
        final second = tester.getRect(_control(1));
        expect(second.left - first.right, 6);
        expect(second.top, first.top);
        expect(
          find.descendant(of: _band, matching: find.byType(Scrollable)),
          findsNothing,
        );
        for (var i = 0; i < count; i++) {
          expect(_control(i).hitTestable(), findsOneWidget);
          expect(
            band.inflate(.01).contains(tester.getRect(_control(i)).bottomRight),
            isTrue,
          );
        }
      }

      await pump(411, 3, direction: TextDirection.rtl);
      final rtl = tester.getRect(_band);
      expect(rtl.right - tester.getRect(_control(0)).right, 12);
      expect(
        tester.getRect(_control(0)).left - tester.getRect(_control(1)).right,
        6,
      );
      expect(tester.getRect(_control(2)).left - rtl.left, 12);

      const caption =
          'A localized quick action whose extended caption exceeds a line';
      await tester.pumpWidget(
        _host(
          scroll: scroll,
          paneWidth: 320,
          scaler: const TextScaler.linear(2),
          header: DocTypeListHeader(
            title: 'List',
            quickChips: [_fixedChip(4, 270, caption: caption)],
          ),
        ),
      );
      final text = tester.renderObject<RenderParagraph>(find.text(caption));
      expect(text.didExceedMaxLines, isTrue);
      expect(
        tester.getSemantics(_control(4)).getSemanticsData().label,
        caption,
      );
      expect(find.byTooltip(caption), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'D-pad follows painted neighbours through reflow in ${direction.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(411, 850);
        addTearDown(tester.view.reset);
        final nodes = [for (var i = 0; i < 4; i++) FocusNode()];
        addTearDown(() {
          for (final node in nodes) {
            node.dispose();
          }
        });
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final key = GlobalKey();
        final calls = <int>[];

        Widget host(double width) => _host(
          scroll: scroll,
          direction: direction,
          paneWidth: width,
          header: DocTypeListHeader(
            title: 'List',
            sliverKey: key,
            quickChips: [
              for (final (i, node) in nodes.indexed)
                _fixedChip(i, 140, focus: node, action: () => calls.add(i)),
            ],
          ),
        );

        await tester.pumpWidget(host(320));
        nodes[0].requestFocus();
        await tester.pump();
        final logicalNext = direction == TextDirection.ltr
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft;
        final logicalBack = direction == TextDirection.ltr
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowRight;
        for (final (key, expected) in [
          (logicalNext, 1),
          (LogicalKeyboardKey.arrowDown, 3),
          (logicalBack, 2),
          (LogicalKeyboardKey.arrowUp, 0),
          (LogicalKeyboardKey.arrowDown, 2),
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus, same(nodes[expected]));
        }
        final lower = tester.element(_control(2));
        await tester.pumpWidget(host(290));
        expect(tester.element(_control(2)), same(lower));
        expect(FocusManager.instance.primaryFocus, same(nodes[2]));
        bool pinned() =>
            tester.widget<SliverPersistentHeader>(find.byKey(key)).pinned;
        expect(pinned(), isTrue);
        tester.view.physicalSize = const Size(411, 260);
        await tester.pump();
        expect(pinned(), isFalse);
        expect(FocusManager.instance.primaryFocus, same(nodes[2]));
        tester.view.physicalSize = const Size(411, 850);
        await tester.pump();
        expect(pinned(), isTrue);
        expect(FocusManager.instance.primaryFocus, same(nodes[2]));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        expect(calls, [2, 2]);
      },
    );
  }

  testWidgets(
    'twelve full captions scroll vertically above results in a short viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 230);
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final labels = [
        for (var i = 0; i < 12; i++)
          'Translated field name $i: a very long full value ABC‑1234567890\nSecond line',
      ];
      final filters = {for (final (i, label) in labels.indexed) i: label}.obs;
      await tester.pumpWidget(
        _host(
          scroll: scroll,
          scaler: const TextScaler.linear(2),
          header: DocTypeListHeader(
            title: 'Long report title',
            floatingAppBar: true,
            activeFilters: filters,
            onFilterTap: () {},
            filterChipsBuilder: (_) => [
              for (final (i, label) in labels.indexed)
                FilterChipWidget(
                  key: ValueKey(i),
                  icon: Icons.filter_alt_outlined,
                  label: label,
                  onTap: () {},
                  onDeleted: () {},
                ),
            ],
          ),
        ),
      );
      final config = tester.widget<SliverPersistentHeader>(
        find.byType(SliverPersistentHeader),
      );
      expect(config.pinned, isFalse);
      expect(config.floating, isTrue);
      expect(config.delegate.minExtent, lessThanOrEqualTo(230 - 48));
      expect(tester.getSize(_band).height, greaterThan(230));
      final reached = <String>{};
      for (
        var offset = 0.0;
        offset < config.delegate.maxExtent + 230;
        offset += 24
      ) {
        scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
        await tester.pump();
        for (final label in labels) {
          if (find.text(label).hitTestable().evaluate().isNotEmpty) {
            reached.add(label);
          }
        }
      }
      expect(reached, unorderedEquals(labels));
      expect(
        tester
            .getRect(find.byKey(_resultKey))
            .overlaps(const Rect.fromLTWH(0, 0, 320, 230)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an extra-narrow pane stacks the complete Edit and Reset targets',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final calls = <String>[];
      final filters = {'a': 'Exact field: Off'}.obs;
      await tester.pumpWidget(
        _host(
          scroll: scroll,
          paneWidth: 80,
          header: DocTypeListHeader(
            title: 'A',
            activeFilters: filters,
            filterChipsBuilder: (_) => [
              FilterChipWidget(
                label: 'Exact field: Off',
                icon: Icons.filter_alt_outlined,
                onDeleted: () => calls.add('reset'),
                onTap: () => calls.add('edit'),
              ),
            ],
          ),
        ),
      );
      final body = find.widgetWithText(TextButton, 'Exact field: Off');
      final reset = find.widgetWithIcon(TextButton, Icons.close);
      final editRect = tester.getRect(body);
      final resetRect = tester.getRect(reset);
      expect(editRect.size, resetRect.size);
      expect(editRect.width, 80);
      expect(editRect.height, greaterThanOrEqualTo(48));
      expect(editRect.bottom, resetRect.top);
      expect(
        tester.getSemantics(body).getSemanticsData().value,
        'Applied filter',
      );
      await tester.tapAt(Offset(editRect.left + 1, editRect.top + 1));
      await tester.tapAt(Offset(resetRect.right - 1, resetRect.bottom - 1));
      expect(calls, ['edit', 'reset']);
    },
  );

  testWidgets('late font loading remeasures the band and sliver together', (
    tester,
  ) async {
    const family = 'LateHeaderInter';
    const caption = 'iiiiiiiiiiii';
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    final chip = HeaderQuickChip(
      caption: caption,
      label: caption,
      role: HeaderQuickRole.command,
      onPressed: () {},
    );
    await tester.pumpWidget(
      _host(
        scroll: scroll,
        paneWidth: 320,
        scaler: const TextScaler.linear(2),
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: family),
        ),
        header: DocTypeListHeader(title: 'List', quickChips: [chip]),
      ),
    );
    final target = find.widgetWithText(TextButton, caption);
    final before = tester.getSize(target);
    final font = FontLoader(family)
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Medium.ttf'));
    await tester.runAsync(font.load);
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    await tester.pumpAndSettle();

    final measured = chip.measure(tester.element(target), 296);
    expect(Size(measured.width, measured.height), isNot(before));
    expect(tester.getSize(target), Size(measured.width, measured.height));
    expect(tester.getSize(_band).height, measured.height);
    expect(
      tester
          .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
          .delegate
          .minExtent,
      measured.height + 56,
    );
  });

  testWidgets('bulk Reset paints matching caption and icon ink', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    final palette = HeaderPalette(theme);
    final filters = {
      'item': 'Item: 1002890',
      'warehouse': 'Warehouse-wise: off',
    }.obs;
    final caption = find.text('Reset filters');
    final icon = find.byIcon(Icons.clear_all);
    final button = find.widgetWithText(TextButton, 'Reset filters');

    for (final enabled in [true, false]) {
      await tester.pumpWidget(
        _host(
          scroll: scroll,
          paneWidth: 411,
          theme: theme,
          header: DocTypeListHeader(
            title: 'Stock Ageing',
            filtersEnabled: enabled,
            activeFilters: filters,
            onClearAllFilters: () {},
            filterChipsBuilder: (_) => [
              for (final label in filters.values)
                FilterChipWidget(
                  label: label,
                  icon: Icons.filter_alt,
                  onDeleted: () {},
                  onTap: () {},
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final expectedInk = enabled ? palette.error : palette.muted;
      final expectedFill = palette.bulkFill({
        if (!enabled) WidgetState.disabled,
      });
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_surfaceKey),
      );
      final (rgba, width) = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          return ((await image.toByteData())!, image.width);
        } finally {
          image.dispose();
        }
      }))!;
      int pixel(int x, int y) {
        final offset = 4 * (y * width + x);
        return Color.fromARGB(
          rgba.getUint8(offset + 3),
          rgba.getUint8(offset),
          rgba.getUint8(offset + 1),
          rgba.getUint8(offset + 2),
        ).toARGB32();
      }

      final fillPoint = tester.getRect(button).centerRight - const Offset(8, 0);
      expect(
        pixel((fillPoint.dx * 2).round(), (fillPoint.dy * 2).round()),
        expectedFill.toARGB32(),
      );
      for (final target in [caption, icon]) {
        final bounds = tester.getRect(target);
        final count = [
          for (var y = (bounds.top * 2).ceil(); y < bounds.bottom * 2; y++)
            for (var x = (bounds.left * 2).ceil(); x < bounds.right * 2; x++)
              if (pixel(x, y) == expectedInk.toARGB32()) 1,
        ].length;
        expect(count, greaterThan(0), reason: '$target, enabled=$enabled');
      }
    }
  });

  for (final accent in AppAccent.all) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'measured quick paint and disabled state [${brightness.name}, ${accent.name}]',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final theme = buildAppTheme(
            AppScheme.of(brightness),
            brightness,
            accent: accent,
          );
          final palette = HeaderPalette(theme);
          final states = [false, true, false, true];
          await tester.pumpWidget(
            _host(
              scroll: scroll,
              theme: theme,
              header: DocTypeListHeader(
                title: 'Report',
                quickChips: [
                  for (final (i, active) in states.indexed)
                    HeaderQuickChip(
                      key: ValueKey(i),
                      caption: 'Quick $i',
                      label: 'Quick $i',
                      role: HeaderQuickRole.choice,
                      active: active,
                      onPressed: i < 2 ? () {} : null,
                    ),
                ],
              ),
            ),
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_surfaceKey),
          );
          final (rgba, rasterWidth) = (await tester.runAsync(() async {
            final shot = await boundary.toImage(pixelRatio: 2);
            try {
              return (
                (await shot.toByteData(format: ImageByteFormat.rawRgba))!,
                shot.width,
              );
            } finally {
              shot.dispose();
            }
          }))!;
          Color pixel(Offset point) {
            final offset =
                ((point.dy * 2).round() * rasterWidth +
                    (point.dx * 2).round()) *
                4;
            return Color.fromARGB(
              255,
              rgba.getUint8(offset),
              rgba.getUint8(offset + 1),
              rgba.getUint8(offset + 2),
            );
          }

          for (final (i, active) in states.indexed) {
            final button = _control(i);
            final data = tester.getSemantics(button).getSemanticsData();
            expect(
              data.flagsCollection.isSelected,
              active ? Tristate.isTrue : Tristate.isFalse,
            );
            expect(data.hasAction(SemanticsAction.tap), i < 2);
            final fill = pixel(
              tester.getRect(button).centerLeft + const Offset(4, 0),
            );
            expect(
              fill,
              active && i < 2
                  ? theme.colorScheme.secondaryContainer
                  : palette.surface,
            );
            final caption = tester.widget<Text>(find.text('Quick $i'));
            expect(
              contrast(caption.style!.color!, fill),
              greaterThanOrEqualTo(4.5),
            );
            expect(contrast(palette.muted, fill), greaterThanOrEqualTo(3));
            expect(
              find.descendant(of: button, matching: find.byIcon(Icons.check)),
              active ? findsOneWidget : findsNothing,
            );
          }
        },
      );
    }
  }
}
