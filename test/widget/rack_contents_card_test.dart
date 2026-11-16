import 'dart:async';

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

  group('RackContentsSheet search and as-on date', () {
    Widget sheet({
      List<RackContentsEntry> entries = const [full, bare],
      DateTime? asOf,
      RackContentsLoader? load,
    }) =>
        Align(
          alignment: Alignment.bottomCenter,
          child: RackContentsSheet(
            rackId: 'KA-WH-DXB1-121D',
            entries: entries,
            baseUrl: 'https://erp.domain.com',
            asOf: asOf,
            loadAsOf: load,
          ),
        );

    /// Types the date into the picker rather than tapping a calendar day, so
    /// the test does not depend on today's date. Leaves the picker closed
    /// but the load un-settled when [settle] is false.
    Future<void> pickDate(WidgetTester tester, String typed,
        {bool settle = true}) async {
      await tester.tap(find.byKey(const ValueKey('rack-as-of')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, typed);
      await tester.tap(find.text('OK'));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    testWidgets('search narrows the cards and the footer counts them',
        (tester) async {
      await pump(tester, sheet(), brightness: Brightness.light, height: 2000);

      await tester.enterText(find.byKey(const ValueKey('rack-search')), 'focus');
      await tester.pump();

      expect(find.byType(RackContentsCard), findsOneWidget);
      expect(find.text('BELTS LADIES PU'), findsOneWidget);
      expect(find.text('End of list · 1 of 2 items · Balance Qty 36 Nos'),
          findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.byType(RackContentsCard), findsNWidgets(2));
      expect(find.text('End of list · 2 items · Balance Qty 36 Nos'),
          findsOneWidget);
    });

    testWidgets('a search with no match says so and can be cleared',
        (tester) async {
      await pump(tester, sheet(), brightness: Brightness.dark, height: 2000);

      await tester.enterText(find.byKey(const ValueKey('rack-search')), 'zzz');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(RackContentsCard), findsNothing);
      expect(find.text('No matching items'), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await tester.pump();
      expect(find.byType(RackContentsCard), findsNWidgets(2));
    });

    testWidgets('opens on today and reloads the rack for a picked date',
        (tester) async {
      final asked = <DateTime>[];
      await pump(
        tester,
        sheet(
          asOf: DateTime.now(),
          load: (date) async {
            asked.add(date);
            return const RackContentsSnapshot(entries: [full]);
          },
        ),
        brightness: Brightness.light,
        height: 2000,
      );
      expect(find.textContaining('· Today'), findsOneWidget);

      await pickDate(tester, '01/15/2025');

      expect(asked, [DateTime(2025, 1, 15)]);
      expect(find.text('As on 15 Jan 2025'), findsOneWidget);
      expect(find.byType(RackContentsCard), findsOneWidget);
      expect(find.text('End of list · 1 item · Balance Qty 36 Nos'),
          findsOneWidget);

      // "Today" goes back to the current stock.
      await tester.tap(find.widgetWithText(TextButton, 'Today'));
      await tester.pumpAndSettle();
      expect(asked, hasLength(2));
      expect(isSameDay(asked.last, DateTime.now()), isTrue);
      expect(find.textContaining('· Today'), findsOneWidget);
    });

    testWidgets('the date button is disabled with a spinner while loading',
        (tester) async {
      final pending = Completer<RackContentsSnapshot>();
      await pump(
        tester,
        sheet(asOf: DateTime.now(), load: (_) => pending.future),
        brightness: Brightness.dark,
        height: 2000,
      );

      await pickDate(tester, '01/15/2025', settle: false);

      final button = find.byKey(const ValueKey('rack-as-of'));
      expect(tester.widget<ButtonStyleButton>(button).enabled, isFalse);
      expect(
          find.descendant(
              of: button, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // The old list stays until the new one arrives.
      expect(find.byType(RackContentsCard), findsNWidgets(2));

      pending.complete(const RackContentsSnapshot(entries: [bare]));
      await tester.pumpAndSettle();
      expect(tester.widget<ButtonStyleButton>(button).enabled, isTrue);
      expect(find.byType(RackContentsCard), findsOneWidget);
    });

    testWidgets('a failed load keeps the previous date and list',
        (tester) async {
      await pump(
        tester,
        sheet(
          asOf: DateTime.now(),
          load: (_) async => throw const FormatException('bad'),
        ),
        brightness: Brightness.light,
        height: 2000,
      );

      await pickDate(tester, '01/15/2025');

      expect(find.byKey(const ValueKey('rack-load-error')), findsOneWidget);
      expect(find.textContaining('Could not load stock as on 15 Jan 2025'),
          findsOneWidget);
      expect(find.textContaining('· Today'), findsOneWidget);
      expect(find.byType(RackContentsCard), findsNWidgets(2));
    });

    testWidgets('a date the rack was empty shows the empty state',
        (tester) async {
      await pump(
        tester,
        sheet(
          asOf: DateTime.now(),
          load: (_) async => const RackContentsSnapshot(entries: []),
        ),
        brightness: Brightness.dark,
        height: 2000,
      );

      await pickDate(tester, '01/15/2025');

      expect(tester.takeException(), isNull);
      expect(find.text('Rack was empty'), findsOneWidget);
      expect(find.text('Nothing was on KA-WH-DXB1-121D on 15 Jan 2025.'),
          findsOneWidget);
      expect(find.text('Back to Today'), findsOneWidget);
    });
  });

  test('footer names the full count while a search narrows the list', () {
    expect(rackContentsFooterLabel(const [full], outOf: 5),
        'End of list · 1 of 5 items · Balance Qty 36 Nos');
    expect(rackContentsFooterLabel(const [full], outOf: 1),
        'End of list · 1 item · Balance Qty 36 Nos');
  });

  test('footer omits the unit when rows mix UOMs', () {
    const pair = RackContentsEntry(
        itemCode: 'x', itemName: 'x', balanceQty: 1500, stockUom: 'Pair');
    expect(rackContentsFooterLabel(const [full, pair]),
        'End of list · 2 items · Balance Qty 1,536');
    expect(rackContentsFooterLabel(const [full]),
        'End of list · 1 item · Balance Qty 36 Nos');
  });
}
