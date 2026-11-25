import 'dart:async';
import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/header_choice_row.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_screen.dart';
import 'package:multimax/app/modules/pricing/item_price/widgets/item_price_list_app_bar.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_screen.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/widgets/pricing_rule_list_app_bar.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../unit/theme_contrast_test.dart' show contrast;

const _font = 'Pricing strip Inter';
const _lists = ['A', 'Standard Buying', 'Standard Selling', 'Special orders'];
const _wideList =
    'Tarification internationale des commandes professionnelles saisonnières';
const _scales = [0.85, 1.0, 1.3, 2.0];
const _regionalNames = [
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

Rect _scrollableBounds(WidgetTester tester, ScrollableState scrollable) =>
    tester.getRect(find.byWidget(scrollable.widget));

void _expectChipVisible(WidgetTester tester, Finder target) {
  final bounds = tester.getRect(target);
  BuildContext context = tester.element(target);
  while (true) {
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (scrollable == null) break;
    final viewport = _scrollableBounds(tester, scrollable);
    expect(bounds.top, greaterThanOrEqualTo(viewport.top - .01));
    expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + .01));
    context = scrollable.context;
  }
}

enum _Screen { itemPrice, pricingRule }

class _Permissions extends PermissionService {
  final _canCreate = false.obs;

  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) =>
      permType != 'create' || _canCreate.value;
}

class _Requests {
  _Requests(this.screen);
  final _Screen screen;
  int calls = 0;
  Completer<Response>? pending;

  Response get result => Response(
    requestOptions: RequestOptions(path: '/pricing'),
    statusCode: 200,
    data: {
      'data': [
        for (var i = 0; i < 18; i++)
          if (screen == _Screen.itemPrice)
            {
              'name': 'price-$i',
              'item_code': 'ABC$i',
              'item_name': 'Price result $i',
              'price_list': 'Standard Selling',
              'price_list_rate': 25,
              'currency': 'AED',
            }
          else
            {
              'name': 'rule-$i',
              'title': 'Rule result $i',
              'price_or_product_discount': 'Price',
              'selling': 1,
            },
      ],
    },
  );

  Future<Response> fetch() async {
    calls++;
    final request = pending;
    return request == null ? result : await request.future;
  }
}

class _Prices extends ItemPriceProvider {
  _Prices(this.requests, this.names, this.pendingCounts);
  final _Requests requests;
  final List<String> names;
  final Future<int>? pendingCounts;

  @override
  Future<Response> getItemPrices({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    String orderBy = 'modified desc',
  }) => requests.fetch();

  @override
  Future<Response> getPriceLists() async => Response(
    requestOptions: RequestOptions(path: '/price-list'),
    data: {
      'data': [
        for (final name in names) {'name': name},
      ],
    },
  );

  @override
  Future<int> count(List<List<dynamic>> filters) async =>
      await pendingCounts ?? (filters.isEmpty ? 18 : 0);
}

class _Rules extends PricingRuleProvider {
  _Rules(this.requests);
  final _Requests requests;

  @override
  Future<Response> getRules({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) => requests.fetch();

  @override
  Future<int> count(List<List<dynamic>> filters) async =>
      filters.isEmpty ? 18 : 0;

  @override
  Future<void> attachTargets(List<PricingRule> rules) async {}
}

class _Fixture {
  _Fixture(this.screen) : requests = _Requests(screen);
  final _Screen screen;
  final _Requests requests;
  ItemPriceController? prices;
  PricingRuleController? rules;

  bool get item => screen == _Screen.itemPrice;
  String get selection =>
      prices?.selectedPriceList.value ?? rules!.status.value;
  set selection(String value) {
    (prices?.selectedPriceList ?? rules!.status).value = value;
  }

  String get updateLabel => item ? 'Updating prices' : 'Updating pricing rules';
  String get resultText => item ? 'Price result 0' : 'Rule result 0';
  String get applied => item ? 'Validity: Active' : 'Side: Selling';
  String get sheet => item ? 'Filter prices' : 'Side';
  String get doctype => item ? 'Item Price' : 'Pricing Rule';

  ScrollController get vertical =>
      prices?.scrollController ?? rules!.scrollController;
  Map<String, dynamic> get filters =>
      prices?.activeFilters ?? rules!.activeFilters;
  Map<String, int> get counts => prices?.listCounts ?? rules!.statusCounts;
  List<String> get values => [
    '',
    if (item)
      ...prices!.priceLists.map((list) => list.name)
    else
      ...PricingRuleController.statuses,
  ];

  void apply({bool second = false}) {
    filters.clear();
    if (item) {
      filters['validity'] = 'Active';
      if (second) filters['batch'] = true;
    } else {
      filters['side'] = 'Selling';
    }
  }

  Widget screenWidget() =>
      item ? const ItemPriceScreen() : const PricingRuleScreen();

  Widget headerWidget() =>
      item ? const ItemPriceListAppBar() : const PricingRuleListAppBar();

