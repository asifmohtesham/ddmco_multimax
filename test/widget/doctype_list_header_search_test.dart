import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';
import 'package:multimax/app/modules/global_widgets/header_choice_row.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../support/recent_search_test_box.dart';
import '../unit/theme_contrast_test.dart' show contrast;

const _searchLabel = 'Search Item…';
const _height = 720.0;
const _font = 'HeaderSearchTestInter';

void _sizeView(WidgetTester tester, double width, {double height = _height}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

Widget _searchApp({
  required Widget home,
  required Brightness brightness,
  TextDirection direction = TextDirection.ltr,
  double scale = 2,
  AppAccent accent = AppAccent.brand,
  TargetPlatform platform = TargetPlatform.android,
}) => MaterialApp(
  theme: buildAppTheme(
    AppScheme.of(brightness),
    brightness,
    accent: accent,
  ).copyWith(platform: platform),
  locale: const Locale('en'),
  builder: (context, child) => Directionality(
    textDirection: direction,
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(fontFamily: _font),
        ),
        child: child!,
      ),
    ),
  ),
  home: home,
);

Finder _action(String label) => find.byTooltip(label);

void _expectNamedButton(WidgetTester tester, String name) {
  final action = _action(name);
  expect(action, findsOneWidget);
  expect(tester.getSize(action), const Size(48, 48));
  final data = tester.getSemantics(action).getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue, reason: name);
  expect(data.hasAction(SemanticsAction.tap), isTrue, reason: name);
  expect(data.label + data.tooltip, contains(name));
}

Future<void> _open(WidgetTester tester, Finder launcher) async {
  await tester.tap(launcher);
  await tester.pumpAndSettle();
}

Widget _launcher(Future<void> Function(BuildContext) open) => Scaffold(
  body: Builder(
    builder: (context) => TextButton(
      onPressed: () => open(context),
      child: const Text('Open search'),
    ),
  ),
);

Future<void> _previousFocus(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

String? _focusedAction() {
  String? label;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is! IconButton) return true;
    label = widget.tooltip;
    return false;
  });
  return label;
}

