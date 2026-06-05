import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';

void main() {
  Widget buildWidget({
    bool isLoading = false,
    bool isSuccess = false,
    bool hasError = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: BarcodeInputWidget(
          onScan: (_) {},
          isLoading: isLoading,
          isSuccess: isSuccess,
          hasError: hasError,
          hintText: 'Scan Item / Batch',
        ),
      ),
    );
  }

  group('BarcodeInputWidget — no helperText in any state', () {
    testWidgets('idle state shows no coloured helper text', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Scan Item / Batch'), findsNothing);
      expect(find.text('Processing...'), findsNothing);
      expect(find.text('Scan Validated'), findsNothing);
      expect(find.text('Scan Failed'), findsNothing);
    });

    testWidgets('loading state shows no helper text', (tester) async {
      await tester.pumpWidget(buildWidget(isLoading: true));
      expect(find.text('Processing...'), findsNothing);
    });

    testWidgets('success state shows no helper text', (tester) async {
      await tester.pumpWidget(buildWidget(isSuccess: true));
      expect(find.text('Scan Validated'), findsNothing);
    });

    testWidgets('error state shows no helper text', (tester) async {
      await tester.pumpWidget(buildWidget(hasError: true));
      expect(find.text('Scan Failed'), findsNothing);
    });
  });
}
