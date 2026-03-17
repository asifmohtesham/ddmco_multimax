// Widget Test #4.3 - Close button UX feedback
//
// Requirement (from -YourRequirement-CorrectTestType.csv):
//   The item form sheet must have a close button that:
//     1. Is visible in the sheet header at all times.
//     2. Uses the standard close icon (Icons.close).
//     3. Has a visible background so it stands out against the form surface
//        (backgroundColor is colorScheme.surfaceContainerHigh).
//     4. Dismisses the sheet when tapped (Navigator.pop is called).
//
// Strategy:
//   - Pump the sheet inside a Navigator so pop() has a route to remove.
//   - Verify icon presence, background style, and post-tap route count.
//
// Run: flutter test test/widget/stock_entry/close_button_ux_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';

class _StubCtrl extends StockEntryFormController {
  @override
  void onInit() {}
}

// ---------------------------------------------------------------------------
// Pump: place the sheet on a named route ('/sheet') pushed over '/'.
// This lets us verify Navigator.pop() by checking the current route.
// ---------------------------------------------------------------------------
Future<void> _pumpWithNavigator(
    WidgetTester tester, _StubCtrl ctrl) async {
  await tester.pumpWidget(
    GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const Scaffold(body: SizedBox())),
        GetPage(
          name: '/sheet',
          page: () => Scaffold(
            body: SizedBox(
              height: 800,
              child: StockEntryItemFormSheet(
                controller: ctrl,
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  await tester.pump();
  Get.toNamed('/sheet');
  await tester.pumpAndSettle();
}

void main() {
  late _StubCtrl ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = _StubCtrl();
    ctrl.currentItemCode = 'ITEM-001';
    ctrl.currentItemName = 'Test Item';
    ctrl.currentVariantOf = '';
    ctrl.selectedStockEntryType.value = 'Material Issue';
  });

  tearDown(() async {
    await Future.delayed(Duration.zero);
    Get.reset();
  });

  // =========================================================================
  // 1. Close button is visible
  // =========================================================================
  group('Close button is visible in the sheet header', () {
    testWidgets('Icons.close is present in the widget tree', (tester) async {
      await _pumpWithNavigator(tester, ctrl);
      expect(find.byIcon(Icons.close), findsOneWidget,
          reason: 'A close icon must be visible in the sheet header.');
    });

    testWidgets('Close button is an IconButton', (tester) async {
      await _pumpWithNavigator(tester, ctrl);
      // The close icon should be inside an IconButton.
      final iconBtnFinder = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      );
      expect(iconBtnFinder, findsOneWidget,
          reason: 'Icons.close must be wrapped in an IconButton.');
    });

    testWidgets('Close button visible for all SE types', (tester) async {
      for (final type in [
        'Material Issue',
        'Material Receipt',
        'Material Transfer',
        'Material Transfer for Manufacture',
      ]) {
        ctrl.selectedStockEntryType.value = type;
        await _pumpWithNavigator(tester, ctrl);
        expect(find.byIcon(Icons.close), findsOneWidget,
            reason: 'Close icon must be visible for SE type: $type.');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  // =========================================================================
  // 2. Close button has a background (stands out against the form surface)
  // =========================================================================
  group('Close button has a styled background', () {
    testWidgets(
        'IconButton wrapping Icons.close has a non-null backgroundColor style',
        (tester) async {
      await _pumpWithNavigator(tester, ctrl);

      final iconBtnFinder = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      );
      final btn = tester.widget<IconButton>(iconBtnFinder);

      // IconButton.styleFrom sets backgroundColor via ButtonStyle.
      // We resolve it with a dummy WidgetState set to verify it is non-null.
      final style = btn.style;
      expect(style, isNotNull,
          reason: 'Close button must have an explicit style applied '
              '(IconButton.styleFrom with backgroundColor).');

      final resolvedBg = style!.backgroundColor
          ?.resolve(<WidgetState>{});
      expect(resolvedBg, isNotNull,
          reason: 'Resolved backgroundColor must not be null — the button '
              'needs a visible background to stand out on the form.');
    });

    testWidgets(
        'Close button foregroundColor is set (icon tint is intentional)',
        (tester) async {
      await _pumpWithNavigator(tester, ctrl);

      final iconBtnFinder = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      );
      final btn = tester.widget<IconButton>(iconBtnFinder);
      final style = btn.style;
      expect(style, isNotNull);

      final resolvedFg = style!.foregroundColor
          ?.resolve(<WidgetState>{});
      expect(resolvedFg, isNotNull,
          reason: 'foregroundColor must be set so the close icon '
              'colour is controlled deliberately.');
    });
  });

  // =========================================================================
  // 3. Close button dismisses the sheet
  // =========================================================================
  group('Tapping close button dismisses the sheet', () {
    testWidgets('Tapping Icons.close calls Navigator.pop', (tester) async {
      await _pumpWithNavigator(tester, ctrl);

      // Confirm we are on the sheet route.
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // After pop the sheet route is gone; the close icon is no longer visible.
      expect(find.byIcon(Icons.close), findsNothing,
          reason: 'After tapping close the sheet must be dismissed '
              '(Navigator.pop removes the route).');
    });

    testWidgets(
        'Sheet is still present before the close button is tapped',
        (tester) async {
      await _pumpWithNavigator(tester, ctrl);
      // Sanity: sheet is rendered before any tap.
      expect(find.byType(StockEntryItemFormSheet), findsOneWidget);
    });

    testWidgets(
        'Sheet is no longer in the tree after close is tapped',
        (tester) async {
      await _pumpWithNavigator(tester, ctrl);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(StockEntryItemFormSheet), findsNothing,
          reason: 'StockEntryItemFormSheet widget must leave the tree '
              'after the close button is tapped.');
    });
  });

  // =========================================================================
  // 4. Close button position — it must be in the top-right area of the sheet
  // =========================================================================
  group('Close button is positioned top-right in the sheet header', () {
    testWidgets(
        'Close button is to the right of the item code/name column',
        (tester) async {
      await _pumpWithNavigator(tester, ctrl);

      final closePos = tester.getCenter(find.byIcon(Icons.close));
      final itemCodePos = tester.getCenter(find.textContaining('ITEM-001'));

      expect(closePos.dx, greaterThan(itemCodePos.dx),
          reason: 'Close button must be to the right of the item code chip.');
    });

    testWidgets(
        'Close button vertical position is in the upper half of the sheet',
        (tester) async {
      await _pumpWithNavigator(tester, ctrl);

      final sheetRect =
          tester.getRect(find.byType(StockEntryItemFormSheet));
      final closePos = tester.getCenter(find.byIcon(Icons.close));

      expect(closePos.dy, lessThan(sheetRect.center.dy),
          reason: 'Close button must be in the upper half of the sheet '
              'so users can easily dismiss it.');
    });
  });
}