  Future<void> pump(
    WidgetTester tester, {
    double width = 411,
    double height = 850,
    TextDirection direction = TextDirection.ltr,
    TextScaler? scaler,
    bool bold = false,
    bool headerOnly = false,
    bool applyFilter = false,
    bool appPreset = false,
    List<String> names = _lists,
    Future<int>? pendingCounts,
    bool canCreate = false,
  }) async {
    await tester.pumpWidget(const SizedBox());
    Get.reset();
    Get.testMode = true;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    Get.put(ApiProvider());
    Get.put(AuthenticationController());
    Get.put<PermissionService>(_Permissions().._canCreate.value = canCreate);
    if (appPreset) {
      Get.put(
        ThemeController(persist: (_, _) async {}, restore: (_) async => null),
      ).textSize.value = AppTextSize.large;
    }
    if (item) {
      Get.put<ItemPriceProvider>(_Prices(requests, names, pendingCounts));
      prices = Get.put<ItemPriceController>(ItemPriceController());
    } else {
      Get.put<PricingRuleProvider>(_Rules(requests));
      rules = Get.put<PricingRuleController>(PricingRuleController());
    }
    if (applyFilter) apply();
    final theme = buildAppTheme(
      AppScheme.light,
      Brightness.light,
      accent: AppAccent.blue,
    );
    await tester.pumpWidget(
      GetMaterialApp(
        getPages: [
          GetPage(
            name: AppRoutes.ITEM_PRICE_FORM,
            page: () => const Scaffold(body: Text('Item Price form fixture')),
          ),
        ],
        theme: theme.copyWith(
          platform: TargetPlatform.android,
          textTheme: theme.textTheme.apply(fontFamily: _font),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: appPreset ? const TextScaler.linear(1.12) : scaler,
            boldText: bold,
          ),
          child: Directionality(textDirection: direction, child: child!),
        ),
        home: headerOnly
            ? Scaffold(
                body: CustomScrollView(
                  controller: vertical,
                  slivers: [
                    headerWidget(),
                    const SliverToBoxAdapter(child: SizedBox(height: 1600)),
                  ],
                ),
              )
            : screenWidget(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

Finder _chip(String value) => find.byWidgetPredicate(
  (widget) =>
      widget is HeaderChoiceButton &&
      (widget.option.id == 'price-list:$value' ||
          widget.option.id == 'rule-status:$value'),
);

Finder _button(String value) =>
    find.descendant(of: _chip(value), matching: find.byType(TextButton));

Finder _captionWidget(WidgetTester tester, String value) => find.descendant(
  of: _chip(value),
  matching: find.text(_caption(tester, value)),
);

RenderParagraph _paragraph(WidgetTester tester, String value) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: _captionWidget(tester, value),
        matching: find.byType(RichText),
      ),
    );

Finder _headerButton(String name) => find.byWidgetPredicate(
  (widget) => widget is HeaderChipButton && widget.label == name,
);

final _row = find.byType(HeaderChoiceRow);
final _header = find.descendant(
  of: find.byType(DocTypeListHeader),
  matching: find.byType(SliverPersistentHeader),
);

SemanticsNode _node(WidgetTester tester, String name) =>
    tester.semantics.simulatedAccessibilityTraversal().singleWhere((node) {
      final data = node.getSemanticsData();
      return data.label == name || data.tooltip == name;
    });

String _caption(WidgetTester tester, String value) =>
    tester.widget<HeaderChoiceButton>(_chip(value)).option.label;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

double _contour(WidgetTester tester, String value) {
  final contour = tester.widget<HeaderActionContour>(
    find.descendant(
      of: _button(value),
      matching: find.byType(HeaderActionContour),
    ),
  );
  return headerContourWidth(contour.states);
}

FocusNode _chipFocus(WidgetTester tester, String value) =>
    tester.widget<TextButton>(_button(value)).focusNode!;

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 13 ? fontSize * 1.5 : fontSize * 2;

  @override
  bool operator ==(Object other) => other is _NonlinearScaler;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  double get textScaleFactor => 2;
}

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => r'C:\temp\test_cookies',
        );
    final font = FontLoader(_font);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('lib/assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  tearDown(Get.reset);

  void prepare(WidgetTester tester) {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'late counts keep the focused price list visible in ${direction.name}',
      (tester) async {
        prepare(tester);
        final counts = Completer<int>();
        final names = List.generate(8, (i) => 'List $i');
        final f = _Fixture(_Screen.itemPrice);
        await f.pump(
          tester,
          direction: direction,
          names: names,
          pendingCounts: counts.future,
        );

        _chipFocus(tester, '').requestFocus();
        await tester.pumpAndSettle();
        for (final name in names) {
          await _key(tester, LogicalKeyboardKey.tab);
          expect(_chipFocus(tester, name).hasPrimaryFocus, isTrue);
        }
        final focused = names.last;
        final focus = _chipFocus(tester, focused);
        final target = _button(focused);
        final before = tester.getRect(target);
        final rowHeight = tester.getSize(_row).height;
        expect(f.counts, isEmpty);

        counts.complete(123456);
        await tester.pumpAndSettle();

        expect(_caption(tester, focused), '$focused (123456)');
        expect(_chipFocus(tester, focused), same(focus));
        expect(focus.hasPrimaryFocus, isTrue);
        expect(tester.getSize(_row).height, greaterThan(rowHeight));
        final after = tester.getRect(target);
        final viewport = Offset.zero & tester.view.physicalSize;
        expect(after.top, greaterThan(before.top));
        expect(after.left, greaterThanOrEqualTo(viewport.left));
        expect(after.right, lessThanOrEqualTo(viewport.right));
        expect(after.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'late counts reveal the focused price list in a short ${direction.name} viewport',
      (tester) async {
        prepare(tester);
        final counts = Completer<int>();
        final names = List.generate(16, (i) => 'List $i');
        final f = _Fixture(_Screen.itemPrice);
        await f.pump(
          tester,
          direction: direction,
          names: names,
          pendingCounts: counts.future,
        );
        tester.view.physicalSize = const Size(411, 320);
        await tester.pumpAndSettle();
        for (final name in ['', ...names]) {
          _chipFocus(tester, name).requestFocus();
          await tester.pumpAndSettle();
        }

        final focused = names.last;
        final focus = _chipFocus(tester, focused);
        final target = _button(focused);
        expect(focus.hasPrimaryFocus, isTrue);
        _expectChipVisible(tester, target);
        final rowHeight = tester.getSize(_row).height;
        expect(f.counts, isEmpty);

        counts.complete(123456);
        await tester.pumpAndSettle();

        expect(_caption(tester, focused), '$focused (123456)');
        expect(_chipFocus(tester, focused), same(focus));
        expect(focus.hasPrimaryFocus, isTrue);
        expect(tester.getSize(_row).height, greaterThan(rowHeight));
        _expectChipVisible(tester, target);
      },
    );

    testWidgets(
      'opposite price-list arrow retraces an uneven ${direction.name} run',
      (tester) async {
        prepare(tester);
        final f = _Fixture(_Screen.itemPrice);
        await f.pump(tester, direction: direction, names: _regionalNames);
        f.counts.clear();
        await tester.pumpAndSettle();

        final local = _chipFocus(tester, 'Local');
        final staff = _chipFocus(tester, 'Staff');
        local.requestFocus();
        await tester.pumpAndSettle();
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus, same(staff));
        await _key(tester, LogicalKeyboardKey.arrowUp);
        expect(FocusManager.instance.primaryFocus, same(local));

        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus, same(staff));
        _chipFocus(tester, 'Retail').requestFocus();
        await tester.pumpAndSettle();
        staff.requestFocus();
        await tester.pumpAndSettle();
        await _key(tester, LogicalKeyboardKey.arrowUp);
        expect(
          FocusManager.instance.primaryFocus,
          same(_chipFocus(tester, 'Europe')),
        );
      },
    );
  }

