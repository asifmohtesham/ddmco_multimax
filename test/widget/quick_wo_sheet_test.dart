import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/bom/bom_screen.dart';

const _bom = BOM(
  name: 'BOM-ITEM-A-001',
  item: 'ITEM-A',
  itemName: 'Item A',
  quantity: 1,
  uom: 'Nos',
  company: 'Multimax',
  isActive: 1,
  isDefault: 1,
  docstatus: 1,
  totalCost: 0,
  rawMaterialCost: 0,
  operatingCost: 0,
  withOperations: 0,
  items: [],
  explodedItems: [],
);

void main() {
  testWidgets('keyboard lift is applied once: Create Work Order sits on the '
      'keyboard and is tappable', (tester) async {
    // Regression: Get.bottomSheet already wraps the sheet in
    // Padding(bottom: viewInsets.bottom). A second one in the sheet lifted it
    // by twice the keyboard height, leaving a gap above the keyboard and
    // pushing the title under the status bar. Opened via Get.bottomSheet
    // exactly like the BOM list does on long-press.
    const keyboard = 300.0;
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(GetMaterialApp(
      getPages: [
        // Stub destination: the sheet navigates to the Work Order form.
        GetPage(
          name: AppRoutes.WORK_ORDER_FORM,
          page: () => const Scaffold(body: Text('work order form')),
        ),
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            viewInsets: const EdgeInsets.only(bottom: keyboard)),
        child: child!,
      ),
      home: const Scaffold(body: SizedBox.shrink()),
    ));
    Get.bottomSheet(
      const QuickWoSheet(bom: _bom),
      isScrollControlled: true,
    );
    await tester.pumpAndSettle();

    const keyboardTop = 1000 - keyboard;
    final create =
        tester.getRect(find.widgetWithText(FilledButton, 'Create Work Order'));
    expect(create.bottom, lessThanOrEqualTo(keyboardTop),
        reason: 'the button must not be hidden by the keyboard');
    expect(create.bottom, greaterThan(keyboardTop - 40),
        reason: 'sheet must sit on the keyboard, not a keyboard-height above');

    await tester.tap(find.widgetWithText(FilledButton, 'Create Work Order'));
    await tester.pumpAndSettle();
    expect(find.text('work order form'), findsOneWidget,
        reason: 'the visible button must receive the tap and navigate');
  });
}
