// Widget Test #4.3 - Close button UX feedback
//
// Requirement:
//   The item form sheet must have a close button that:
//     1. Is visible in the sheet header at all times.
//     2. Uses the standard close icon (Icons.close).
//     3. Has a visible background so it stands out against the form surface.
//     4. Dismisses the sheet when tapped (Navigator.pop is called).
//
// Run: flutter test test/widget/stock_entry/close_button_ux_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------
class _ParentCtrl extends StockEntryFormController {
  @override
  void onInit() {}
}

class _ItemCtrl extends StockEntryItemFormController {
  @override
  void onInit() {}
}

// ---------------------------------------------------------------------------
// Pump: place the sheet on a named route ('/sheet') pushed over '/'.
// This lets us verify Navigator.pop() by checking the current route.
// ---------------------------------------------------------------------------
Future<void> _pumpWithNavigator(
    WidgetTester tester, _ParentCtrl parent, _ItemCtrl ctrl) async {
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
              child: UniversalItemFormSheet(
                controller: ctrl,
                scrollController: ScrollController(),
                customFields: const [],
                onSubmit: () async {},
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
  late _ParentCtrl parent;
  late _ItemCtrl ctrl;

  setUp(() {
    Get.testMode = true;
    parent = _ParentCtrl();
    ctrl   = _ItemCtrl();
    ctrl.testInjectParent(parent);
    ctrl.itemCode.value  = 'ITEM-001';
    ctrl.itemName.value  = 'Test Item';
    parent.selectedStockEntryType.value = 'Material Issue';
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
      await _pumpWithNavigator(tester, parent, ctrl);
      expect(find.byIcon(Icons.close), findsOneWidget,
          reason: 'A close icon must be visible in the sheet header.');
    });

    testWidgets('Close button is an IconButton', (tester) async {
      await _pumpWithNavigator(tester, parent, ctrl);
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
        parent.selectedStockEntryType.value = type;
        await _pumpWithNavigator(tester, parent, ctrl);
        expect(find.byIcon(Icons.close), findsOneWidget,
            reason: 'Close icon must be visible for SE type: $type.');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  // =========================================================================
  // 2. Close button has a background
  // =========================================================================
  group('Close button has a styled background', () {
    testWidgets(
        'IconButton wrapping Icons.close has a non-null backgroundColor style',
        (tester) async {
      await _pumpWithNavigator(tester, parent, ctrl);

      final iconBtnFinder = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      );
      final btn = tester.widget<IconButton>(iconBtnFinder);
      final style = btn.style;
      expect(style, isNotNull,
          reason: 'Close button must have an explicit style applied.');

      final resolvedBg = style!.backgroundColor
          ?.resolve(<WidgetState>{});
      expect(resolvedBg, isNotNull,
          reason: 'Resolved backgroundColor must not be null.');
    });

    testWidgets(
        'Close button foregroundColor is set (icon tint is intentional)',
        (tester) async {
      await _pumpWithNavigator(tester, parent, ctrl);

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
      await _pumpWithNavigator(tester, parent, ctrl);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsNothing,
          reason: 'After tapping close the sheet must be dismissed.');
    });

    testWidgets(
        'Sheet is still present before the close button is tapped',
        (tester) async {
      await _pumpWithNavigator(tester, parent, ctrl);
      expect(find.byType(UniversalItemFormSheet), findsOneWidget);
    });

    testWidgets(
        'Sheet is no longer in the tree after close is tapped',
        (tester) async {
      await _pumpWithNavigator(tester, parent, ctrl);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(UniversalItemFormSheet), findsNothing,
          reason: 'UniversalItemFormSheet must leave the tree '
              'after the close button is tapped.');
    });
  });

  // =========================================================================
  // 4. Close button position
  // =========================================================================
  group('Close button is positioned top-right in the sheet header', () {
    testWidgets(
        'Close button is to the right of the item code/name column',
        (tester) async {
      await _pumpWithNavigator(tester, parent, ctrl);

      final closePos    = tester.getCenter(find.byIcon(Icons.close));
      final itemCodePos = tester.getCenter(find.textContaining('ITEM-001'));

      expect(closePos.dx, greaterThan(itemCodePos.dx),
          reason: 'Close button must be to the right of the item code chip.');
    });

    testWidgets(
        'Close button vertical position is in the upper half of the sheet',
        (tester) async {
      await _pumpWithNavigator(tester, parent, ctrl);

      final sheetRect =
          tester.getRect(find.byType(UniversalItemFormSheet));
      final closePos = tester.getCenter(find.byIcon(Icons.close));

      expect(closePos.dy, lessThan(sheetRect.center.dy),
          reason: 'Close button must be in the upper half of the sheet.');
    });
  });
}
