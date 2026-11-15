import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/home/rack_contents_logic.dart';
import 'package:multimax/app/modules/home/widgets/rack_contents_sheet.dart';
import 'package:multimax/main.dart' show buildAppTheme;

/// The Dashboard rack-contents card and sheet at phone width (360 px), in
/// light and dark: Item fields under their Item DocType labels, Balance Qty
/// as the largest figure, a neutral image placeholder, the quiet note when
/// Item details failed, and the list conventions (scrollbar, end-of-list
/// total).
void main() {
  const full = RackContentsEntry(
    itemCode: '3000247',
    itemName: 'BELTS LADIES PU',
    balanceQty: 36,
    stockUom: 'Nos',
    itemGroup: 'Belts',
    image: '/files/3000247-SGPU-14.jpg',
    variantOf: 'SGPU-14',
    countryOfOrigin: 'China',
    brand: 'FOCUS',
    description: 'BELTS LADIES PU-FOCUS-PU-Pin-Womens-MIX-4MM-110-115CM-PU-25mm-PIN',
  );

  const bare = RackContentsEntry(
    itemCode: '2002654',
    itemName: '2002654',
    balanceQty: 0,
    stockUom: 'Nos',
    itemGroup: 'Belts',
    disabled: true,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Brightness brightness,
    double height = 1200,
  }) async {
    await tester.binding.setSurfaceSize(Size(360, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scheme =
        brightness == Brightness.dark ? AppScheme.dark : AppScheme.light;
    final theme = buildAppTheme(scheme, brightness);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      darkTheme: theme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: child),
    ));
    // Let the test HTTP client fail the image load so errorBuilder runs.
    await tester.pump();
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    group('RackContentsCard ($mode)', () {
      testWidgets('shows the Item fields under their DocType labels',
          (tester) async {
        await pump(
          tester,
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: RackContentsCard(
              entry: full,
              imageUrl: 'https://erp.domain.com/files/3000247-SGPU-14.jpg',
            ),
          ),
          brightness: brightness,
        );

        expect(tester.takeException(), isNull);
        for (final label in [
          'Variant Of',
          'Country of Origin',
          'Item Group',
          'Brand',
          'Description',
          'Balance Qty',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text('SGPU-14'), findsOneWidget);
        expect(find.text('China'), findsOneWidget);
        expect(find.text('FOCUS'), findsOneWidget);
        expect(find.text('3000247'), findsOneWidget);
        expect(find.text('36'), findsOneWidget);
        expect(find.text('Nos'), findsOneWidget);
      });

      testWidgets('Balance Qty is the largest figure on the card',
          (tester) async {
        await pump(
          tester,
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: RackContentsCard(entry: full, imageUrl: null),
          ),
          brightness: brightness,
        );

        final qty = tester.widget<Text>(find.byKey(const ValueKey('rack-card-qty')));
        final qtySize = qty.style!.fontSize!;
        final others = tester
            .widgetList<Text>(find.descendant(
                of: find.byType(RackContentsCard), matching: find.byType(Text)))
            .where((t) => t.key != const ValueKey('rack-card-qty'));
        for (final t in others) {
          expect(t.style?.fontSize ?? 14, lessThan(qtySize),
              reason: '"${t.data}" must be smaller than the quantity');
        }
        // Ink comes from the scheme, never a hardcoded colour.
        final element = tester.element(find.byType(RackContentsCard));
        expect(qty.style!.color, element.scheme.text);
      });

      testWidgets('no image and a failed image both show the placeholder',
          (tester) async {
        await pump(
          tester,
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(children: [
              RackContentsCard(entry: bare, imageUrl: null),
              SizedBox(height: 12),
              RackContentsCard(
                entry: full,
                imageUrl: 'https://erp.domain.com/files/missing.jpg',
              ),
            ]),
          ),
          brightness: brightness,
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('rack-card-image-placeholder')),
            findsNWidgets(2));
      });

      testWidgets('a bare row shows Disabled and a muted zero, no empty labels',
          (tester) async {
        await pump(
          tester,
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: RackContentsCard(entry: bare, imageUrl: null),
          ),
          brightness: brightness,
        );

        expect(find.text('Disabled'), findsOneWidget);
        expect(find.text('Variant Of'), findsNothing);
        expect(find.text('Country of Origin'), findsNothing);
        expect(find.text('Description'), findsNothing);
        final qty = tester.widget<Text>(find.byKey(const ValueKey('rack-card-qty')));
        expect(qty.data, '0');
        final element = tester.element(find.byType(RackContentsCard));
        expect(qty.style!.color, element.scheme.textMuted);
      });
    });

    group('RackContentsSheet ($mode)', () {
      Widget sheet({bool failed = false, ValueChanged<String>? onTap}) =>
          Align(
            alignment: Alignment.bottomCenter,
            child: RackContentsSheet(
              rackId: 'KA-WH-DXB1-121D',
              entries: const [full, bare],
              baseUrl: 'https://erp.domain.com',
              itemDetailsFailed: failed,
              onItemTap: onTap,
            ),
          );

      testWidgets('ends with the list marker and the Balance Qty total',
          (tester) async {
        await pump(tester, sheet(), brightness: brightness, height: 2000);

        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollbar), findsOneWidget);
        expect(find.text('End of list · 2 items · Balance Qty 36 Nos'),
            findsOneWidget);
        expect(find.text('Item details could not be loaded.'), findsNothing);
      });

      testWidgets('says quietly when Item details could not be loaded',
          (tester) async {
        await pump(tester, sheet(failed: true), brightness: brightness);

        expect(find.text('Item details could not be loaded.'), findsOneWidget);
        expect(find.byType(RackContentsCard), findsWidgets);
      });

      testWidgets('tapping a card opens that item', (tester) async {
        final tapped = <String>[];
        await pump(tester, sheet(onTap: tapped.add),
            brightness: brightness, height: 2000);

        await tester.tap(find.text('BELTS LADIES PU'));
        await tester.pump();
        expect(tapped, ['3000247']);
      });
    });
  }

  test('footer omits the unit when rows mix UOMs', () {
    const pair = RackContentsEntry(
        itemCode: 'x', itemName: 'x', balanceQty: 1500, stockUom: 'Pair');
    expect(rackContentsFooterLabel(const [full, pair]),
        'End of list · 2 items · Balance Qty 1,536');
    expect(rackContentsFooterLabel(const [full]),
        'End of list · 1 item · Balance Qty 36 Nos');
  });
}
