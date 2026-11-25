import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('POS Upload status colours', () {
    const ramps = {
      'To Deliver': (
        AppColors.orange500,
        AppColors.orange700,
        AppColors.orange300,
      ),
      'Out for Delivery': (
        AppColors.blue500,
        AppColors.blue700,
        AppColors.blue300,
      ),
      'Delivered': (AppColors.green500, AppColors.green700, AppColors.green300),
      'Draft': (AppColors.gray500, AppColors.gray700, AppColors.gray300),
    };

    for (final brightness in Brightness.values) {
      testWidgets('renders the expected text, fill and border in $brightness', (
        tester,
      ) async {
        for (final entry in ramps.entries) {
          final status = entry.key;
          final (base, lightInk, darkInk) = entry.value;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(body: StatusPill.posUpload(status: status)),
            ),
          );
          await tester.pumpAndSettle();

          final text = tester.widget<Text>(find.text(status));
          expect(
            text.style!.color,
            brightness == Brightness.dark ? darkInk : lightInk,
          );

          final decorations = tester
              .widgetList<Container>(
                find.descendant(
                  of: find.byType(StatusPill),
                  matching: find.byType(Container),
                ),
              )
              .map((container) => container.decoration as BoxDecoration);
          final pill = decorations.singleWhere(
            (decoration) => decoration.shape == BoxShape.rectangle,
          );
          final dot = decorations.singleWhere(
            (decoration) => decoration.shape == BoxShape.circle,
          );
          expect(dot.color, base);
          expect(
            pill.color,
            Color.alphaBlend(
              base.withValues(alpha: 0.13),
              AppScheme.of(brightness).fg,
            ),
          );
          expect(pill.border, Border.all(color: base.withValues(alpha: 0.35)));
        }
      });
    }
  });

  group('StatusPill status-change animation', () {
    testWidgets('wraps its content in an AnimatedSwitcher for a cross-fade',
        (tester) async {
      await tester.pumpWidget(_wrap(const StatusPill(status: 'Draft')));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
    });

    testWidgets(
        'animates and settles to the new status text when status changes',
        (tester) async {
      String status = 'Draft';
      late StateSetter setState;

      await tester.pumpWidget(_wrap(StatefulBuilder(builder: (context, setter) {
        setState = setter;
        return StatusPill(status: status);
      })));

      expect(find.text('Draft'), findsOneWidget);

      setState(() => status = 'Completed');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Draft'), findsNothing);
    });
  });
}
