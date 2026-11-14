import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/pos_upload/widgets/pos_upload_timeline.dart';

Widget _host(List<TimelineCheckpoint> checkpoints) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PosUploadTimeline(checkpoints: checkpoints),
        ),
      ),
    );

void main() {
  testWidgets('renders a title for every checkpoint', (tester) async {
    await tester.pumpWidget(_host(const [
      TimelineCheckpoint(
        title: 'POS Upload Created',
        statusLabel: 'Pending',
        state: CheckpointState.reached,
        timestamp: '2026-06-30 08:00:00',
        detail: '20 items',
      ),
      TimelineCheckpoint(
        title: 'Delivery Note',
        statusLabel: 'In Progress',
        state: CheckpointState.upcoming,
      ),
      TimelineCheckpoint(
        title: 'Packing Slips',
        statusLabel: 'Packing',
        state: CheckpointState.upcoming,
      ),
    ]));

    expect(find.text('POS Upload Created'), findsOneWidget);
    expect(find.text('Delivery Note'), findsOneWidget);
    expect(find.text('Packing Slips'), findsOneWidget);
  });

  testWidgets('reached node shows doc name and detail', (tester) async {
    await tester.pumpWidget(_host(const [
      TimelineCheckpoint(
        title: 'Delivery Note',
        statusLabel: 'In Progress',
        state: CheckpointState.reached,
        docName: 'ML-DN-0042',
        timestamp: '2026-06-30 09:00:00',
        detail: '540 / 600 qty · 90%',
        progress: 0.9,
      ),
    ]));

    expect(find.text('ML-DN-0042'), findsOneWidget);
    expect(find.text('540 / 600 qty · 90%'), findsOneWidget);
  });

  testWidgets('upcoming node shows an Awaiting hint', (tester) async {
    await tester.pumpWidget(_host(const [
      TimelineCheckpoint(
        title: 'Packing Slips',
        statusLabel: 'Packing',
        state: CheckpointState.upcoming,
      ),
    ]));

    expect(find.textContaining('Awaiting'), findsOneWidget);
  });

  testWidgets('loading node shows a progress spinner', (tester) async {
    await tester.pumpWidget(_host(const [
      TimelineCheckpoint(
        title: 'Delivery Note',
        statusLabel: 'In Progress',
        state: CheckpointState.loading,
      ),
    ]));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
