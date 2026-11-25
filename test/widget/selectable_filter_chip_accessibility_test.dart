import 'dart:typed_data';
import 'dart:ui' as ui;

// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show FontLoader, LogicalKeyboardKey, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/customer_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_screen.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_form_screen.dart';
import 'package:multimax/app/modules/item/form/item_tab_controller.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_screen.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_screen.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../helpers/auth_fakes.dart';
import '../support/delivery_note_fixture.dart';
import '../unit/theme_contrast_test.dart' show contrast;

const _font = 'Selectable filter chip Inter';

ThemeData _theme({
  Brightness brightness = Brightness.light,
  AppAccent accent = AppAccent.brand,
}) {
  final app = buildAppTheme(
    AppScheme.of(brightness),
    brightness,
    accent: accent,
  );
  return app.copyWith(
    platform: TargetPlatform.android,
    textTheme: app.textTheme.apply(fontFamily: _font),
  );
}

Finder _chip(String caption) => find.byWidgetPredicate(
  (widget) => widget is SelectableFilterChip && widget.caption == caption,
);

Finder _raw(Finder chip) =>
    find.descendant(of: chip, matching: find.byType(RawChip));

SemanticsData _action(WidgetTester tester, String caption) =>
    tester.semantics.simulatedAccessibilityTraversal().singleWhere((node) {
      final data = node.getSemanticsData();
      return data.label == caption && data.flagsCollection.isButton;
    }).getSemanticsData();

void _expectTarget(WidgetTester tester, Finder chip, {bool enabled = true}) {
  final target = _raw(chip);
  final semantics = tester.getSemantics(enabled ? target : chip);
  for (final rect in [tester.getRect(target), semantics.rect]) {
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
  }
  expect(
    semantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
    enabled,
  );
}

void _keepKeyboardHighlight() {
  final manager = FocusManager.instance;
  final previous = manager.highlightStrategy;
  manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => manager.highlightStrategy = previous);
}

class _OfflinePosUpload extends PosUploadController {
  @override
  Future<void> fetchPosUploads({
    bool isLoadMore = false,
    bool clear = false,
  }) async {
    isLoading.value = false;
  }

  @override
  Future<void> fetchCustomers() async {}
}

class _EmptyStorage {
  T? read<T>(String key) => null;
}

DeliveryNote _note() => DeliveryNote.fromJson({
  'name': 'DN-001',
  'docstatus': 1,
  'set_warehouse': 'Main Stores',
  'items': [
    {
      'name': 'DN-ITEM-001',
      'item_code': 'ABC',
      'item_name': 'Test Strap',
      'qty': 2,
      'uom': 'Nos',
      'custom_invoice_serial_number': '1',
    },
  ],
});

class _DeliveryNote extends DeliveryNoteFormController {
  final selections = <String>[];

  // Seed the document without starting the scanner and realtime workers.
  @override
  // ignore: must_call_super
  void onInit() {
    deliveryNote.value = _note();
    setWarehouse.value = 'Main Stores';
    isLoading.value = false;
  }

  @override
  void setFilter(String label) {
    selections.add(label);
    super.setFilter(label);
  }
}

class _PackingSlip extends PackingSlipFormController {
  final selections = <String>[];

  // Seed the document without starting the scanner and realtime workers.
  @override
  // ignore: must_call_super
  void onInit() {
    packingSlip.value = PackingSlip.fromJson({
      'name': 'PS-001',
      'docstatus': 1,
    });
    linkedDeliveryNote.value = _note();
    itemFilter.value = 'All';
    isLoading.value = false;
  }

  @override
  void setFilter(String label) {
    selections.add(label);
    super.setFilter(label);
  }
}

class _ItemForm extends ItemFormController {
  _ItemForm() : super(readArguments: () => null);

  @override
  void onInit() {
    super.onInit();
    itemCode = 'ITEM-1';
    item.value = Item.fromJson({
      'name': itemCode,
      'item_code': itemCode,
      'item_name': itemCode,
    });
    isLoading.value = false;
  }

  @override
  Future<void> fetchDashboardData() async {
    stockLevels.assignAll([
      WarehouseStock(warehouse: 'North - Company A', quantity: 1),
      WarehouseStock(warehouse: 'North - Company B', quantity: 2),
    ]);
  }
}