  testWidgets(
    'accessibility focus reveals a clipped price-list chip without moving keyboard focus',
    (tester) async {
      prepare(tester);
      final f = _Fixture(_Screen.itemPrice);
      await f.pump(tester, width: 320, names: _regionalNames);
      f.counts.clear();
      tester.view.physicalSize = const Size(320, 320);
      await tester.pumpAndSettle();

      final keyboardFocus = _chipFocus(tester, '');
      keyboardFocus.requestFocus();
      await tester.pumpAndSettle();
      final target = _button('Europe');
      final scrollable = Scrollable.of(
        tester.element(target),
        axis: Axis.vertical,
      );
      final position = scrollable.position;
      final viewport = _scrollableBounds(tester, scrollable);
      position.jumpTo(
        position.pixels + tester.getRect(target).bottom - viewport.bottom - 20,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(target).bottom, closeTo(viewport.bottom + 20, .01));
      expect(tester.getRect(target).top, lessThan(viewport.bottom));
      expect(keyboardFocus.hasPrimaryFocus, isTrue);
      final node = _node(tester, 'Europe');
      node.owner!.performAction(
        node.id,
        SemanticsAction.didGainAccessibilityFocus,
      );
      await tester.pumpAndSettle();

      _expectChipVisible(tester, target);
      expect(FocusManager.instance.primaryFocus, same(keyboardFocus));
    },
  );

