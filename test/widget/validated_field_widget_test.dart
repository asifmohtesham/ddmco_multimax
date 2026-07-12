import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ValidatedFieldWidget errorText animation', () {
    testWidgets('wraps errorText in an AnimatedSwitcher', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(ValidatedFieldWidget(
        controller: controller,
        color: Colors.blue,
        hintText: 'Hint',
        isReadOnly: false,
        isValid: false,
        isValidating: false,
        onValidate: () {},
        onReset: () {},
      )));

      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });

    testWidgets(
        'fades errorText in when set and out when cleared, without leaving it behind',
        (tester) async {
      String? errorText;
      late StateSetter setState;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(StatefulBuilder(builder: (context, setter) {
        setState = setter;
        return ValidatedFieldWidget(
          controller: controller,
          color: Colors.blue,
          hintText: 'Hint',
          isReadOnly: false,
          isValid: false,
          isValidating: false,
          onValidate: () {},
          onReset: () {},
          errorText: errorText,
        );
      })));

      expect(find.text('Only 5 available'), findsNothing);

      setState(() => errorText = 'Only 5 available');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Only 5 available'), findsOneWidget);

      setState(() => errorText = null);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Only 5 available'), findsNothing);
    });
  });
}