class _Pixels {
  const _Pixels(this.bytes, this.width);

  final ByteData bytes;
  final int width;

  Color at(Offset point) {
    final x = (point.dx * 2).floor();
    final y = (point.dy * 2).floor();
    final pixel = bytes.getUint32((y * width + x) * 4);
    return Color(((pixel & 0xff) << 24) | (pixel >> 8));
  }

  bool containsInk(Rect rect, Color color) {
    for (var y = rect.top; y < rect.bottom; y += .5) {
      for (var x = rect.left; x < rect.right; x += .5) {
        if (at(Offset(x, y)) == color) return true;
      }
    }
    return false;
  }

  static Future<_Pixels> capture(WidgetTester tester, GlobalKey key) async {
    return (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        return _Pixels(
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
          image.width,
        );
      } finally {
        image.dispose();
      }
    }))!;
  }
}

void main() {
  setUpAll(() async {
    final loader = FontLoader(_font);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('lib/assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
  });

  testWidgets(
    'plain counted and dotted chips share pointer, focus and disabled behaviour',
    (tester) async {
      final plainFocus = FocusNode(debugLabel: 'plain');
      final statusFocus = FocusNode(debugLabel: 'status');
      final disabledFocus = FocusNode(debugLabel: 'disabled');
      addTearDown(plainFocus.dispose);
      addTearDown(statusFocus.dispose);
      addTearDown(disabledFocus.dispose);
      _keepKeyboardHighlight();

      final changes = <bool>[];
      var chosen = false;
      var statusTouches = 0;
      final theme = _theme();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            backgroundColor: const Color(0xFFFFFFFF),
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 220,
                child: StatefulBuilder(
                  builder: (context, setState) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SelectableFilterChip(
                        label: 'A',
                        selected: chosen,
                        focusNode: plainFocus,
                        onSelected: (value) {
                          changes.add(value);
                          setState(() => chosen = value);
                        },
                      ),
                      SelectableFilterChip(
                        label: 'Ready',
                        count: 0,
                        dotColor: theme.colorScheme.primary,
                        selected: true,
                        focusNode: statusFocus,
                        onSelected: (_) => statusTouches++,
                      ),
                      SelectableFilterChip(
                        label: 'North',
                        semanticLabel: 'North - Warehouse 01',
                        selected: false,
                        focusNode: disabledFocus,
                        onSelected: null,
                      ),
                      const SelectableFilterChip(
                        label: 'Closed',
                        dotColor: Colors.orange,
                        selected: true,
                        onSelected: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      for (final (caption, speech, selected, enabled) in [
        ('A', 'A', false, true),
        ('Ready (0)', 'Ready (0)', true, true),
        ('North', 'North - Warehouse 01', false, false),
        ('Closed', 'Closed', true, false),
      ]) {
        _expectTarget(tester, _chip(caption), enabled: enabled);
        final data = _action(tester, speech);
        expect(
          data.flagsCollection.isSelected,
          selected ? ui.Tristate.isTrue : ui.Tristate.isFalse,
        );
        expect(
          data.flagsCollection.isEnabled,
          enabled ? ui.Tristate.isTrue : ui.Tristate.isFalse,
        );
        if (!enabled) expect(data.flagsCollection.isFocused, ui.Tristate.none);
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      final plain = _raw(_chip('A'));
      final start = tester.getRect(plain);
      await tester.tapAt(Offset(start.center.dx, start.top + 1));
      await tester.pumpAndSettle();
      final selected = tester.getRect(plain);
      await tester.tapAt(Offset(selected.center.dx, selected.bottom - 1));
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      for (final isLeading in [true, false]) {
        final rect = tester.getRect(plain);
        await tester.tapAt(
          Offset(isLeading ? rect.left + 1 : rect.right - 1, rect.center.dy),
        );
        await tester.pumpAndSettle();
      }
      expect(changes, [true, false, true, false]);

      final status = tester.getRect(_raw(_chip('Ready (0)')));
      for (final y in [
        status.top + 1,
        status.bottom - 1,
        status.top - 1,
        status.bottom + 1,
      ]) {
        await tester.tapAt(Offset(status.center.dx, y));
        await tester.pumpAndSettle();
      }
      expect(statusTouches, 2);
      for (final caption in ['North', 'Closed']) {
        final rect = tester.getRect(_raw(_chip(caption)));
        await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
        await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
      }

      plainFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(statusFocus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(statusTouches, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(plainFocus.hasPrimaryFocus, isTrue);
      expect(disabledFocus.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('constrained caller rows expose full targets [$scale×]', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.reset);
      addTearDown(Get.reset);
      final theme = _theme();

      Widget fixedScale(BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      );

      Future<void> revealAndTap(String caption) async {
        final horizontal = find.ancestor(
          of: _chip('All'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
          ),
        );
        final viewport = tester.element(horizontal);
        final terminal = _chip(caption);
        await tester.scrollUntilVisible(
          terminal,
          180,
          scrollable: find.byElementPredicate((element) => element == viewport),
        );
        await tester.pumpAndSettle();
        _expectTarget(tester, terminal);
        final rect = tester.getRect(_raw(terminal));
        await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
        await tester.pumpAndSettle();
        expect(
          _action(tester, caption).flagsCollection.isSelected,
          ui.Tristate.isTrue,
        );
        expect(tester.takeException(), isNull);
      }

      final delegate = GlobalDocumentSearchDelegate();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: fixedScale,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showSearch<void>(context: context, delegate: delegate),
                  child: const Text('Search'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        _expectTarget(tester, _chip('All'));
        await revealAndTap(kDiscoverableSearchTargets.last.label);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        delegate.dispose();
      }

      Get.testMode = true;
      Get.put<ApiProvider>(FakeApiProvider());
      Get.put(PosUploadProvider());
      Get.put(CustomerProvider());
      final pos = Get.put<PosUploadController>(_OfflinePosUpload());
      await tester.pumpWidget(
        GetMaterialApp(
          theme: theme,
          builder: fixedScale,
          home: const PosUploadScreen(),
        ),
      );
      await tester.pumpAndSettle();
      _expectTarget(tester, _chip('All'));
      final status = PosUpload.statusOptions.last;
      await revealAndTap(status);
      expect(pos.activeFilters['status'], status);
      await tester.tap(_chip(status));
      await tester.pumpAndSettle();
      expect(pos.activeFilters.containsKey('status'), isFalse);

      Get.put(StorageService.withStorage(_EmptyStorage()));
      final stock = Get.put(StockBalanceController());
      stock.showImages.value = false;
      stock.reportData.assignAll([
        for (var i = 0; i < 12; i++)
          {
            'warehouse': 'WH ${i.toString().padLeft(2, '0')}',
            'item_code': 'Item $i',
            'bal_qty': i,
          },
      ]);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: theme,
          builder: fixedScale,
          home: const StockBalanceScreen(),
        ),
      );
      await tester.pumpAndSettle();
      _expectTarget(tester, _chip('All'));
      await revealAndTap('WH 11');
      expect(stock.quickWarehouse.value, 'WH 11');
      await tester.tap(find.text('In stock'));
      await tester.pumpAndSettle();
      expect(stock.quickWarehouse.value, 'WH 11');
      expect(stock.quickState.value, 'instock');
      final result = find.text('Item 11');
      final report = find.byType(CustomScrollView);
      await tester.scrollUntilVisible(
        result,
        160,
        scrollable: find.descendant(
          of: report,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          ),
        ),
      );
      expect(result, findsOneWidget);
      expect(tester.getRect(result).overlaps(tester.getRect(report)), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'document item choices ignore reselects and keep results reachable',
    (tester) async {
      addTearDown(Get.reset);
      registerDeliveryNoteTestServices();
      Get.put(DeliveryNoteProvider());
      Get.put(WorkOrderProvider());
      Get.put(PackingSlipProvider());
      Get.put(PosUploadProvider());

      late _DeliveryNote delivery;
      late _PackingSlip packing;
      await tester.pumpWidget(
        GetMaterialApp(
          theme: _theme(),
          home: const SizedBox.shrink(),
          getPages: [
            GetPage(
              name: '/note',
              page: () => const DeliveryNoteFormScreen(),
              binding: BindingsBuilder(() {
                delivery =
                    Get.put<DeliveryNoteFormController>(_DeliveryNote())
                        as _DeliveryNote;
              }),
            ),
            GetPage(
              name: '/slip',
              page: () => const PackingSlipFormScreen(),
              binding: BindingsBuilder(() {
                packing =
                    Get.put<PackingSlipFormController>(_PackingSlip())
                        as _PackingSlip;
              }),
            ),
          ],
        ),
      );

      for (final (route, pending) in [
        ('/note', 'Pending (0)'),
        ('/slip', 'Pending (1)'),
      ]) {
        Get.toNamed<void>(
          route,
          arguments: {'name': 'FIXTURE', 'mode': 'view'},
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Items'));
        await tester.pumpAndSettle();
        final selections = route == '/note'
            ? delivery.selections
            : packing.selections;
        final all = _chip('All (1)');
        _expectTarget(tester, all);
        await tester.tap(all);
        await tester.pumpAndSettle();
        expect(selections, isEmpty);
        expect(
          find.textContaining('Test Strap', findRichText: true),
          findsWidgets,
        );

        final choice = _chip(pending);
        _expectTarget(tester, choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(selections, ['Pending']);
        expect(
          _action(tester, pending).flagsCollection.isSelected,
          ui.Tristate.isTrue,
        );
        Get.back<void>();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'Item stock choices display and select each full warehouse name',
    (tester) async {
      addTearDown(Get.reset);
      Get.put<ApiProvider>(FakeApiProvider());
      Get.put(ItemProvider());
      final item = _ItemForm();
      Get.put<ItemFormController>(item);
      Get.put(ItemTabController());
      await tester.pumpWidget(
        GetMaterialApp(theme: _theme(), home: const ItemFormScreen()),
      );
      await tester.tap(find.text('Stock Levels'));
      await tester.pumpAndSettle();

      const northA = 'North - Company A';
      const northB = 'North - Company B';
      expect(_chip(northA), findsOneWidget);
      expect(_chip(northB), findsOneWidget);
      expect(
        _action(tester, northA).flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );
      await tester.tap(_chip(northB));
      await tester.pumpAndSettle();
      expect(item.selectedWarehouse.value, northB);
      expect(
        _action(tester, northB).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        _action(tester, northA).flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );
      await tester.tap(_chip(northA));
      await tester.pumpAndSettle();
      expect(item.selectedWarehouse.value, northA);
      expect(
        _action(tester, northA).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      await tester.tap(_chip('All'));
      await tester.pumpAndSettle();
      expect(item.selectedWarehouse.value, isNull);
    },
  );

  for (final brightness in Brightness.values) {
    for (final accent in AppAccent.all) {
      testWidgets(
        'rendered selectable states match their contrast roles [${brightness.name} ${accent.name}]',
        (tester) async {
          tester.view.devicePixelRatio = 2;
          tester.view.physicalSize = const Size(700, 420);
          addTearDown(tester.view.reset);
          _keepKeyboardHighlight();
          final theme = _theme(brightness: brightness, accent: accent);
          final palette = HeaderPalette(theme);
          final host = palette.scheme.bg;
          final boundary = GlobalKey();
          final focus = FocusNode();
          addTearDown(focus.dispose);

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  backgroundColor: host,
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SelectableFilterChip(
                            label: 'Rest',
                            selected: false,
                            onSelected: (_) {},
                          ),
                          SelectableFilterChip(
                            label: 'Selected',
                            dotColor: palette.choiceFill(true, true),
                            selected: true,
                            focusNode: focus,
                            onSelected: (_) {},
                          ),
                          const SelectableFilterChip(
                            label: 'Off',
                            selected: false,
                            onSelected: null,
                          ),
                          const SelectableFilterChip(
                            label: 'On',
                            selected: true,
                            onSelected: null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          Rect paintBounds(String text) => tester.getRect(
            find.descendant(of: _chip(text), matching: find.byType(Ink)),
          );

          final rest = await _Pixels.capture(tester, boundary);
          for (final (caption, selected, enabled) in [
            ('Rest', false, true),
            ('Selected', true, true),
            ('Off', false, false),
            ('On', true, false),
          ]) {
            final rect = paintBounds(caption);
            final fill = rest.at(Offset(rect.center.dx, rect.top + 3));
            final actualHost = rest.at(Offset(rect.center.dx, rect.top - 3));
            final ink = palette.choiceInk(selected, enabled);
            final label = tester.getRect(find.text(caption));
            expect(
              fill,
              palette.choiceFill(selected, enabled),
              reason: caption,
            );
            expect(actualHost, host);
            expect(
              rest.containsInk(label, ink),
              isTrue,
              reason: '$caption opaque label',
            );
            expect(contrast(ink, fill), greaterThanOrEqualTo(4.5));
            if (selected) {
              final check = Rect.fromLTRB(
                rect.left + 6,
                rect.top + 6,
                rect.left + 25,
                rect.bottom - 6,
              );
              expect(
                rest.containsInk(check, ink),
                isTrue,
                reason: '$caption opaque check',
              );
              expect(contrast(fill, actualHost), greaterThanOrEqualTo(3));
            } else {
              final outline = rest.at(Offset(rect.center.dx, rect.top + .25));
              expect(outline, palette.muted);
              expect(contrast(outline, fill), greaterThanOrEqualTo(3));
              expect(contrast(outline, actualHost), greaterThanOrEqualTo(3));
            }
          }

          final selectedRect = paintBounds('Selected');
          final selectedInk = palette.choiceInk(true, true);
          final dot = find.descendant(
            of: _chip('Selected'),
            matching: find.byWidgetPredicate((widget) {
              if (widget is! Container) return false;
              final decoration = widget.decoration;
              return decoration is BoxDecoration &&
                  decoration.shape == BoxShape.circle &&
                  decoration.border != null;
            }),
          );
          final dotRect = tester.getRect(dot);
          final dotFill = rest.at(dotRect.center);
          expect(dotFill, palette.choiceFill(true, true));
          expect(rest.containsInk(dotRect, selectedInk), isTrue);
          expect(contrast(selectedInk, dotFill), greaterThanOrEqualTo(3));
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(focus.hasPrimaryFocus, isTrue);
          final focused = await _Pixels.capture(tester, boundary);
          final contour = focused.at(
            Offset(selectedRect.center.dx, selectedRect.top - 1),
          );
          final separator = focused.at(
            Offset(selectedRect.center.dx, selectedRect.top - 2.75),
          );
          expect(contour, palette.muted);
          expect(separator, palette.surface);
          expect(contrast(contour, separator), greaterThanOrEqualTo(3));
          expect(contrast(contour, host), greaterThanOrEqualTo(3));

          final pointer = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await pointer.addPointer(location: const Offset(4, 4));
          await pointer.moveTo(selectedRect.center);
          await tester.pumpAndSettle();
          await pointer.down(selectedRect.center);
          await tester.pumpAndSettle();
          final pressed = await _Pixels.capture(tester, boundary);
          final dec =
              tester
                      .widget<Ink>(
                        find.descendant(
                          of: _chip('Selected'),
                          matching: find.byType(Ink),
                        ),
                      )
                      .decoration!
                  as ShapeDecoration;
          expect((dec.shape as OutlinedBorder).side.width, 3);
          final stroke = pressed.at(
            Offset(selectedRect.center.dx, selectedRect.top - 2.5),
          );
          final fill = pressed.at(
            Offset(selectedRect.center.dx, selectedRect.top + 3),
          );
          expect(stroke, palette.muted);
          expect(
            contrast(
              fill,
              Color.alphaBlend(
                palette.quickPressedLayer,
                palette.choiceFill(true, true),
              ),
            ),
            lessThan(1.02),
          );
          final ink = palette.choiceInk(true, true);
          expect(
            pressed.containsInk(tester.getRect(find.text('Selected')), ink),
            isTrue,
          );
          expect(
            pressed.containsInk(
              Rect.fromLTRB(
                selectedRect.left + 6,
                selectedRect.top + 6,
                selectedRect.left + 25,
                selectedRect.bottom - 6,
              ),
              ink,
            ),
            isTrue,
          );
          expect(contrast(ink, fill), greaterThanOrEqualTo(4.5));
          final mark = pressed.at(
            Offset(selectedRect.center.dx, selectedRect.bottom - 2.5),
          );
          final markSeparator = pressed.at(
            Offset(selectedRect.center.dx, selectedRect.bottom - 1.5),
          );
          expect(contrast(mark, markSeparator), greaterThanOrEqualTo(3));
          await pointer.cancel();
          await pointer.removePointer();
        },
      );
    }
  }
}
