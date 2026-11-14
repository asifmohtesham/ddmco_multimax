import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/main.dart' show buildAppTheme;

void main() {
  testWidgets('save bar swaps icon for a spinner when the busy flag flips',
      (tester) async {
    final busy = false.obs;
    addTearDown(busy.close);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(AppScheme.light, Brightness.light),
      home: Scaffold(
        body: AsyncFilledButton(
          busy: busy,
          onPressed: () {},
          icon: const Icon(Icons.save_outlined, size: 18),
          label: 'Save re-order rules',
          loadingLabel: 'Saving…',
        ),
      ),
    ));

    expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    busy.value = true;
    // Single pumps — pumpAndSettle would spin forever on the indefinite
    // CircularProgressIndicator.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving…'), findsOneWidget);
  });
}
