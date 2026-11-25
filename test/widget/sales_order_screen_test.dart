import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/header_choice_row.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_screen.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/main.dart' show buildAppTheme;

class _SalesOrders extends SalesOrderProvider {
  final requests = <Map<String, dynamic>?>[];
  Completer<Response>? pending;

  @override
  Future<Response> getSalesOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
    String orderBy = 'modified desc',
  }) {
    requests.add(filters);
    return pending?.future ?? Future.value(results());
  }

  Response results() => Response(
    requestOptions: RequestOptions(),
    statusCode: 200,
    data: {
      'data': [
        for (var i = 0; i < 14; i++)
          {
            'name': 'ORDER-$i',
            'customer_name': 'Example Customer',
            'status': 'Completed',
            'transaction_date': '2026-11-23',
          },
      ],
    },
  );
}

class _CreatePermission extends PermissionService {
  final allowCreate = false.obs;

  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) =>
      permType != 'create' || allowCreate.value;
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize < 20 ? 2 : 1.75);

  @override
  double get textScaleFactor => 2;
}

const _scopes = ['Mine', 'Everyone'];
const _choices = [..._scopes, ...SalesOrderController.statusChips];
const _font = 'Sales Order test Inter';

String _name(String caption) =>
    'Order ${_scopes.contains(caption) ? 'scope' : 'status'}, $caption';

Finder _choice(String caption) => find.byWidgetPredicate(
  (widget) => widget is HeaderChoiceButton && widget.option.label == caption,
);

Finder _native(String caption) =>
    find.descendant(of: _choice(caption), matching: find.byType(TextButton));

Finder _bar() => find.byType(HeaderChoiceRow);

ScrollPosition _vertical(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byType(CustomScrollView))
    .controller!
    .position;

RenderSliverPersistentHeader _sliver(WidgetTester tester) =>
    tester.renderObject(find.byType(SliverPersistentHeader));

SemanticsNode _node(WidgetTester tester, String label) => tester.semantics
    .simulatedAccessibilityTraversal()
    .singleWhere((node) => node.label == label);

void _action(SemanticsNode node, SemanticsAction action) =>
    node.owner!.performAction(node.id, action);

Rect _semanticRect(SemanticsNode node) {
  final transform = Matrix4.identity();
  for (
    SemanticsNode? ancestor = node;
    ancestor != null;
    ancestor = ancestor.parent
  ) {
    if (ancestor.transform case final matrix?) transform.leftMultiply(matrix);
  }
  return MatrixUtils.transformRect(transform, node.rect);
}