  testWidgets(
    'a multiline price list keeps its entire caption inside the choice pill',
    (tester) async {
      prepare(tester);
      const name =
          'International Wholesale Distribution Preferred Customer Price List for United Arab Emirates and Saudi Arabia';
      final f = _Fixture(_Screen.itemPrice);
      await f.pump(
        tester,
        scaler: const TextScaler.linear(2),
        names: const ['A', name],
      );
      f.selection = name;
      await tester.pumpAndSettle();

      final pill = find.descendant(
        of: _button(name),
        matching: find.byType(HeaderPill),
      );
      final shortPill = find.descendant(
        of: _button('A'),
        matching: find.byType(HeaderPill),
      );
      final pillRect = tester.getRect(pill);
      final singleLineHeight = tester.getSize(shortPill).height;
      expect(pillRect.height, greaterThan(singleLineHeight));
      final shortRadius = singleLineHeight / 2;
      expect(
        tester.renderObject<RenderCustomPaint>(
          find.descendant(of: pill, matching: find.byType(CustomPaint)),
        ),
        paints..rrect(
          rrect: RRect.fromRectAndRadius(
            (Offset.zero & pillRect.size).deflate(.5),
            Radius.circular(shortRadius),
          ),
        ),
      );

      final caption = _paragraph(tester, name);
      expect(caption.didExceedMaxLines, isFalse);
      expect(caption.text.toPlainText(), _caption(tester, name));
      final fill = RRect.fromRectAndRadius(
        pillRect.deflate(.5),
        Radius.circular(shortRadius),
      );
      final lineBoxes = caption.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: caption.text.toPlainText().length,
        ),
      );
      for (final line in lineBoxes) {
        final bounds = line
            .toRect()
            .shift(caption.localToGlobal(Offset.zero))
            .deflate(1);
        for (final point in [
          bounds.topLeft,
          bounds.topRight,
          bounds.bottomLeft,
          bounds.bottomRight,
        ]) {
          expect(fill.contains(point), isTrue);
        }
      }

