import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

Widget _wrapInSliver(Widget sliver) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(slivers: [
        sliver,
        const SliverToBoxAdapter(
          child: SizedBox(height: 1000),
        ),
      ]),
    ),
  );
}

void main() {
  group('DocTypeFormHeader', () {
    testWidgets('renders doctype label when docType provided', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(
          title: 'WO-2024-00123',
          docType: 'Work Order',
        ),
      ));
      expect(find.text('WORK ORDER'), findsOneWidget);
    });

    testWidgets('renders status pill when statusLabel provided', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(
          title: 'WO-2024-00123',
          statusLabel: 'Draft',
        ),
      ));
      expect(find.byType(StatusPill), findsWidgets);
    });

    testWidgets('renders without docType or statusLabel (backwards compat)', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(title: 'WO-2024-00123'),
      ));
      expect(find.byType(StatusPill), findsNothing);
    });

    testWidgets('unsaved indicator visible when canSave and docStatus==0', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(
          title: 'WO-2024-00123',
          canSave: true,
          docStatus: 0,
        ),
      ));
      expect(find.text('Unsaved changes'), findsOneWidget);
    });

    testWidgets('unsaved indicator hidden when canSave but docStatus==1', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(
          title: 'WO-2024-00123',
          canSave: true,
          docStatus: 1,
        ),
      ));
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets('emits a single SliverPersistentHeader', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(title: 'TEST-001'),
      ));
      expect(find.byType(SliverPersistentHeader), findsOneWidget);
    });
  });
}
