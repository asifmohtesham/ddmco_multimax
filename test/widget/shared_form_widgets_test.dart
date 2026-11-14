import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/doc_detail_row.dart';
import 'package:multimax/app/modules/global_widgets/doc_summary_row.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/main.dart' show buildAppTheme;

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// WCAG 2.x contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('FormEmptyState', () {
    testWidgets('renders icon + message; title/action optional by default',
        (tester) async {
      await tester.pumpWidget(_wrap(const FormEmptyState(
        icon: Icons.attach_file_outlined,
        message: 'No attachments found.',
      )));
      expect(find.byIcon(Icons.attach_file_outlined), findsOneWidget);
      expect(find.text('No attachments found.'), findsOneWidget);
    });

    testWidgets('renders title and action when provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(FormEmptyState(
        icon: Icons.qr_code_scanner,
        title: 'No Items',
        message: 'Scan an item or tap + to add.',
        action: FilledButton(
          onPressed: () => tapped = true,
          child: const Text('Add'),
        ),
      )));
      expect(find.text('No Items'), findsOneWidget);
      await tester.tap(find.text('Add'));
      expect(tapped, isTrue);
    });
  });

  group('DocDetailRow', () {
    testWidgets('shows label + value, no copy icon by default', (tester) async {
      await tester.pumpWidget(_wrap(const DocDetailRow(
        label: 'Item Code',
        value: 'ITEM-001',
      )));
      expect(find.text('Item Code'), findsOneWidget);
      expect(find.text('ITEM-001'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsNothing);
    });

    testWidgets('copy icon fires onCopy when copyable', (tester) async {
      var copied = false;
      await tester.pumpWidget(_wrap(DocDetailRow(
        label: 'Item Code',
        value: 'ITEM-001',
        isCopyable: true,
        onCopy: () => copied = true,
      )));
      expect(find.byIcon(Icons.copy), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy));
      expect(copied, isTrue);
    });
  });

  group('DocSummaryRow', () {
    testWidgets('renders label + value', (tester) async {
      await tester.pumpWidget(_wrap(const DocSummaryRow(
        label: 'Grand Total',
        value: '\$ 100.00',
        isBold: true,
      )));
      expect(find.text('Grand Total'), findsOneWidget);
      expect(find.text('\$ 100.00'), findsOneWidget);
    });

    // Regression: the non-bold value used onSurface @ 0.6 alpha, which
    // composited to 3.99:1 (sub-AA) on DocSectionCard's surfaceContainerLow
    // fill in light mode.
    for (final b in Brightness.values) {
      testWidgets('non-bold value passes AA on DocSectionCard fill [$b]',
          (tester) async {
        final theme = buildAppTheme(AppScheme.of(b), b);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: DocSummaryRow(label: 'Total Quantity', value: '194.00'),
          ),
        ));

        final value = tester.widget<Text>(find.text('194.00'));
        final ink = value.style!.color!;
        final cardFill = theme.colorScheme.surfaceContainerLow;
        expect(ink.a, 1.0,
            reason: 'value ink must be opaque — alpha composites '
                'unpredictably across surfaces');
        expect(_contrast(ink, cardFill), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('SelectableFilterChip', () {
    testWidgets('renders label with count and fires onSelected',
        (tester) async {
      bool? got;
      await tester.pumpWidget(_wrap(SelectableFilterChip(
        label: 'Pending',
        count: 3,
        selected: false,
        onSelected: (v) => got = v,
      )));
      expect(find.text('Pending (3)'), findsOneWidget);
      await tester.tap(find.byType(ChoiceChip));
      expect(got, isTrue);
    });

    testWidgets('omits count when null', (tester) async {
      await tester.pumpWidget(_wrap(SelectableFilterChip(
        label: 'All',
        selected: true,
        onSelected: (_) {},
      )));
      expect(find.text('All'), findsOneWidget);
    });
  });
}
