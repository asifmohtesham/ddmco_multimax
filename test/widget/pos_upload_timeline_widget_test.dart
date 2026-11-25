import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pos_upload/widgets/pos_upload_timeline.dart';

Widget _host(
  List<TimelineCheckpoint> checkpoints, {
  Brightness brightness = Brightness.light,
}) {
  final scheme = AppScheme.of(brightness);
  return MaterialApp(
    theme: ThemeData(
      scaffoldBackgroundColor: scheme.fg,
      colorScheme: ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: scheme.primary,
        onSurface: scheme.text,
        surface: scheme.fg,
      ),
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PosUploadTimeline(checkpoints: checkpoints),
      ),
    ),
  );
}

double _contrast(Color foreground, Color background) {
  final fg = foreground.computeLuminance();
  final bg = background.computeLuminance();
  return fg > bg ? (fg + 0.05) / (bg + 0.05) : (bg + 0.05) / (fg + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'delivery history shows event details with ${brightness.name} contrast',
      (tester) async {
        final history = buildPosUploadDeliveryHistory({
          'workflow_logs': [
            {
              'name': 'old-dispatch',
              'creation': '2026-11-24 09:20:01',
              'content':
                  'POS delivery · Out for Delivery · Driver: First Driver',
            },
          ],
          'versions': [
            {
              'creation': '2026-11-25 12:07:00.124200',
              'data': {
                'updater_reference': {
                  'pos_delivery': {
                    'action': 'Delivery Return',
                    'driver_name': 'Second Driver',
                    'recorded_by_name': 'Dispatcher',
                    'reason': 'Rejected',
                    'dn': 'DN-1',
                  },
                },
              },
            },
            {
              'creation': '2026-11-25 14:08:21',
              'data': {
                'updater_reference': {
                  'pos_delivery': {'action': 'Delivered'},
                },
              },
            },
          ],
        });
        await tester.pumpWidget(_host(history, brightness: brightness));

        expect(find.text('25 Nov 2026, 12:07:00'), findsOneWidget);
        expect(find.text('Delivery Note: DN-1'), findsOneWidget);
        expect(
          find.text(
            'Driver: Second Driver\nRecorded by: Dispatcher\nReason: Rejected by customer',
          ),
          findsOneWidget,
        );
        expect(find.text('Driver: First Driver'), findsOneWidget);

        final surface = AppScheme.of(brightness).fg;
        final isDark = brightness == Brightness.dark;
        final statuses = [
          (
            'Out for Delivery',
            AppColors.blue500,
            isDark ? AppColors.blue300 : AppColors.blue700,
          ),
          (
            'Delivery Return',
            AppColors.red500,
            isDark ? AppColors.red300 : AppColors.red700,
          ),
          (
            'Delivered',
            AppColors.green500,
            isDark ? AppColors.green300 : AppColors.green700,
          ),
        ];
        for (final (action, base, ink) in statuses) {
          final label = find.text(action);
          final pill = find.ancestor(
            of: label,
            matching: find.byType(StatusPill),
          );
          final tint = Color.alphaBlend(base.withValues(alpha: 0.13), surface);
          expect(
            find.descendant(
              of: pill,
              matching: find.byWidgetPredicate((widget) {
                if (widget is! Container) return false;
                final decoration = widget.decoration;
                return decoration is BoxDecoration && decoration.color == tint;
              }),
            ),
            findsOneWidget,
          );
          final textColor = tester.widget<Text>(label).style!.color!;
          expect(textColor, ink);
          expect(_contrast(textColor, tint), greaterThanOrEqualTo(4.5));
        }
      },
    );
  }

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
