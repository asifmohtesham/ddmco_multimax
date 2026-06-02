// test/widget/camera_viewfinder_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/modules/global_widgets/camera_viewfinder_panel.dart';

void main() {
  group('CameraViewfinderPanel', () {
    testWidgets('renders with fixed 200px height', (tester) async {
      final controller = MobileScannerController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraViewfinderPanel(
              controller: controller,
              onBarcode: (_) {},
            ),
          ),
        ),
      );

      final box = tester.renderObject<RenderBox>(
        find.byType(CameraViewfinderPanel),
      );
      expect(box.size.height, equals(200.0));
    });
  });
}
