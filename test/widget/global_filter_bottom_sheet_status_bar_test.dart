import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

void main() {
  // The shell reserves `statusBar + 48` at the top, and it is shared by the
  // Packing Slip, POS Upload, PO, PR, Sales Order, Stock Entry and ToDo filter
  // sheets. It used to read the inset from MediaQuery.viewPadding.top, which
  // Get.bottomSheet zeroes (removeTop: true), leaving a bare 48 that a tall
  // status bar or display cutout eats into.
  testWidgets('reserves the real status bar height above the sheet',
      (tester) async {
    const statusBar = 140.0; // a cutout device, well past the hardcoded 48
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    Get.bottomSheet(
      GlobalFilterBottomSheet(
        sortOptions: const [SortOption('Name', 'name')],
        currentSortField: 'name',
        currentSortOrder: 'asc',
        onSortChanged: (_, __) {},
        // Tall enough that the sheet wants the whole screen.
        filterWidgets: List.generate(12, (i) => SizedBox(height: 80, child: Text('f$i'))),
        onApply: () {},
        onClear: () {},
      ),
      isScrollControlled: true,
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('Sort & Filter')).top,
        greaterThanOrEqualTo(statusBar),
        reason: 'the sheet title must clear a tall status bar');
  });
}
