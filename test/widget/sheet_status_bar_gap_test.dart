import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/widgets/sheet_status_bar_gap.dart';

void main() {
  // A sheet taller than the space Get.bottomSheet gives it: without the gap it
  // fills the screen and its first row sits behind the status bar. Get pushes
  // the route with removeTop: true, so a SafeArea inside would do nothing.
  Widget tallSheet() => const SheetStatusBarGap(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sheet title'),
              SizedBox(height: 2000),
            ],
          ),
        ),
      );

  testWidgets('a tall sheet starts below the status bar', (tester) async {
    const statusBar = 60.0;
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    Get.bottomSheet(tallSheet(), isScrollControlled: true);
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('Sheet title')).top,
        greaterThanOrEqualTo(statusBar),
        reason: 'the first row must clear the status bar');
  });

  testWidgets('a short sheet still sits at the bottom', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 60);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    Get.bottomSheet(
      const SheetStatusBarGap(
        child: SizedBox(height: 100, child: Text('Short sheet')),
      ),
      isScrollControlled: true,
    );
    await tester.pumpAndSettle();

    // The gap must not push a short sheet up off the bottom edge.
    expect(tester.getRect(find.text('Short sheet')).bottom, 700);
  });
}