void main() {
  setUpAll(() async {
    final loader = FontLoader(_font)
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
    await loader.load();
  });

  testWidgets(
    'Search keeps primary focus when wrapped counts unpin the header',
    (tester) async {
      _sizeView(tester, 320, height: 520);
      final counted = ValueNotifier(false);
      addTearDown(counted.dispose);
      final query = ''.obs;
      const names = [
        'Retail',
        'Trade',
        'Gulf',
        'Export',
        'UAE',
        'Qatar',
        'Oman',
        'Bahrain',
        'Europe',
        'Local',
        'Special',
        'Staff',
      ];
      await tester.pumpWidget(
        _searchApp(
          brightness: Brightness.light,
          scale: 1,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: counted,
              builder: (context, hasCounts, _) => CustomScrollView(
                slivers: [
                  DocTypeListHeader(
                    title: 'Item Price',
                    searchDoctype: 'Item Price',
                    searchQuery: query,
                    onFilterTap: () {},
                    bottom: HeaderChoiceRow(
                      options: [
                        for (final name in names)
                          HeaderChoiceOption(
                            id: name,
                            groupId: 'price-list',
                            label: hasCounts ? '$name (1234)' : name,
                            semanticLabel: name,
                            selected: false,
                            onPressed: () {},
                          ),
                      ],
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 900)),
                ],
              ),
            ),
          ),
        ),
      );

      final header = find.byType(SliverPersistentHeader);
      final search = find.byIcon(Icons.search);
      expect(tester.widget<SliverPersistentHeader>(header).pinned, isTrue);
      final focus = Focus.of(tester.element(search));
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasPrimaryFocus, isTrue);

      counted.value = true;
      await tester.pumpAndSettle();
      expect(tester.widget<SliverPersistentHeader>(header).pinned, isFalse);
      expect(Focus.of(tester.element(search)), same(focus));
      expect(focus.hasPrimaryFocus, isTrue);
    },
  );

  for (final (doctype, height, keyboard, camera) in [
    ('Item', 380.0, 260.0, true),
    ('Material Request', 320.0, 220.0, false),
    ('Item', 320.0, 230.0, true),
    ('Item', 320.0, 270.0, true),
  ]) {
    testWidgets('focused $doctype input fits above a $keyboard dp keyboard', (
      tester,
    ) async {
      _sizeView(tester, 320, height: height);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      await tester.pumpWidget(
        _searchApp(
          brightness: Brightness.light,
          home: _launcher(
            (context) => showListSearch(
              context,
              query: 'bolts',
              doctype: doctype,
              onImageScanResult: camera ? (_) {} : null,
            ),
          ),
        ),
      );
      await _open(tester, find.text('Open search'));
      final field = find.byType(EditableText);
      final original = tester.widget<EditableText>(field);

      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<EditableText>(field).controller,
        original.controller,
      );
      expect(original.focusNode.hasFocus, isTrue);
      expect(
        tester.getCenter(field).dy,
        inInclusiveRange(0, height - keyboard),
      );
      expect(field.hitTestable(), findsOneWidget);
      if (height - keyboard >= 90) {
        expect(
          tester.getBottomLeft(field).dy,
          lessThanOrEqualTo(height - keyboard),
        );
        expect(
          tester.getCenter(_action('Back')).dy,
          closeTo(tester.getCenter(field).dy, 2),
        );
      }
      await tester.enterText(field, 'short window');
      await tester.pump();
      expect(original.controller.text, 'short window');
    });
  }

  testWidgets('short search results scroll above the keyboard', (tester) async {
    _sizeView(tester, 320, height: 320);
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24);
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        home: _launcher(
          (context) => showListSearch(
            context,
            query: 'bolt',
            doctype: 'Material Request',
            targetRoute: '/material-request',
            searcher: (_, _) async => [
              GlobalSearchItem(id: 'b01', title: 'Bolt', rawData: const {}),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final field = find.byType(EditableText);
    expect(field.hitTestable(), findsOneWidget);
    expect(tester.getCenter(field).dy, inInclusiveRange(24, 100));
    await tester.dragFrom(
      tester.getCenter(_action('Back')),
      const Offset(0, -140),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Bolt').hitTestable(), findsOneWidget);
  });

  testWidgets('Clear supersedes the pending controller debounce once', (
    tester,
  ) async {
    _sizeView(tester, 320);
    Timer? pending;
    addTearDown(() => pending?.cancel());
    final changes = <String>[];
    var query = 'bolts';
    var clears = 0;
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        home: _launcher(
          (context) => showListSearch(
            context,
            query: query,
            onSearchChanged: (value) {
              changes.add(value);
              pending?.cancel();
              pending = Timer(
                const Duration(milliseconds: 400),
                () => query = value,
              );
            },
            onSearchClear: () {
              clears++;
              query = '';
            },
          ),
        ),
      ),
    );
    await _open(tester, find.text('Open search'));
    await tester.enterText(find.byType(EditableText), 'WMX');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(_action('Clear search'));
    await tester.pump(const Duration(milliseconds: 450));
    expect(query, isEmpty);
    expect(changes, ['WMX', '']);
    expect(clears, 1);
  });

  for (final direction in TextDirection.values) {
    testWidgets('stacked search tabs by row in ${direction.name}', (
      tester,
    ) async {
      _sizeView(tester, 320);
      await tester.pumpWidget(
        _searchApp(
          brightness: Brightness.light,
          direction: direction,
          home: _launcher(
            (context) => showListSearch(
              context,
              query: 'bolts',
              doctype: 'Item',
              onImageScanResult: (_) {},
            ),
          ),
        ),
      );
      await _open(tester, find.text('Open search'));
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      const reverse = ['Search by image', 'Clear search', 'Back'];
      for (final action in reverse) {
        await _previousFocus(tester);
        expect(_focusedAction(), action);
      }
      for (final action in reverse.take(2).toList().reversed) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_focusedAction(), action);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(field.focusNode.hasFocus, isTrue);
    });
  }

  testWidgets('camera is disabled and announces pending scanning', (
    tester,
  ) async {
    final attempt = Completer<ImageScanResult?>();
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        home: _launcher(
          (context) => showListSearch(
            context,
            doctype: 'Item',
            onImageScanResult: (_) {},
            imageScanner: (_) => attempt.future,
          ),
        ),
      ),
    );
    await _open(tester, find.text('Open search'));
    final camera = _action('Search by image');
    await tester.tap(camera);
    await tester.pump();
    final pending = tester.getSemantics(camera).getSemanticsData();
    expect(pending.flagsCollection.isEnabled, Tristate.isFalse);
    expect(pending.hasAction(SemanticsAction.tap), isFalse);
    expect(pending.value, 'Scanning image');
    expect(pending.flagsCollection.isLiveRegion, isTrue);
    attempt.complete(null);
    await tester.pumpAndSettle();
    _expectNamedButton(tester, 'Search by image');
  });

  testWidgets('ambient direction change retains the edited query and focus', (
    tester,
  ) async {
    final changes = <String>[];
    final home = _launcher(
      (context) =>
          showListSearch(context, query: 'bolt', onSearchChanged: changes.add),
    );
    await tester.pumpWidget(
      _searchApp(brightness: Brightness.light, home: home),
    );
    await _open(tester, find.text('Open search'));
    final field = find.byType(EditableText);
    final original = tester.widget<EditableText>(field);
    await tester.enterText(field, 'bolts');
    await tester.pump();
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        direction: TextDirection.rtl,
        home: home,
      ),
    );
    await tester.pumpAndSettle();
    final current = tester.widget<EditableText>(field);
    expect(Directionality.of(tester.element(field)), TextDirection.rtl);
    expect(current.controller, original.controller);
    expect(current.controller.text, 'bolts');
    expect(current.focusNode.hasFocus, isTrue);
    expect(changes, ['bolts']);
  });

  testWidgets('Windows selects the initial search term when the field opens', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        platform: TargetPlatform.windows,
        scale: 1,
        home: _launcher((context) => showListSearch(context, query: 'bolt')),
      ),
    );
    await _open(tester, find.text('Open search'));
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(
      field.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
  });

  testWidgets('iOS search opens and closes with a 300 ms fade', (tester) async {
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        platform: TargetPlatform.iOS,
        scale: 1,
        home: _launcher((context) => showListSearch(context)),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final field = find.byType(EditableText);
    final route = ModalRoute.of(tester.element(field))!;
    expect(route.transitionDuration, const Duration(milliseconds: 300));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 300));
    final fading = find.ancestor(
      of: field,
      matching: find.byType(FadeTransition),
    );
    expect(
      tester.widget<FadeTransition>(fading.first).opacity.value,
      closeTo(.5, .01),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
    final position = tester.getTopLeft(field);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(field), position);
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    await tester.tap(_action('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widget<FadeTransition>(fading.first).opacity.value,
      closeTo(.5, .01),
    );
    expect(tester.getTopLeft(field), position);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
  });

  testWidgets('API results consume the top safe inset once', (tester) async {
    _sizeView(tester, 411);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 12);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 12);
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        scale: 1,
        home: _launcher(
          (context) => showListSearch(
            context,
            query: 'bolt',
            doctype: 'Item',
            targetRoute: '/item-form',
            searcher: (_, _) async => [
              GlobalSearchItem(id: 'b01', title: 'Bolt', rawData: const {}),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, 'Bolt');
    expect(tester.getTopLeft(tile).dy, 24 + 56);
    final resultList = tester.element(find.byType(ListView));
    expect(MediaQuery.paddingOf(resultList).bottom, 12);
  });

  testWidgets('default search keeps the AppBar leading and field positions', (
    tester,
  ) async {
    _sizeView(tester, 411);
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        scale: 1,
        home: _launcher((context) => showListSearch(context)),
      ),
    );
    await _open(tester, find.text('Open search'));
    expect(tester.getCenter(_action('Back')).dx, 28);
    expect(tester.getTopLeft(find.byType(EditableText)).dx, 72);
  });

  testWidgets('API submit and refocus reopen the result list at its top', (
    tester,
  ) async {
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        scale: 1,
        home: _launcher(
          (context) => showListSearch(
            context,
            query: 'bolt',
            doctype: 'Item',
            targetRoute: '/item-form',
            searcher: (_, _) async => List.generate(
              30,
              (index) => GlobalSearchItem(
                id: '$index',
                title: 'Bolt $index',
                rawData: const {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final first = find.text('Bolt 0').hitTestable();
    final list = find.byType(ListView);
    expect(first, findsOneWidget);
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(first, findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(first, findsOneWidget);
    final editable = find.byType(EditableText);
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);

    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(first, findsNothing);
    await tester.tap(editable);
    await tester.pumpAndSettle();
    expect(first, findsOneWidget);
  });

  testWidgets('search range underline retains IME composing text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        home: _launcher((context) => showListSearch(context)),
      ),
    );
    await _open(tester, find.text('Open search'));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'bolts',
        selection: TextSelection(baseOffset: 2, extentOffset: 4),
        composing: TextRange(start: 1, end: 5),
      ),
    );
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final span = editable.buildTextSpan();
    expect(span.toPlainText(), 'bolts');
    final parts = span.children!.cast<TextSpan>();
    expect(parts.map((part) => part.text), ['b', 'o', 'lt', 's']);
    expect(parts[0].style?.decoration, isNull);
    expect(parts[1].style?.decoration, TextDecoration.underline);
    expect(parts[2].style?.decoration, TextDecoration.underline);
    expect(parts[2].style?.decorationColor, isNotNull);
    expect(parts[3].style?.decoration, TextDecoration.underline);
  });

  for (final width in [320.0, 411.0]) {
    for (final brightness in Brightness.values) {
      for (final direction in TextDirection.values) {
        testWidgets(
          'toolbar and edit search preserve existing query and close behavior '
          'at $width ${brightness.name} ${direction.name}',
          (tester) async {
            _sizeView(tester, width);
            const initial = 'bolts and hex nuts';
            final query = initial.obs;
            final filters = {'status': 'Draft'};
            final changes = <String>[];
            final scans = <ImageScanResult>[];
            void onChange(String value) {
              changes.add(value);
              query.value = value;
            }

            await tester.pumpWidget(
              _searchApp(
                brightness: brightness,
                direction: direction,
                home: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      DocTypeListHeader(
                        title: 'Item',
                        searchDoctype: 'Item',
                        searchQuery: query,
                        onSearchChanged: onChange,
                        onImageScanResult: scans.add,
                        filterChipsBuilder: (context) => [
                          FilterChipWidget(
                            icon: Icons.search,
                            label: 'Search: ${query.value}',
                            onDeleted: () => onChange(''),
                            onTap: () => editListSearch(
                              context,
                              searchQuery: query,
                              doctype: 'Item',
                              onSearchChanged: onChange,
                              onImageScanResult: scans.add,
                            ),
                          ),
                        ],
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 500)),
                    ],
                  ),
                ),
              ),
            );

            final field = find.byType(EditableText);
            final toolbar = _action('Search Item, current query: $initial');
            await _open(tester, toolbar);
            final editing = tester.widget<EditableText>(field);
            expect(editing.controller.text, initial);
            expect(editing.controller.selection.extentOffset, initial.length);
            final renderEditable = tester
                .state<EditableTextState>(field)
                .renderEditable;
            expect(renderEditable.textScaler.scale(22), 44);
            final caret = renderEditable.getLocalRectForCaret(
              editing.controller.selection.extent,
            );
            expect(
              caret.center.dx,
              inInclusiveRange(0, renderEditable.size.width),
            );
            expect(editing.focusNode.hasFocus, isTrue);
            expect(editing.cursorColor, isNotNull);
            expect(tester.getSemantics(field).label, _searchLabel);
            expect(changes, isEmpty);

            for (final label in ['Back', 'Clear search', 'Search by image']) {
              _expectNamedButton(tester, label);
            }
            final backX = tester.getCenter(_action('Back')).dx;
            final clearX = tester.getCenter(_action('Clear search')).dx;
            final cameraX = tester.getCenter(_action('Search by image')).dx;
            if (direction == TextDirection.ltr) {
              expect(backX, lessThan(clearX));
              expect(clearX, lessThan(cameraX));
            } else {
              expect(backX, greaterThan(clearX));
              expect(clearX, greaterThan(cameraX));
            }
            expect(
              tester.getTopLeft(field).dy,
              greaterThanOrEqualTo(tester.getBottomLeft(_action('Back')).dy),
            );

            tester.view.viewInsets = const FakeViewPadding(bottom: 350);
            tester.view.physicalSize = Size(width == 320 ? 411 : 320, _height);
            await tester.pumpAndSettle();
            expect(
              tester.widget<EditableText>(field).controller,
              editing.controller,
            );
            expect(editing.focusNode.hasFocus, isTrue);
            expect(editing.controller.selection.extentOffset, initial.length);

            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(field, findsNothing);
            expect(changes, isEmpty);

            await _open(tester, find.bySemanticsLabel('Edit Search: $initial'));
            expect(tester.widget<EditableText>(field).controller.text, initial);
            expect(changes, isEmpty);

            await tester.tap(_action('Clear search'));
            await tester.pumpAndSettle();
            expect(tester.widget<EditableText>(field).controller.text, isEmpty);
            expect(changes, ['']);
            expect(filters, {'status': 'Draft'});
            expect(_action('Clear search'), findsNothing);

            await tester.enterText(field, 'catalog');
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await tester.pumpAndSettle();
            expect(field, findsNothing);
            expect(changes, ['', 'catalog']);
            expect(
              _action('Search Item, current query: catalog'),
              findsOneWidget,
            );
            expect(scans, isEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'search buttons support keyboard, camera cancel and return focus',
    (tester) async {
      final launcher = FocusNode();
      addTearDown(launcher.dispose);
      _sizeView(tester, 320);
      final scans = <ImageScanResult>[];
      var clearCalls = 0;
      final changes = <String>[];
      var query = 'bolts';
      final attempts = <Completer<ImageScanResult?>>[];

      await tester.pumpWidget(
        _searchApp(
          brightness: Brightness.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                focusNode: launcher,
                onPressed: () => showListSearch(
                  context,
                  query: query,
                  doctype: 'Item',
                  onSearchChanged: changes.add,
                  onSearchClear: () {
                    clearCalls++;
                    query = '';
                  },
                  onImageScanResult: scans.add,
                  imageScanner: (_) {
                    final attempt = Completer<ImageScanResult?>();
                    attempts.add(attempt);
                    return attempt.future;
                  },
                ),
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      );

      launcher.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      await _previousFocus(tester);
      await _previousFocus(tester);
      expect(_focusedAction(), 'Clear search');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(clearCalls, 1);
      expect(changes, isEmpty);
      expect(field.focusNode.hasFocus, isTrue);

      final camera = _action('Search by image');
      final isStacked =
          tester.getCenter(camera).dy <
          tester.getTopLeft(find.byType(EditableText)).dy;
      if (isStacked) {
        await _previousFocus(tester);
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(attempts, hasLength(1));
      attempts.single.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget);
      expect(scans, isEmpty);

      await tester.tap(camera);
      await tester.pump();
      expect(attempts, hasLength(2));
      const result = ImageScanResult(itemCode: 'ITEM-002', batchNo: 'A-1');
      attempts.last.complete(result);
      await tester.pumpAndSettle();
      expect(scans, [result]);
      expect(find.byType(EditableText), findsNothing);
      expect(launcher.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      if (isStacked) await _previousFocus(tester);
      await _previousFocus(tester);
      expect(_focusedAction(), 'Back');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(launcher.hasFocus, isTrue);
      expect(find.byType(EditableText), findsNothing);
      expect(changes, isEmpty);
    },
  );

  testWidgets('a scoped scaler follows the search toolbar across the route', (
    tester,
  ) async {
    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        scale: 1,
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showListSearch(context, doctype: 'Item'),
                  child: const Text('Open search'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _open(tester, find.text('Open search'));
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(editable.textScaler.scale(22), 44);
    final bodyHint = tester.element(find.text('Type to search the list'));
    expect(MediaQuery.textScalerOf(bodyHint).scale(22), 22);
  });

  testWidgets('API search debounces and keeps history in the source scope', (
    tester,
  ) async {
    final box = RecentSearchTestBox();
    final storage = StorageService.withStorage(box);
    const user = 'search@example.com';
    const history = '/inventory/item';
    await storage.addRecentSearch(history, user, 'Blue widgets');
    await storage.addRecentSearch('Item', user, 'Office supplies');
    final requests = <String>[];

    await tester.pumpWidget(
      _searchApp(
        brightness: Brightness.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showListSearch(
                context,
                doctype: 'Item',
                targetRoute: '/item-form',
                recentSearchKey: history,
                recentSearchStore: (storage: storage, user: user),
                searcher: (doctype, query) async {
                  expect(doctype, 'Item');
                  requests.add(query);
                  return const <GlobalSearchItem>[];
                },
              ),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    );
    await _open(tester, find.text('Open search'));
    expect(find.text('Blue widgets'), findsOneWidget);
    expect(find.text('Office supplies'), findsNothing);

    final field = find.byType(EditableText);
    await tester.enterText(field, 'bo');
    await tester.pump(const Duration(milliseconds: 350));
    expect(requests, isEmpty);

    await tester.enterText(field, 'bol');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'bolt');
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(requests, ['bolt']);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    expect(requests, ['bolt']);
    expect(storage.getRecentSearches(history, user), ['bolt', 'Blue widgets']);
    expect(storage.getRecentSearches('Item', user), ['Office supplies']);

    await tester.enterText(field, 'cancelled');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    expect(requests, ['bolt']);
  });

  testWidgets(
    'rendered search actions and selection pass across all palettes',
    (tester) async {
      const cases = [
        <WidgetState>{},
        {WidgetState.hovered},
        {WidgetState.focused},
        {WidgetState.pressed},
        {WidgetState.hovered, WidgetState.focused, WidgetState.pressed},
      ];
      for (final brightness in Brightness.values) {
        for (final accent in AppAccent.all) {
          final scheme = AppScheme.of(brightness);
          await tester.pumpWidget(
            _searchApp(
              brightness: brightness,
              accent: accent,
              scale: 1,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showListSearch(
                      context,
                      query: 'bolts',
                      doctype: 'Item',
                      onImageScanResult: (_) {},
                    ),
                    child: const Text('Open search'),
                  ),
                ),
              ),
            ),
          );
          await _open(tester, find.text('Open search'));
          for (final label in ['Back', 'Clear search', 'Search by image']) {
            final button = tester.widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == label,
              ),
            );
            for (final states in cases) {
              final ink = button.style!.foregroundColor!.resolve(states)!;
              expect(contrast(ink, scheme.fg), greaterThanOrEqualTo(3));
              expect(
                button.style!.overlayColor!.resolve(states),
                Colors.transparent,
              );
            }
          }

          final editable = find.byType(EditableText);
          final field = tester.widget<EditableText>(editable);
          final selection = TextSelectionTheme.of(
            tester.element(find.byType(EditableText)),
          );
          final fill = field.selectionColor!;
          expect(
            contrast(field.style.color!, scheme.fg),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrast(field.style.color!, fill), greaterThanOrEqualTo(4.5));
          expect(
            contrast(field.cursorColor, scheme.fg),
            greaterThanOrEqualTo(3),
          );
          expect(
            contrast(selection.selectionHandleColor!, scheme.fg),
            greaterThanOrEqualTo(3),
          );
          expect(
            contrast(selection.selectionHandleColor!, fill),
            greaterThanOrEqualTo(3),
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(field.controller.selection.start, 4);
          expect(field.controller.selection.end, 5);
          final span = tester
              .state<EditableTextState>(editable)
              .buildTextSpan();
          final selected = span.children?.whereType<TextSpan>().singleWhere(
            (part) => part.text == 's',
          );
          expect(selected?.style?.decoration, TextDecoration.underline);
          expect(
            contrast(selected!.style!.decorationColor!, fill),
            greaterThanOrEqualTo(3),
          );

          await tester.tap(_action('Back'));
          await tester.pumpAndSettle();
        }
      }
    },
  );
}
