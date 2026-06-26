import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';

void main() {
  group('AsyncIconButton', () {
    testWidgets('shows the icon and fires onPressed when not busy',
        (tester) async {
      final busy = false.obs;
      addTearDown(busy.close);
      var taps = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncIconButton(
            busy: busy,
            onPressed: () => taps++,
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Create',
          ),
        ),
      ));

      expect(find.byIcon(Icons.receipt_long), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(IconButton));
      expect(taps, 1);
    });

    testWidgets('shows a spinner and disables the button while busy',
        (tester) async {
      final busy = false.obs;
      addTearDown(busy.close);
      var taps = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncIconButton(
            busy: busy,
            onPressed: () => taps++,
            icon: const Icon(Icons.receipt_long),
          ),
        ),
      ));

      busy.value = true;
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long), findsNothing);

      // Disabled: tapping does nothing (re-entrancy protection).
      await tester.tap(find.byType(IconButton));
      expect(taps, 0);
    });

    testWidgets(
        'repaints inside a SliverPersistentHeader extraAction without scroll '
        '(carries its own Obx)', (tester) async {
      final busy = false.obs;
      addTearDown(busy.close);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              DocTypeFormHeader(
                title: 'PO-1',
                docType: 'Purchase Order',
                extraActions: [
                  AsyncIconButton(
                    busy: busy,
                    onPressed: () {},
                    icon: const Icon(Icons.receipt_long),
                  ),
                ],
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 1000)),
            ],
          ),
        ),
      ));

      expect(find.byIcon(Icons.receipt_long), findsOneWidget);

      busy.value = true;
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long), findsNothing);
    });
  });

  group('AsyncFilledButton', () {
    testWidgets('shows label + icon and fires onPressed when not busy',
        (tester) async {
      final busy = false.obs;
      addTearDown(busy.close);
      var taps = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncFilledButton(
            busy: busy,
            onPressed: () => taps++,
            icon: const Icon(Icons.receipt_long),
            label: 'Create Purchase Receipt',
            loadingLabel: 'Creating…',
          ),
        ),
      ));

      expect(find.text('Create Purchase Receipt'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });

    testWidgets('shows spinner + loadingLabel and disables while busy',
        (tester) async {
      final busy = false.obs;
      addTearDown(busy.close);
      var taps = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncFilledButton(
            busy: busy,
            onPressed: () => taps++,
            icon: const Icon(Icons.receipt_long),
            label: 'Create Purchase Receipt',
            loadingLabel: 'Creating…',
          ),
        ),
      ));

      busy.value = true;
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Creating…'), findsOneWidget);
      expect(find.text('Create Purchase Receipt'), findsNothing);

      await tester.tap(find.byType(FilledButton));
      expect(taps, 0);
    });
  });
}
