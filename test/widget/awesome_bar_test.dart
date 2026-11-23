import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';
import 'package:multimax/app/modules/common/widgets/awesome_bar.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:shared_preferences/shared_preferences.dart';

import '../unit/theme_contrast_test.dart' show contrast;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets('empty AwesomeBar uses theme inks in ${brightness.name} mode', (
      tester,
    ) async {
      final scheme = AppScheme.of(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppScheme.light, Brightness.light),
          darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: Scaffold(body: AwesomeBar()),
        ),
      );
      await tester.tap(find.byTooltip('Search or type a command'));
      await tester.pumpAndSettle();

      for (final finder in [
        find.text('No results found'),
        find.textContaining('Try searching for an ID'),
      ]) {
        expect(tester.widget<Text>(finder).style?.color, scheme.textMuted);
      }
      expect(
        tester.widget<Icon>(find.byIcon(Icons.search_off)).color,
        scheme.textSubtle,
      );
    });

    testWidgets(
      'scan recents show outcomes and readable text in ${brightness.name} mode',
      (tester) async {
        _seedScans([
          AwesomeBarOption.scan(
            code: '10048832',
            kind: ScanType.item,
            outcome: ScanOutcome.ok,
            itemLabel: 'POUCH <LEATHER>',
          ),
          AwesomeBarOption.scan(
            code: 'WH-01-R-A1',
            kind: ScanType.rack,
            outcome: ScanOutcome.ok,
            rackId: 'WH-01-R-A1',
          ),
          AwesomeBarOption.scan(
            code: 'TEMPLATE',
            kind: ScanType.variant_of,
            outcome: ScanOutcome.ok,
          ),
          AwesomeBarOption.scan(
            code: 'missing',
            kind: ScanType.unknown,
            outcome: ScanOutcome.notFound,
          ),
          AwesomeBarOption.scan(
            code: 'bad-rack-code',
            kind: ScanType.rack,
            outcome: ScanOutcome.invalid,
          ),
          AwesomeBarOption.scan(
            code: 'WH-01-R-A2',
            kind: ScanType.rack,
            outcome: ScanOutcome.empty,
          ),
          AwesomeBarOption.scan(
            code: 'error-code',
            kind: ScanType.error,
            outcome: ScanOutcome.error,
          ),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(AppScheme.of(brightness), brightness),
            home: Scaffold(body: AwesomeBar(onScanRepeat: (_) async {})),
          ),
        );
        await _openSearch(tester);

        expect(find.text('RECENT'), findsOneWidget);
        expect(find.text('Scanned 10048832'), findsOneWidget);
        for (final (label, icon) in [
          ('POUCH <LEATHER>', searchTargetForDoctype('Item')!.icon),
          ('Rack WH-01-R-A1', Icons.shelves),
          ('Variants of TEMPLATE', Icons.account_tree_outlined),
          ('missing', Icons.qr_code_scanner),
        ]) {
          final tile = find.ancestor(
            of: find.text(label),
            matching: find.byType(ListTile),
          );
          expect(
            find.descendant(of: tile, matching: find.byIcon(icon)),
            findsOneWidget,
          );
        }

        for (final outcome in [
          'Not found',
          'Invalid rack code',
          'Empty rack',
          'Scan failed',
        ]) {
          final label = find.text(outcome);
          final foreground = tester.widget<Text>(label).style!.color!;
          final backgrounds = find.ancestor(
            of: label,
            matching: find.byWidgetPredicate(
              (widget) => widget is Material && widget.color != null,
            ),
          );
          final surface = tester.widget<Material>(backgrounds.first);
          final background = ElevationOverlay.applySurfaceTint(
            surface.color!,
            surface.surfaceTintColor,
            surface.elevation,
          );
          expect(
            foreground,
            brightness == Brightness.dark ? AppColors.red300 : AppColors.red700,
          );
          expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
      },
    );
  }

  testWidgets('tapping a scan recent closes the search and replays its code', (
    tester,
  ) async {
    _seedScans([
      AwesomeBarOption.scan(
        code: 'Missing <Code>',
        kind: ScanType.unknown,
        outcome: ScanOutcome.notFound,
      ),
    ]);
    final repeated = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AwesomeBar(onScanRepeat: (code) async => repeated.add(code)),
        ),
      ),
    );
    await _openSearch(tester);
    final label = find.text('Missing <Code>');
    final tile = tester.widget<ListTile>(
      find.ancestor(of: label, matching: find.byType(ListTile)),
    );
    await tester.tap(label);
    // Dispatch a second tap through the tile while the route is closing.
    tile.onTap!();
    await tester.pumpAndSettle();

    expect(repeated, ['Missing <Code>']);
    expect(find.byType(SearchBar), findsNothing);
    await _openSearch(tester);
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('Missing <Code>'), findsOneWidget);
  });

  testWidgets(
    'a new scan shows in RECENT when reopening an existing AwesomeBar',
    (tester) async {
      final controller = Get.put(
        AwesomeBarController(
          globalSearch: (_) async =>
              Response(requestOptions: RequestOptions(), data: {'message': []}),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AwesomeBar(onScanRepeat: (_) async {})),
        ),
      );
      await _openSearch(tester);
      await tester.enterText(find.byType(EditableText), 'retained query');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await _openSearch(tester);
      expect(find.text('retained query'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.runAsync(
        () => AwesomeBarRecentStore.record(
          AwesomeBarOption.scan(
            code: 'NEWSCAN',
            kind: ScanType.variant_of,
            outcome: ScanOutcome.ok,
          ),
        ),
      );
      await _openSearch(tester);
      expect(Get.find<AwesomeBarController>(), same(controller));
      expect(find.text('retained query'), findsNothing);
      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('Variants of NEWSCAN'), findsOneWidget);
    },
  );

  testWidgets('an AwesomeBar outside Dashboard omits scan recents', (
    tester,
  ) async {
    _seedScans([
      AwesomeBarOption.scan(
        code: 'DASHBOARD-SCAN',
        kind: ScanType.unknown,
        outcome: ScanOutcome.notFound,
      ),
    ]);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AwesomeBar())),
    );
    await _openSearch(tester);

    expect(find.text('DASHBOARD-SCAN'), findsNothing);
    expect(find.text('RECENT'), findsNothing);
    expect(find.text('No results found'), findsOneWidget);
  });
}

void _seedScans(List<AwesomeBarOption> scans) {
  SharedPreferences.setMockInitialValues({
    'awesome_bar_recents': scans.map((scan) => jsonEncode(scan.toJson())).toList(),
  });
}

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search or type a command'));
  await tester.pumpAndSettle();
}
