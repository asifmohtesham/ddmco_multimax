import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/shared/pos_upload/item_group_card.dart';
import 'package:multimax/main.dart' show buildAppTheme;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  Widget app(Brightness b, Widget child) => MaterialApp(
        theme: buildAppTheme(AppScheme.of(b), b),
        home: Scaffold(body: child),
      );

  group('InlineBanner', () {
    for (final b in Brightness.values) {
      testWidgets('warning banner text is readable (≥4.5) [$b]',
          (tester) async {
        await tester.pumpWidget(app(
          b,
          const InlineBanner(
            visible: true,
            message: 'Careful now',
            type: BannerType.warning,
          ),
        ));
        await tester.pumpAndSettle();

        final text = tester.widget<Text>(find.text('Careful now'));
        final banner = tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.color != null);
        // Banner fill may be translucent — composite over the surface.
        final surface = AppScheme.of(b).fg;
        final effectiveBg = Color.alphaBlend(banner.color!, surface);
        expect(
          _contrast(text.style!.color!, effectiveBg),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('ItemGroupCard demand chip', () {
    testWidgets('short-demand POS chip ink is not amber700 in light mode',
        (tester) async {
      await tester.pumpWidget(app(
        Brightness.light,
        SingleChildScrollView(
          child: ItemGroupCard(
            isExpanded: false,
            serialNo: 1,
            itemName: 'Widget',
            rate: 1.0,
            totalQty: 10,
            scannedQty: 2,
            posUploadQty: 5, // < totalQty → demand-short (amber) state
            onToggle: () {},
            children: const [],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final texts = tester.widgetList<Text>(find.byType(Text));
      final inks = texts.map((t) => t.style?.color).whereType<Color>();
      // amber.shade700 is ~2.1:1 on the white card — must not be used as ink.
      expect(inks, isNot(contains(Colors.amber.shade700)));
    });
  });
}