      _chipFocus(tester, name).requestFocus();
      await tester.pumpAndSettle();
      final contour = tester.widget<HeaderActionContour>(
        find.descendant(
          of: _button(name),
          matching: find.byType(HeaderActionContour),
        ),
      );
      expect(contour.borderRadius, shortRadius + 3.5);
    },
  );

  testWidgets('each price-list and rule-status chip responds at its corners', (
    tester,
  ) async {
    prepare(tester);
    for (final screen in _Screen.values) {
      final f = _Fixture(screen);
      await f.pump(tester);
      for (final collapsed in [false, true]) {
        final delegate = tester
            .widget<SliverPersistentHeader>(_header)
            .delegate;
        if (collapsed) {
          f.vertical.jumpTo(delegate.maxExtent - delegate.minExtent);
          await tester.pumpAndSettle();
        }
        for (final value in f.values) {
          for (final upper in [true, false]) {
            final other = f.values.firstWhere((option) => option != value);
            f.selection = other;
            await tester.pumpAndSettle();
            final native = tester.getRect(_button(value));
            final semantic = _node(tester, _caption(tester, value));
            expect(native.height, greaterThanOrEqualTo(48), reason: value);
            expect(native.width, greaterThanOrEqualTo(48), reason: value);
            expect(semantic.rect.height, greaterThanOrEqualTo(48));
            expect(semantic.rect.width, greaterThanOrEqualTo(48));
            final before = f.requests.calls;
            final outside = upper ? native.top - 1 : native.bottom + 1;
            await tester.tapAt(Offset(native.center.dx, outside));
            await tester.pumpAndSettle();
            expect(f.selection, other);
            expect(f.requests.calls, before);
            expect(f.filters, isEmpty);
            expect(find.text(f.sheet), findsNothing);
            final edge = upper ? native.top + 1 : native.bottom - 1;
            final x = upper ? native.left + 1 : native.right - 1;
            await tester.tapAt(Offset(x, edge));
            await tester.pumpAndSettle();
            expect(
              f.selection,
              value,
              reason: 'target at $native, probe ($x, $edge)',
            );
            expect(f.requests.calls, before + 1);
          }
        }
        final first = tester.getRect(_button(''));
        final second = tester.getRect(_button(f.values[1]));
        final calls = f.requests.calls;
        await tester.tapAt(
          Offset((first.right + second.left) / 2, first.center.dy),
        );
        await tester.pumpAndSettle();
        expect(f.requests.calls, calls);
      }
    }
  });

  testWidgets(
    'the quick row and applied actions keep independent hit regions',
    (tester) async {
      prepare(tester);
      for (final screen in _Screen.values) {
        final f = _Fixture(screen);
        await f.pump(tester, headerOnly: true);
        final edit = 'Edit ${f.applied}';
        final reset = 'Reset ${f.applied}';
        final labels = ['Add filter', edit, reset, if (f.item) 'Reset filters'];
        for (final name in labels) {
          for (final upper in [true, false]) {
            f.apply(second: f.item);
            await tester.pumpAndSettle();
            final target = tester.getRect(_headerButton(name));
            expect(target.height, greaterThanOrEqualTo(48));
            expect(target.width, greaterThanOrEqualTo(48));
            final calls = f.requests.calls;
            final filters = Map.of(f.filters);
            await tester.tapAt(
              Offset(
                target.center.dx,
                upper ? target.top - 1 : target.bottom + 1,
              ),
            );
            await tester.pumpAndSettle();
            expect(f.requests.calls, calls);
            expect(f.filters, filters);
            expect(find.text(f.sheet), findsNothing);
            final x = name == edit
                ? target.right - 1
                : name == reset
                ? target.left + 1
                : target.center.dx;
            await tester.tapAt(
              Offset(x, upper ? target.top + 1 : target.bottom - 1),
            );
            await tester.pumpAndSettle();
            expect(f.selection, '');
            if (name == 'Add filter' || name == edit) {
              expect(find.text(f.sheet), findsOneWidget);
              expect(f.filters, filters);
              final context = tester.element(find.text(f.sheet));
              Navigator.of(context).pop();
              await tester.pumpAndSettle();
            } else {
              expect(f.requests.calls, calls + 1);
              expect(
                f.filters.containsKey(f.item ? 'validity' : 'side'),
                isFalse,
              );
              if (name == 'Reset filters') expect(f.filters, isEmpty);
            }
          }
        }
      }
    },
  );

  testWidgets(
    'pricing choices expose a name, role and selection with stable captions',
    (tester) async {
      prepare(tester);
      for (final screen in _Screen.values) {
        final f = _Fixture(screen);
        await f.pump(tester, headerOnly: true);
        expect(_caption(tester, f.values.last), '${f.values.last} (0)');
        final originalTargets = {
          for (final value in f.values) value: tester.getRect(_button(value)),
        };
        for (final value in f.values) {
          final data = _node(
            tester,
            _caption(tester, value),
          ).getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          expect(
            data.flagsCollection.isSelected,
            value.isEmpty ? Tristate.isTrue : Tristate.isFalse,
          );
        }
        final value = f.values[1];
        await tester.tap(_button(value));
        await tester.pumpAndSettle();
        for (final option in f.values) {
          final target = tester.getRect(_button(option));
          final caption = _captionWidget(tester, option);
          expect(target, originalTargets[option]);
          expect(tester.getCenter(caption).dx, closeTo(target.center.dx, .01));
          final tick = find.descendant(
            of: _chip(option),
            matching: find.byIcon(Icons.check),
          );
          expect(tick, option == value ? findsOneWidget : findsNothing);
          if (option == value) {
            final palette = HeaderPalette.of(tester.element(_chip(option)));
            final pill = tester.widget<HeaderPill>(
              find.descendant(
                of: _chip(option),
                matching: find.byType(HeaderPill),
              ),
            );
            final text = tester.widget<Text>(caption);
            final check = tester.widget<Icon>(tick);
            expect(
              contrast(pill.fill, palette.surface),
              greaterThanOrEqualTo(3),
            );
            expect(
              contrast(text.style!.color!, pill.fill),
              greaterThanOrEqualTo(4.5),
            );
            expect(contrast(check.color!, pill.fill), greaterThanOrEqualTo(3));
          }
        }
        expect(
          _node(
            tester,
            _caption(tester, value),
          ).getSemanticsData().flagsCollection.isSelected,
          Tristate.isTrue,
        );
        expect(
          _node(
            tester,
            _caption(tester, ''),
          ).getSemanticsData().flagsCollection.isSelected,
          Tristate.isFalse,
        );
        final calls = f.requests.calls;
        await tester.tap(_button(value));
        await tester.pumpAndSettle();
        expect(f.requests.calls, calls);
        await tester.tap(_button(''));
        await tester.pumpAndSettle();
        expect(f.selection, '');
        expect(f.requests.calls, calls + 1);
      }
    },
  );

  testWidgets('pricing header targets meet Flutter accessibility guidelines', (
    tester,
  ) async {
    prepare(tester);
    for (final screen in _Screen.values) {
      final f = _Fixture(screen);
      await f.pump(tester, headerOnly: true, applyFilter: true);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }
  });

  testWidgets('Tab traverses wrapped pricing choices in LTR and RTL', (
    tester,
  ) async {
    prepare(tester);
    final manager = FocusManager.instance;
    final previous = manager.highlightStrategy;
    manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => manager.highlightStrategy = previous);
    for (final screen in _Screen.values) {
      for (final direction in TextDirection.values) {
        final f = _Fixture(screen);
        await f.pump(tester, direction: direction, headerOnly: true);
        final search = find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is HeaderIconAction &&
                widget.tooltip == 'Search ${f.doctype}',
          ),
          matching: find.byIcon(Icons.search),
        );
        Focus.of(tester.element(search)).requestFocus();
        await tester.pumpAndSettle();
        final bounds = tester.getRect(_row);
        for (final value in f.values) {
          await _key(tester, LogicalKeyboardKey.tab);
          expect(
            _chipFocus(tester, value).hasPrimaryFocus,
            isTrue,
            reason: value,
          );
          final data = _node(
            tester,
            _caption(tester, value),
          ).getSemanticsData();
          expect(
            data.flagsCollection.isFocused,
            Tristate.isTrue,
            reason: value,
          );
          final box = tester.getRect(_button(value));
          expect(box.left, greaterThanOrEqualTo(bounds.left));
          expect(box.right, lessThanOrEqualTo(bounds.right));
          expect(_contour(tester, value), 2);
        }
        await _key(tester, LogicalKeyboardKey.tab);
        expect(
          _node(
            tester,
            'Add filter',
          ).getSemanticsData().flagsCollection.isFocused,
          Tristate.isTrue,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await _key(tester, LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        final last = f.values.last;
        expect(_chipFocus(tester, last).hasPrimaryFocus, isTrue);
        final calls = f.requests.calls;
        await _key(tester, LogicalKeyboardKey.enter);
        expect(f.selection, last);
        expect(f.requests.calls, calls + 1);

        final value = f.values[f.values.length - 2];
        _chipFocus(tester, value).requestFocus();
        await tester.pumpAndSettle();
        final press = await tester.startGesture(
          tester.getCenter(_button(value)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(_contour(tester, value), 3);
        await press.cancel();
        await tester.pumpAndSettle();
        await _key(tester, LogicalKeyboardKey.space);
        expect(f.selection, value);
        expect(f.requests.calls, calls + 2);
      }
    }
  });

  testWidgets('pricing chips mirror wrapped positions and keep spoken order', (
    tester,
  ) async {
    prepare(tester);
    for (final screen in _Screen.values) {
      final ltr = <String, Rect>{};
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        final f = _Fixture(screen);
        await f.pump(tester, direction: direction, headerOnly: true);
        final labels = f.values
            .map((value) => _caption(tester, value))
            .toList();
        final traversal = tester.semantics.simulatedAccessibilityTraversal();
        expect(
          traversal
              .map((node) => node.getSemanticsData().label)
              .where(labels.contains),
          labels,
        );
        for (final value in f.values) {
          final target = tester.getRect(_button(value));
          if (direction == TextDirection.ltr) {
            ltr[value] = target;
          } else {
            final original = ltr[value]!;
            expect(target.left, closeTo(411 - original.right, .01));
            expect(target.right, closeTo(411 - original.left, .01));
            expect(target.top, original.top);
            expect(target.bottom, original.bottom);
          }
        }
        final first = tester.getRect(_button(''));
        final next = tester.getRect(_button(f.values[1]));
        final band = tester.getRect(_row);
        final rtl = direction == TextDirection.rtl;
        expect(rtl ? band.right - first.right : first.left - band.left, 12);
        expect(rtl ? first.left - next.right : next.left - first.right, 6);
        expect(
          tester.getRect(_button(f.values.last)).top,
          greaterThan(first.top),
        );
      }
    }
  });

  for (final screen in _Screen.values) {
    for (final scale in _scales) {
      testWidgets('${screen.name} wraps and measures its chips at ${scale}x', (
        tester,
      ) async {
        prepare(tester);
        final f = _Fixture(screen);
        await f.pump(tester, scaler: TextScaler.linear(scale));
        final children = find.descendant(
          of: _row,
          matching: find.byType(Scrollable),
        );
        expect(children, findsNothing);
        final sliver = tester.renderObject<RenderSliver>(_header);
        final delegate = tester
            .widget<SliverPersistentHeader>(_header)
            .delegate;
        final minimum = delegate.minExtent;
        final maximum = delegate.maxExtent;
        final travel = maximum - minimum;
        final rowHeight = tester.getSize(_row).height;
        expect(rowHeight, greaterThan(48));
        expect(
          tester.getRect(_button(f.values.last)).top,
          greaterThan(tester.getRect(_button('')).top),
        );

        for (final offset in [0.0, travel / 2, travel, travel + 24]) {
          f.vertical.jumpTo(offset);
          await tester.pumpAndSettle();
          final current = tester
              .widget<SliverPersistentHeader>(_header)
              .delegate;
          expect(current.minExtent, minimum);
          expect(current.maxExtent, maximum);
          expect(sliver.geometry!.scrollExtent, maximum);
          expect(sliver.geometry!.maxPaintExtent, maximum);
          expect(
            sliver.geometry!.paintExtent,
            closeTo(maximum - offset.clamp(0, travel), .01),
          );
          expect(
            f.vertical.position.viewportDimension -
                sliver.geometry!.paintExtent,
            greaterThanOrEqualTo(48),
          );
          expect(tester.getSize(_row).height, rowHeight);
          final bounds = tester.getRect(_row);
          for (final value in f.values) {
            final target = tester.getRect(_button(value));
            expect(target.height, greaterThanOrEqualTo(48));
            expect(target.width, greaterThanOrEqualTo(48));
            expect(target.left, greaterThanOrEqualTo(bounds.left));
            expect(target.right, lessThanOrEqualTo(bounds.right));
            expect(target.top, greaterThanOrEqualTo(bounds.top));
            expect(target.bottom, lessThanOrEqualTo(bounds.bottom));
            final caption = _captionWidget(tester, value);
            expect(caption, findsOneWidget);
            final widget = tester.widget<Text>(caption);
            expect(
              widget.data,
              '${value.isEmpty ? 'All' : value} (${f.counts[value]})',
            );
            expect(widget.maxLines, isNull);
            expect(widget.softWrap, isTrue);
            final paragraph = _paragraph(tester, value);
            expect(paragraph.textScaler.scale(14), closeTo(14 * scale, .01));
            final captionBounds = tester.getRect(caption);
            expect(captionBounds.left, greaterThanOrEqualTo(target.left));
            expect(captionBounds.right, lessThanOrEqualTo(target.right));
            expect(captionBounds.top, greaterThanOrEqualTo(target.top));
            expect(captionBounds.bottom, lessThanOrEqualTo(target.bottom));
          }
          expect(tester.takeException(), isNull);
        }
        f.vertical.jumpTo(0);
        await tester.pumpAndSettle();
        final value = f.values.last;
        final target = tester.getRect(_button(value));
        await tester.tapAt(target.bottomRight - const Offset(1, 1));
        await tester.pumpAndSettle();
        expect(f.selection, value);
        expect(find.text(f.resultText), findsOneWidget);
      });
    }
  }

  testWidgets(
    '411 × 914 dp pricing fixtures measure the resting header at 1.0x',
    (tester) async {
      prepare(tester);
      for (final screen in _Screen.values) {
        final f = _Fixture(screen);
        await f.pump(
          tester,
          height: 914,
          names: const ['Standard Buying', 'Standard Selling'],
        );
        f.counts.addAll(
          f.item
              ? {'': 319, 'Standard Buying': 0, 'Standard Selling': 319}
              : {'': 3, 'Active': 3},
        );
        await tester.pumpAndSettle();
        final delegate = tester
            .widget<SliverPersistentHeader>(_header)
            .delegate;
        final sliver = tester.renderObject<RenderSliver>(_header);
        expect(delegate.maxExtent, f.item ? 304 : 356);
        expect(delegate.minExtent, f.item ? 208 : 260);
        expect(sliver.geometry!.paintExtent, delegate.maxExtent);
        expect(
          tester.getRect(_button(f.values.last)).bottom,
          lessThan(delegate.maxExtent),
        );
        expect(
          tester.getTopLeft(find.text(f.resultText)).dy,
          greaterThan(delegate.maxExtent),
        );
        f.vertical.jumpTo(delegate.maxExtent - delegate.minExtent);
        await tester.pumpAndSettle();
        expect(sliver.geometry!.paintExtent, delegate.minExtent);
      }
    },
  );

  testWidgets(
    'a long price-list name wraps in full and retains focus after counting',
    (tester) async {
      prepare(tester);
      final f = _Fixture(_Screen.itemPrice);
      await f.pump(
        tester,
        width: 320,
        names: [..._lists, _wideList],
        scaler: const _NonlinearScaler(),
        bold: true,
        headerOnly: true,
      );
      final target = tester.getRect(_button(_wideList));
      expect(target.width, lessThanOrEqualTo(320));
      expect(target.height, greaterThan(tester.getSize(_button('')).height));
      expect(
        _node(tester, _caption(tester, _wideList)).label,
        '$_wideList (0)',
      );
      final focus = _chipFocus(tester, _wideList);
      focus.requestFocus();
      await tester.pumpAndSettle();
      f.counts[_wideList] = 8;
      await tester.pumpAndSettle();
      expect(_chipFocus(tester, _wideList), same(focus));
      expect(focus.hasPrimaryFocus, isTrue);
      const caption = '$_wideList (8)';
      expect(_node(tester, caption).label, caption);
      final paragraph = _paragraph(tester, _wideList);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: caption.length),
      );
      expect(boxes.length, greaterThan(1));
      final updatedTarget = tester.getRect(_button(_wideList));
      for (final box in boxes) {
        final bounds = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
        expect(bounds.left, greaterThanOrEqualTo(updatedTarget.left));
        expect(bounds.right, lessThanOrEqualTo(updatedTarget.right));
        expect(bounds.top, greaterThanOrEqualTo(updatedTarget.top));
        expect(bounds.bottom, lessThanOrEqualTo(updatedTarget.bottom));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pricing and legacy bottoms use their intended text scale', (
    tester,
  ) async {
    prepare(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final screen in _Screen.values) {
      final preset = _Fixture(screen);
      await preset.pump(tester, appPreset: true, headerOnly: true);
      final line = _paragraph(tester, '');
      expect(line.textScaler.scale(14), closeTo(14 * 2 * 1.12, .01));
      expect(
        tester.getSize(_button('')).height,
        greaterThanOrEqualTo(line.size.height),
      );
    }

    const legacy = ValueKey('legacy bottom');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.12)),
          child: child!,
        ),
        home: const Scaffold(
          body: CustomScrollView(
            slivers: [
              DocTypeListHeader(
                title: 'Legacy',
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(52),
                  child: Text('Legacy bottom', key: legacy),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 1600)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.byKey(legacy))).scale(14),
      closeTo(14 * 1.12, .01),
    );
  });

  testWidgets('Item Price keeps wrapped chips clear of Create', (tester) async {
    prepare(tester);
    final f = _Fixture(_Screen.itemPrice);
    final names = [for (var i = 1; i <= 24; i++) 'Retail Zone $i'];
    await f.pump(tester, height: 590, names: names, canCreate: true);
    f.counts.assignAll({'': 319, for (final name in names) name: 10});
    await tester.pumpAndSettle();

    const target = 'Retail Zone 15';
    final choice = _button(target);
    final innerScroll = find.descendant(
      of: find.byType(DocTypeListHeader),
      matching: find.byType(Scrollable),
    );
    if (innerScroll.evaluate().isNotEmpty) {
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
    }
    expect(choice.hitTestable(), findsOneWidget);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(f.selection, target);
    expect(find.text('Item Price form fixture'), findsNothing);

    f.vertical.jumpTo(0);
    await tester.pumpAndSettle();
    final messenger = ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    );
    messenger.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.fixed,
        content: SizedBox(height: 140, child: Text('SnackBar fixture')),
      ),
    );
    await tester.pumpAndSettle();
    final fab = find.byType(FloatingActionButton);
    final headerKey = tester
        .widget<DocTypeListHeader>(find.byType(DocTypeListHeader))
        .sliverKey!;
    final scaffold = tester.renderObject(find.byType(Scaffold));
    expect(
      DocTypeListHeader.extentInViewport(headerKey, scaffold),
      greaterThan(tester.getRect(fab).top),
    );
    final create = fab.hitTestable();
    expect(create, findsNothing);
    expect(
      tester.semantics.simulatedAccessibilityTraversal().where(
        (node) => node.label == 'New price' || node.tooltip == 'New price',
      ),
      isEmpty,
    );

    messenger.removeCurrentSnackBar();
    f.vertical.jumpTo(f.vertical.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(create, findsOneWidget);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text('Item Price form fixture'), findsOneWidget);
  });

  for (final retainResults in [true, false]) {
    testWidgets('short Item Price shows one fixed progress indicator '
        'with ${retainResults ? 'retained' : 'empty'} results', (tester) async {
      prepare(tester);
      final f = _Fixture(_Screen.itemPrice);
      final names = [for (var i = 1; i <= 24; i++) 'Retail Zone $i'];
      await f.pump(tester, height: 320, names: names);
      if (!retainResults) f.prices!.prices.clear();
      await tester.pumpAndSettle();
      final request = f.requests.pending = Completer<Response>();
      await tester.tap(_button(names.first));
      await tester.pump();
      expect(f.selection, names.first);
      final progress = find.byType(LinearProgressIndicator);
      expect(progress, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final bounds = tester.getRect(progress);
      expect(bounds.height, greaterThan(0));
      expect(bounds.top, 0);
      expect(bounds.bottom, lessThanOrEqualTo(320));
      final announcements = tester.semantics
          .simulatedAccessibilityTraversal()
          .where((node) => node.label == 'Updating prices');
      expect(announcements, hasLength(1));
      expect(
        announcements.single.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue,
      );
      expect(
        tester
            .hitTestOnBinding(bounds.center)
            .path
            .map((entry) => entry.target),
        isNot(contains(tester.renderObject(progress))),
      );

      final scroll = f.vertical.position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(progress), bounds);
      f.requests.pending = null;
      request.complete(f.requests.result);
      await tester.pumpAndSettle();
      expect(progress, findsNothing);
    });
  }

  testWidgets(
    'a pending facet reload is visible and guarded with populated results',
    (tester) async {
      prepare(tester);
      for (final screen in _Screen.values) {
        final f = _Fixture(screen);
        await f.pump(tester);
        final value = f.values[1];
        final other = f.values[2];
        const tab = LogicalKeyboardKey.tab;
        final calls = f.requests.calls;
        _chipFocus(tester, value).requestFocus();
        await tester.pumpAndSettle();
        final request = f.requests.pending = Completer<Response>();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.tap(
          _button(other),
        ); // The second pointer input precedes repaint.
        await tester.pump();
        expect(f.requests.calls, calls + 1);
        expect(f.selection, value);
        expect(find.text(f.resultText), findsOneWidget);
        expect(_node(tester, f.updateLabel), isNotNull);
        final disabled = _node(
          tester,
          _caption(tester, value),
        ).getSemanticsData();
        expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
        expect(disabled.flagsCollection.isSelected, Tristate.isTrue);
        expect(disabled.hasAction(SemanticsAction.tap), isFalse);
        f.counts[value] = 4;
        await tester.pump();
        expect(_caption(tester, value), '$value (4)');
        expect(_node(tester, '$value (4)'), isNotNull);
        f.requests.pending = null;
        request.complete(f.requests.result);
        await tester.pumpAndSettle();
        expect(_chipFocus(tester, value).hasPrimaryFocus, isTrue);
        expect(find.bySemanticsLabel(f.updateLabel), findsNothing);

        _chipFocus(tester, other).requestFocus();
        await tester.pumpAndSettle();
        final failure = f.requests.pending = Completer<Response>();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.sendKeyEvent(tab);
        await tester.pump();
        final elsewhere = FocusManager.instance.primaryFocus;
        expect(elsewhere?.debugLabel, isNot('Header choices loading'));
        f.requests.pending = null;
        failure.completeError(StateError('facet request failed'));
        await tester.pumpAndSettle();
        expect(f.selection, other);
        expect(f.requests.calls, calls + 2);
        expect(FocusManager.instance.primaryFocus, same(elsewhere));
        expect(
          _node(
            tester,
            _caption(tester, other),
          ).getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(find.text(f.resultText), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