void _expectContained(Rect target, Rect viewport, {required String caption}) {
  expect(viewport.left, lessThanOrEqualTo(target.left + .01), reason: caption);
  expect(viewport.top, lessThanOrEqualTo(target.top + .01), reason: caption);
  expect(
    viewport.right,
    greaterThanOrEqualTo(target.right - .01),
    reason: caption,
  );
  expect(
    viewport.bottom,
    greaterThanOrEqualTo(target.bottom - .01),
    reason: caption,
  );
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  late _SalesOrders provider;
  late SalesOrderController controller;
  late _CreatePermission permission;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => r'C:\temp\test_cookies',
        );
    final font = FontLoader(_font);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('lib/assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  setUp(() {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(AuthenticationController());
    permission = _CreatePermission();
    Get.put<PermissionService>(permission);
    provider = Get.put<SalesOrderProvider>(_SalesOrders()) as _SalesOrders;
    Get.put(UserProvider());
  });
  tearDown(Get.reset);

  Future<void> pump(
    WidgetTester tester, {
    TextScaler scaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
    double width = 411,
    double height = 850,
    double ratio = 1,
    bool bold = false,
    Widget? fixture,
  }) async {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(width * ratio, height * ratio);
    addTearDown(tester.view.reset);
    if (!Get.isRegistered<SalesOrderController>()) {
      controller = Get.put(SalesOrderController());
    }
    final app = buildAppTheme(AppScheme.light, Brightness.light);
    await tester.pumpWidget(
      GetMaterialApp(
        getPages: [
          GetPage(
            name: AppRoutes.SALES_ORDER_FORM,
            page: () => const Scaffold(body: Text('Sales Order form fixture')),
          ),
        ],
        theme: app.copyWith(
          platform: TargetPlatform.android,
          textTheme: app.textTheme.apply(fontFamily: _font),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: scaler, boldText: bold)
              .applyTextStyleOverrides(
                lineHeightScaleFactorOverride: null,
                letterSpacingOverride: bold ? 1.5 : null,
                wordSpacingOverride: bold ? 2 : null,
                paragraphSpacingOverride: null,
              ),
          child: Directionality(textDirection: direction, child: child!),
        ),
        home: fixture ?? const SalesOrderScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('short Sales Order keeps wrapped chips clear of Create', (
    tester,
  ) async {
    permission.allowCreate.value = true;
    await pump(tester, height: 320);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    final completed = _native('Completed');
    final innerScroll = find.descendant(
      of: find.byType(DocTypeListHeader),
      matching: find.byType(Scrollable),
    );
    if (innerScroll.evaluate().isNotEmpty) {
      await tester.ensureVisible(completed);
      await tester.pumpAndSettle();
    }
    expect(completed.hitTestable(), findsOneWidget);
    await tester.tap(completed);
    await tester.pumpAndSettle();
    expect(controller.activeFilters['status'], 'Completed');
    expect(find.text('Sales Order form fixture'), findsNothing);

    final scroll = _vertical(tester);
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    final create = find.byType(FloatingActionButton).hitTestable();
    expect(create, findsOneWidget);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text('Sales Order form fixture'), findsOneWidget);
  });

  testWidgets('every Sales Order choice accepts taps at all four edges', (
    tester,
  ) async {
    const ratio = 2.625;
    await pump(tester, width: 1080 / ratio, height: 2400 / ratio, ratio: ratio);
    for (final collapsed in [false, true]) {
      for (final caption in _choices) {
        for (final edge in [
          Alignment.topCenter,
          Alignment.bottomCenter,
          Alignment.centerLeft,
          Alignment.centerRight,
        ]) {
          final scope = _scopes.contains(caption);
          if (scope) {
            controller.setScope(
              caption == 'Mine'
                  ? ActionableScope.everyone
                  : ActionableScope.mine,
            );
          } else if (controller.activeFilters['status'] == caption) {
            controller.setStatusChip(caption);
          }
          await tester.pumpAndSettle();
          final header = _sliver(tester);
          _vertical(
            tester,
          ).jumpTo(collapsed ? header.maxExtent - header.minExtent : 0);
          await tester.pumpAndSettle();
          final rect = tester.getRect(_native(caption));
          final physical = _semanticRect(_node(tester, _name(caption)));
          final semantic = Rect.fromLTRB(
            physical.left / ratio,
            physical.top / ratio,
            physical.right / ratio,
            physical.bottom / ratio,
          );
          expect(rect.width * ratio, greaterThanOrEqualTo(126));
          expect(rect.height * ratio, greaterThanOrEqualTo(126));
          _expectContained(rect, tester.getRect(_bar()), caption: caption);
          for (final (paint, spoken) in [
            (rect.left, semantic.left),
            (rect.right, semantic.right),
            (rect.top, semantic.top),
            (rect.bottom, semantic.bottom),
          ]) {
            expect(spoken, closeTo(paint, 1 / ratio), reason: caption);
          }
          for (final other in _choices.where((other) => other != caption)) {
            expect(rect.overlaps(tester.getRect(_native(other))), isFalse);
          }
          final count = provider.requests.length;
          await tester.tapAt(edge.withinRect(rect.inflate(1)));
          await tester.pumpAndSettle();
          expect(provider.requests, hasLength(count), reason: '$caption $edge');
          await tester.tapAt(edge.withinRect(rect.deflate(1)));
          await tester.pumpAndSettle();
          expect(
            provider.requests,
            hasLength(count + 1),
            reason: '$caption $edge',
          );
          if (scope) {
            expect(controller.scope.value.name, caption.toLowerCase());
          } else {
            expect(controller.activeFilters['status'], caption);
          }
        }
      }
    }
    final selected = tester.getRect(_native('Cancelled'));
    await tester.tapAt(Offset(selected.center.dx, selected.bottom - 1));
    await tester.pumpAndSettle();
    expect(controller.activeFilters.containsKey('status'), isFalse);

    final mine = tester.getRect(_native('Mine'));
    final everyone = tester.getRect(_native('Everyone'));
    final count = provider.requests.length;
    await tester.tapAt(
      Offset((mine.right + everyone.left) / 2, mine.center.dy),
    );
    await tester.pumpAndSettle();
    expect(provider.requests, hasLength(count));
  });

  testWidgets(
    'scope is exclusive and status is exclusive with an empty selection',
    (tester) async {
      await pump(tester);
      controller.applyFilters({
        'customer': 'ACME',
        'owner': 'other@example.test',
        'status': [
          'in',
          ['Draft', 'On Hold'],
        ],
      });
      await tester.pumpAndSettle();

      void verify(String caption, bool selected) {
        final data = _node(tester, _name(caption)).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isEnabled, Tristate.isTrue);
        expect(data.flagsCollection.isFocused, isNot(Tristate.none));
        expect(
          data.flagsCollection.isSelected,
          selected ? Tristate.isTrue : Tristate.isFalse,
        );
        expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
      }

      for (final caption in _choices) {
        verify(caption, caption == 'Everyone');
      }
      expect(find.text('Status: Draft, On Hold'), findsOneWidget);
      verify('Mine', false);
      final count = provider.requests.length;
      _action(_node(tester, _name('Mine')), SemanticsAction.tap);
      await tester.pumpAndSettle();
      verify('Mine', true);
      verify('Everyone', false);
      _action(_node(tester, _name('Mine')), SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(provider.requests, hasLength(count + 1));

      for (final caption in ['Draft', 'To Deliver and Bill']) {
        _action(_node(tester, _name(caption)), SemanticsAction.tap);
        await tester.pumpAndSettle();
        verify(caption, true);
        expect(_node(tester, 'Edit Status: $caption'), isNotNull);
        expect(_node(tester, 'Reset Status: $caption'), isNotNull);
      }
      verify('Draft', false);
      verify('To Deliver and Bill', true);
      _action(_node(tester, _name('To Deliver and Bill')), SemanticsAction.tap);
      await tester.pumpAndSettle();
      for (final caption in SalesOrderController.statusChips) {
        verify(caption, false);
      }
      expect(controller.activeFilters, {
        'customer': 'ACME',
        'owner': 'other@example.test',
      });
      expect(provider.requests.last, {
        'customer': 'ACME',
        'owner': 'other@example.test',
      });
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'Tab and semantics follow the choice order across lines and keys activate once [$direction]',
      (tester) async {
        await pump(tester, direction: direction);
        final manager = FocusManager.instance;
        final previous = manager.highlightStrategy;
        manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() => manager.highlightStrategy = previous);
        if (direction == TextDirection.rtl) {
          _vertical(
            tester,
          ).jumpTo((_sliver(tester).maxExtent - _sliver(tester).minExtent) / 2);
          await tester.pumpAndSettle();
        }
        final search = find.descendant(
          of: find.byTooltip('Search Sales Order'),
          matching: find.byIcon(Icons.search),
        );
        Focus.of(tester.element(search)).requestFocus();
        await tester.pumpAndSettle();
        final count = provider.requests.length;
        final viewport = tester.getRect(_bar());
        final names = _choices.map(_name).toList();
        final choiceNodes = tester.semantics
            .simulatedAccessibilityTraversal()
            .where((node) => names.contains(node.label))
            .toList();
        expect(choiceNodes.map((node) => node.label), names);
        for (final (index, node) in choiceNodes.indexed) {
          expect(
            node.sortKey ?? node.parent?.sortKey,
            isA<OrdinalSortKey>().having((key) => key.order, 'order', index),
          );
        }
        for (final caption in _choices) {
          await _key(tester, LogicalKeyboardKey.tab);
          expect(
            tester
                .widget<TextButton>(_native(caption))
                .focusNode!
                .hasPrimaryFocus,
            isTrue,
            reason: '$caption, focus tree ${debugDescribeFocusTree()}',
          );
          final node = _node(tester, _name(caption));
          expect(
            node.getSemanticsData().flagsCollection.isFocused,
            Tristate.isTrue,
          );
          _expectContained(
            tester.getRect(_native(caption)),
            viewport,
            caption: caption,
          );
          final contour = find.descendant(
            of: _choice(caption),
            matching: find.byType(HeaderActionContour),
          );
          expect(
            headerContourWidth(
              tester.widget<HeaderActionContour>(contour).states,
            ),
            2,
          );
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
        for (final caption in _choices.reversed) {
          await _key(tester, LogicalKeyboardKey.tab);
          expect(
            tester
                .widget<TextButton>(_native(caption))
                .focusNode!
                .hasPrimaryFocus,
            isTrue,
            reason: caption,
          );
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          tester
              .widget<TextButton>(_native('To Deliver and Bill'))
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
        await _key(tester, LogicalKeyboardKey.arrowUp);
        expect(
          tester.widget<TextButton>(_native('Mine')).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        expect(provider.requests, hasLength(count));
        await _key(tester, LogicalKeyboardKey.enter);
        expect(controller.scope.value, ActionableScope.mine);
        expect(provider.requests, hasLength(count + 1));
        tester
            .widget<TextButton>(_native('Cancelled'))
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await _key(tester, LogicalKeyboardKey.enter);
        expect(controller.activeFilters['status'], 'Cancelled');
        await _key(tester, LogicalKeyboardKey.space);
        expect(controller.activeFilters.containsKey('status'), isFalse);
        expect(provider.requests, hasLength(count + 3));
      },
    );
  }

  testWidgets(
    'Sales Order uses one effective scaler for measurement and paint',
    (tester) async {
      final theme = Get.put(
        ThemeController(persist: (_, _) async {}, restore: (_) async => null),
      );
      await theme.setTextSize(AppTextSize.large);
      final preset = AppTextSize.large.factor;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, scaler: TextScaler.linear(preset));
      final heading = tester.renderObject<RenderParagraph>(
        find.text('Sales Order').last,
      );
      expect(heading.textScaler.scale(12), closeTo(24 * preset, .01));
      for (final caption in _choices) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: _choice(caption), matching: find.text(caption)),
        );
        expect(paragraph.textScaler.scale(14), closeTo(28 * preset, .01));
      }
      await pump(
        tester,
        scaler: TextScaler.linear(preset),
        fixture: const Scaffold(
          body: CustomScrollView(
            slivers: [
              DocTypeListHeader(
                title: 'Legacy',
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(48),
                  child: Text('Legacy bottom'),
                ),
              ),
            ],
          ),
        ),
      );
      final legacy = tester.renderObject<RenderParagraph>(
        find.text('Legacy bottom'),
      );
      expect(legacy.textScaler.scale(14), closeTo(14 * preset, .01));
      Get.delete<ThemeController>();
      await pump(tester, scaler: const _NonlinearScaler());
      final caption = tester.renderObject<RenderParagraph>(
        find.text('Everyone'),
      );
      expect(caption.textScaler.scale(12), 24);
      expect(caption.textScaler.scale(24), 42);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      '411 dp choices wrap with complete captions and matching extents [$direction]',
      (tester) async {
        var lastHeight = 0.0;
        for (final (scale, bold) in [
          (.85, false),
          (1.0, false),
          (1.3, false),
          (2.0, false),
          (2.0, true),
        ]) {
          await pump(
            tester,
            direction: direction,
            scaler: TextScaler.linear(scale),
            bold: bold,
            height: 914,
          );
          controller.setScope(ActionableScope.mine);
          await tester.pumpAndSettle();
          final header = _sliver(tester);
          final row = tester.widget<HeaderChoiceRow>(_bar());
          final height = tester.getSize(_bar()).height;
          expect(height, row.heightFor(tester.element(_bar()), 411));
          expect(height, greaterThanOrEqualTo(lastHeight));
          expect(
            find.descendant(of: _bar(), matching: find.byType(Scrollable)),
            findsNothing,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
            ),
            findsNothing,
          );
          if (scale == 1) {
            expect(
              (header.maxExtent, header.minExtent),
              (408.0, 312.0),
              reason: '411 × 914 dp at 1.0× with Mine selected and no status',
            );
          }
          lastHeight = height;

          final mine = tester.getRect(_native('Mine'));
          final everyone = tester.getRect(_native('Everyone'));
          expect(mine.center.dy, everyone.center.dy);
          expect(
            direction == TextDirection.ltr ? mine.right : -mine.left,
            lessThan(
              direction == TextDirection.ltr ? everyone.left : -everyone.right,
            ),
          );
          expect(
            tester.getRect(_native('Cancelled')).top,
            greaterThan(mine.bottom),
          );

          final collapse = header.maxExtent - header.minExtent;
          for (final offset in [0.0, collapse / 2, collapse, collapse + 30]) {
            _vertical(tester).jumpTo(offset);
            await tester.pumpAndSettle();
            final extent = header.maxExtent - offset.clamp(0.0, collapse);
            expect(header.child!.size.height, closeTo(extent, .01));
            expect(
              header.geometry!.maxPaintExtent,
              closeTo(header.maxExtent, .01),
            );
            expect(
              header.geometry!.maxScrollObstructionExtent,
              closeTo(header.minExtent, .01),
            );

            final bar = tester.getRect(_bar());
            final results = tester.getRect(
              find.byType(GenericDocumentCard).first,
            );
            final viewport = tester.getRect(find.byType(CustomScrollView));
            expect(results.bottom, greaterThan(bar.bottom));
            expect(results.top, lessThan(viewport.bottom));
            for (final label in _choices) {
              final target = tester.getRect(_native(label));
              _expectContained(target, bar, caption: label);
              expect(target.width, greaterThanOrEqualTo(48));
              expect(target.height, greaterThanOrEqualTo(48));
              final caption = find.descendant(
                of: _choice(label),
                matching: find.text(label),
              );
              final paragraph = tester.renderObject<RenderParagraph>(caption);
              final laidOut = paragraph.getDryLayout(
                BoxConstraints.tightFor(width: paragraph.size.width),
              );
              expect(
                paragraph.size.height,
                greaterThanOrEqualTo(laidOut.height),
              );
              expect(paragraph.didExceedMaxLines, isFalse);
              _expectContained(tester.getRect(caption), target, caption: label);
            }
            expect(tester.takeException(), isNull);
          }
          final target = tester.getRect(_native('To Deliver'));
          final requests = provider.requests.length;
          await tester.drag(_bar(), const Offset(-320, 0));
          await tester.pumpAndSettle();
          expect(tester.getRect(_native('To Deliver')), target);
          expect(provider.requests, hasLength(requests));
        }
      },
    );
  }

  testWidgets(
    'Sales Order captions stay centered without reflow when selected',
    (tester) async {
      await pump(tester, scaler: const TextScaler.linear(2));
      for (final (label, select) in <(String, VoidCallback)>[
        ('Mine', () => controller.setScope(ActionableScope.mine)),
        ('To Deliver', () => controller.setStatusChip('To Deliver')),
      ]) {
        final choice = _choice(label);
        final caption = find.descendant(of: choice, matching: find.text(label));
        final check = find.descendant(
          of: choice,
          matching: find.byIcon(Icons.check),
        );
        final target = tester.getRect(_native(label));
        expect(tester.getCenter(caption).dx, closeTo(target.center.dx, .01));
        expect(check, findsNothing);

        select();
        await tester.pumpAndSettle();
        expect(tester.getRect(_native(label)), target);
        expect(tester.getCenter(caption).dx, closeTo(target.center.dx, .01));
        expect(check, findsOneWidget);
        expect(
          tester.getRect(check).overlaps(tester.getRect(caption)),
          isFalse,
        );
      }
    },
  );

  testWidgets(
    'expanded Sales Order header leaves the count and first result visible',
    (tester) async {
      await pump(tester, height: 400);

      expect(_vertical(tester).pixels, 0);
      final viewport = tester.getRect(find.byType(CustomScrollView));
      expect(find.text('14 orders').hitTestable(), findsOneWidget);
      final cards = find.byType(GenericDocumentCard);
      expect(cards, findsWidgets);
      final firstResult = tester.getRect(cards.first);
      expect(viewport.bottom - firstResult.top, greaterThanOrEqualTo(24));

      await tester.dragFrom(
        viewport.bottomCenter.translate(0, -10),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      expect(_vertical(tester).pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sales Order preserves focus on reflow and can scroll away in a short viewport',
    (tester) async {
      await pump(tester);
      final tail = tester.widget<TextButton>(_native('Cancelled')).focusNode!;
      tail.requestFocus();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 850);
      await tester.pumpAndSettle();
      expect(tail.hasPrimaryFocus, isTrue);
      _expectContained(
        tester.getRect(_native('Cancelled')),
        tester.getRect(_bar()),
        caption: 'Cancelled',
      );

      await pump(tester, scaler: const TextScaler.linear(2), height: 320);
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final salesHeader = find.byType(SliverPersistentHeader);
      expect(
        tester.widget<SliverPersistentHeader>(salesHeader).pinned,
        isFalse,
      );
      expect(find.text('14 orders').hitTestable(), findsOneWidget);
      expect(
        viewport.bottom -
            tester.getTopLeft(find.byType(GenericDocumentCard).first).dy,
        greaterThanOrEqualTo(24),
      );
      tester.widget<TextButton>(_native('Mine')).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      _vertical(tester).jumpTo(0);
      await tester.pumpAndSettle();
      final cancelled = _native('Cancelled');
      expect(tester.getRect(cancelled).bottom, greaterThan(viewport.bottom));

      final shortTail = tester.widget<TextButton>(cancelled).focusNode!;
      shortTail.requestFocus();
      await tester.pumpAndSettle();
      expect(shortTail.hasPrimaryFocus, isTrue);
      _expectContained(
        tester.getRect(cancelled),
        viewport,
        caption: 'Cancelled',
      );

      _vertical(tester).jumpTo(_sliver(tester).maxExtent);
      await tester.pumpAndSettle();
      final result = tester.getRect(find.byType(GenericDocumentCard).first);
      expect(viewport.overlaps(result), isTrue);

      const long =
          'A translated choice with a much longer caption on this small screen';
      await pump(
        tester,
        width: 110,
        height: 195,
        fixture: Scaffold(
          body: CustomScrollView(
            slivers: [
              DocTypeListHeader(
                title: 'Sales Order',
                bottom: HeaderChoiceRow(
                  options: [
                    HeaderChoiceOption(
                      id: 'translation',
                      groupId: 'status',
                      label: long,
                      semanticLabel: long,
                      selected: true,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 300, child: Text('Result')),
              ),
            ],
          ),
        ),
      );
      final caption = tester.renderObject<RenderParagraph>(find.text(long));
      expect(caption.size.height, greaterThan(40));
      expect(caption.didExceedMaxLines, isFalse);
      final header = find.byType(SliverPersistentHeader);
      expect(tester.widget<SliverPersistentHeader>(header).pinned, isFalse);
      final resultScroll = Scrollable.of(
        tester.element(find.text('Result')),
        axis: Axis.vertical,
      );
      resultScroll.position.jumpTo(
        tester.renderObject<RenderSliverPersistentHeader>(header).maxExtent,
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Result')).dy, closeTo(0, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'busy choices repaint immediately and return focus only when it stays in the bar',
    (tester) async {
      await pump(tester);
      final mine = tester.widget<TextButton>(_native('Mine')).focusNode!;
      mine.requestFocus();
      await tester.pumpAndSettle();
      final first = provider.pending = Completer<Response>();
      final count = provider.requests.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      controller.setStatusChip('Draft');
      await tester.pump();
      expect(provider.requests, hasLength(count + 1));
      expect(find.text('ORDER-0'), findsOneWidget);
      final loading = _node(tester, 'Loading sales orders').getSemanticsData();
      expect(loading.flagsCollection.isLiveRegion, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final pendingMine = _node(tester, _name('Mine')).getSemanticsData();
      expect(pendingMine.flagsCollection.isSelected, Tristate.isTrue);
      expect(pendingMine.flagsCollection.isEnabled, Tristate.isFalse);
      expect(pendingMine.hasAction(SemanticsAction.tap), isFalse);
      expect(mine.hasPrimaryFocus, isFalse);
      provider.pending = null;
      first.complete(provider.results());
      await tester.pumpAndSettle();
      expect(mine.hasPrimaryFocus, isTrue);

      final everyone = tester
          .widget<TextButton>(_native('Everyone'))
          .focusNode!;
      everyone.requestFocus();
      await tester.pumpAndSettle();
      final second = provider.pending = Completer<Response>();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        _node(
          tester,
          'Add filter',
        ).getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
        reason: debugDescribeFocusTree(),
      );
      provider.pending = null;
      second.complete(provider.results());
      await tester.pumpAndSettle();
      expect(everyone.hasPrimaryFocus, isFalse);
      expect(
        _node(
          tester,
          'Add filter',
        ).getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
      );

      final draft = tester.widget<TextButton>(_native('Draft')).focusNode!;
      draft.requestFocus();
      await tester.pumpAndSettle();
      final failing = provider.pending = Completer<Response>();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      provider.pending = null;
      failing.completeError(StateError('Fixture reload failed'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load Sales Orders'), findsOneWidget);
      expect(controller.isLoading.value, isFalse);
      expect(controller.activeFilters['status'], 'Draft');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      draft.requestFocus();
      await tester.pumpAndSettle();
      final leaving = provider.pending = Completer<Response>();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final destination = FocusNode();
      final navigator = Navigator.of(
        tester.element(find.byType(SalesOrderScreen)),
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: TextButton(
                focusNode: destination,
                autofocus: true,
                onPressed: () {},
                child: const Text('Another route'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(destination.hasPrimaryFocus, isTrue);
      provider.pending = null;
      leaving.complete(provider.results());
      await tester.pumpAndSettle();
      expect(destination.hasPrimaryFocus, isTrue);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(draft.hasPrimaryFocus, isFalse);
      destination.dispose();
    },
  );
}
