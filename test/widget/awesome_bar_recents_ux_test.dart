import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

final _now = DateTime(2026, 11, 26, 15, 30);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwesomeBarRecentStore.clock = () => _now;
  });
  tearDown(() {
    AwesomeBarRecentStore.clock = DateTime.now;
    Get.reset();
  });

  testWidgets('× removes one entry and Clear all asks before clearing', (
    tester,
  ) async {
    _seed([
      _scan('AAA', ScanOutcome.ok, at: _now),
      _scan('BBB', ScanOutcome.notFound, at: _now),
    ]);
    await _pump(tester, onScanRepeat: (_) async {});
    await _openSearch(tester);

    final removeA = find.descendant(
      of: _tileOf('AAA'),
      matching: find.byTooltip('Remove from recent'),
    );
    await tester.tap(removeA);
    await tester.pumpAndSettle();
    expect(find.text('AAA'), findsNothing);
    expect(find.text('BBB'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear recent?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('BBB'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('BBB'), findsNothing);
    expect(find.text('RECENT'), findsNothing);
    expect(find.text('Search or scan'), findsOneWidget);
    expect(await tester.runAsync(AwesomeBarRecentStore.read), isEmpty);
  });

  testWidgets('Clear all outside Dashboard keeps the hidden scans', (
    tester,
  ) async {
    _seed([
      _scan('SCAN-1', ScanOutcome.ok, at: _now),
      AwesomeBarOption.query('lost query'),
    ]);
    await _pump(tester);
    await _openSearch(tester);
    expect(find.text('SCAN-1'), findsNothing);
    expect(find.text('lost query'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    final left = await tester.runAsync(AwesomeBarRecentStore.read);
    expect(left!.map((option) => option.value), ['SCAN-1']);
  });

  testWidgets('entries show when they were saved, grouped by day', (
    tester,
  ) async {
    _seed([
      _scan(
        'NOW',
        ScanOutcome.ok,
        at: _now.subtract(const Duration(seconds: 5)),
      ),
      _scan(
        'FIVE',
        ScanOutcome.notFound,
        at: _now.subtract(const Duration(minutes: 5)),
      ),
      _scan('MORNING', ScanOutcome.ok, at: DateTime(2026, 11, 26, 9, 5)),
      _scan('YDAY', ScanOutcome.ok, at: DateTime(2026, 11, 25, 14, 5)),
      _scan('OLD', ScanOutcome.ok, at: DateTime(2026, 11, 20, 8, 0)),
      _scan('LEGACY', ScanOutcome.ok),
    ]);
    await _pump(tester, onScanRepeat: (_) async {});
    await _openSearch(tester);

    expect(find.text('Scanned NOW · Just now'), findsOneWidget);
    expect(find.text('Not found · 5 min ago'), findsOneWidget);
    expect(find.text('Scanned MORNING · 09:05'), findsOneWidget);
    expect(find.text('Scanned YDAY · Yesterday 14:05'), findsOneWidget);
    expect(find.text('Scanned OLD · 20 Nov 08:00'), findsOneWidget);
    expect(find.text('Scanned LEGACY'), findsOneWidget);
    for (final group in ['Today', 'Yesterday', 'Earlier']) {
      expect(find.text(group), findsOneWidget);
    }
    // Earlier holds both the dated and the undated entry.
    expect(
      tester.getTopLeft(find.text('Earlier')).dy,
      lessThan(tester.getTopLeft(find.text('OLD')).dy),
    );
  });

  testWidgets('one day of entries needs no day labels', (tester) async {
    _seed([
      _scan('A', ScanOutcome.ok, at: _now),
      _scan('B', ScanOutcome.ok, at: _now),
    ]);
    await _pump(tester, onScanRepeat: (_) async {});
    await _openSearch(tester);
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('only a failed scan offers edit, which scans the edited code', (
    tester,
  ) async {
    _seed([
      _scan('1004883', ScanOutcome.notFound, at: _now),
      _scan('OKCODE', ScanOutcome.ok, at: _now),
    ]);
    final repeated = <String>[];
    await _pump(tester, onScanRepeat: (code) async => repeated.add(code));
    await _openSearch(tester);

    expect(
      find.descendant(
        of: _tileOf('OKCODE'),
        matching: find.byTooltip('Edit code and scan'),
      ),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: _tileOf('1004883'),
        matching: find.byTooltip('Edit code and scan'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit code'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '1004883'),
      ' 10048832 ',
    );
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(repeated, ['10048832']);
    expect(find.byType(SearchBar), findsNothing);
  });

  testWidgets('long press offers the scan actions', (tester) async {
    _seed([
      AwesomeBarOption.scan(
        code: '10048832',
        kind: ScanType.item,
        outcome: ScanOutcome.ok,
        itemLabel: 'POUCH LEATHER',
        itemCode: 'ITM-0042',
      ),
    ]);
    final item = searchTargetForDoctype('Item')!;
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(
      tester,
      onScanRepeat: (_) async {},
      itemPage: GetPage(
        name: item.route,
        page: () => Scaffold(body: Text('Item page ${Get.arguments}')),
      ),
    );
    await _openSearch(tester);

    await tester.longPress(find.text('POUCH LEATHER'));
    await tester.pumpAndSettle();
    for (final action in [
      'Scan again',
      'Edit code and scan',
      'Open item',
      'Search for this code',
      'Copy code',
      'Remove from recent',
    ]) {
      expect(find.text(action), findsOneWidget);
    }

    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(clipboard, ['10048832']);

    await tester.longPress(find.text('POUCH LEATHER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search for this code'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '10048832',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), '');
    await tester.pumpAndSettle();
    await tester.longPress(find.text('POUCH LEATHER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open item'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Item page'), findsOneWidget);
    expect(find.textContaining('ITM-0042'), findsOneWidget);
  });

  testWidgets('a failed scan without an item does not offer Open item', (
    tester,
  ) async {
    _seed([_scan('MISSING', ScanOutcome.notFound, at: _now)]);
    await _pump(tester, onScanRepeat: (_) async {});
    await _openSearch(tester);
    await tester.longPress(find.text('MISSING'));
    await tester.pumpAndSettle();
    expect(find.text('Open item'), findsNothing);
    expect(find.text('Edit code and scan'), findsWidgets);
  });

  testWidgets('a submitted search with no results is saved and can rerun', (
    tester,
  ) async {
    final queries = <String>[];
    Get.put(
      AwesomeBarController(
        globalSearch: (query) async {
          queries.add(query);
          return Response(
            requestOptions: RequestOptions(),
            data: {'message': []},
          );
        },
      ),
    );
    await _pump(tester, onScanRepeat: (_) async {});
    await _openSearch(tester);

    await tester.enterText(find.byType(EditableText), 'zzqx');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('No results found'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), '');
    await tester.pumpAndSettle();
    expect(find.text('zzqx'), findsOneWidget);
    expect(find.text('No results · Just now'), findsOneWidget);

    await tester.tap(find.text('zzqx'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'zzqx',
    );
    expect(queries, ['zzqx', 'zzqx']);
  });

  testWidgets('typing keeps earlier results and shows a thin progress bar', (
    tester,
  ) async {
    final replies = <String, Completer<Response>>{};
    Get.put(
      AwesomeBarController(
        globalSearch: (query) => (replies[query] = Completer()).future,
      ),
    );
    await _pump(tester, onScanRepeat: (_) async {});
    await _openSearch(tester);

    await tester.enterText(find.byType(EditableText), 'DN-1');
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Searching…'), findsOneWidget);
    expect(find.text('No results found'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    replies['DN-1']!.complete(_reply('DN-0001'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('DN-0001'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'DN-12');
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('DN-0001'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    replies['DN-12']!.complete(_reply('DN-0012'));
    await tester.pump();
    await tester.pump();
    expect(find.text('DN-0001'), findsNothing);
    expect(find.text('DN-0012'), findsOneWidget);
  });

  for (final accent in AppAccent.all) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'RECENT headings are readable [${brightness.name}, ${accent.name}]',
        (tester) async {
          _seed([
            _scan('A', ScanOutcome.ok, at: _now),
            _scan('B', ScanOutcome.ok, at: DateTime(2026, 11, 25, 9)),
          ]);
          await _pump(
            tester,
            onScanRepeat: (_) async {},
            theme: buildAppTheme(
              AppScheme.of(brightness),
              brightness,
              accent: accent,
            ),
          );
          await _openSearch(tester);

          for (final label in ['RECENT', 'Clear all', 'Today', 'Yesterday']) {
            final text = find.text(label);
            final style = DefaultTextStyle.of(
              tester.element(text),
            ).style.merge(tester.widget<Text>(text).style);
            final foreground =
                style.color ??
                Theme.of(tester.element(text)).colorScheme.primary;
            final surface = tester.widget<Material>(
              find
                  .ancestor(
                    of: text,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Material && (widget.color?.a ?? 0) == 1,
                    ),
                  )
                  .first,
            );
            final background = ElevationOverlay.applySurfaceTint(
              surface.color!,
              surface.surfaceTintColor,
              surface.elevation,
            );
            expect(
              contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
              reason: label,
            );
          }
        },
      );
    }
  }
}

AwesomeBarOption _scan(String code, ScanOutcome outcome, {DateTime? at}) {
  final scan = AwesomeBarOption.scan(
    code: code,
    kind: outcome == ScanOutcome.ok ? ScanType.item : ScanType.unknown,
    outcome: outcome,
  );
  if (at == null) return scan;
  final json = scan.toJson()..['at'] = at.toUtc().toIso8601String();
  return AwesomeBarOption.fromJson(json);
}

Response _reply(String name) => Response(
  requestOptions: RequestOptions(),
  data: {
    'message': [
      {'doctype': 'Delivery Note', 'name': name},
    ],
  },
);

void _seed(List<AwesomeBarOption> options) {
  SharedPreferences.setMockInitialValues({
    'awesome_bar_recents': options
        .map((option) => jsonEncode(option.toJson()))
        .toList(),
  });
}

Finder _tileOf(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(ListTile));

Future<void> _pump(
  WidgetTester tester, {
  Future<void> Function(String code)? onScanRepeat,
  ThemeData? theme,
  GetPage? itemPage,
}) => tester.pumpWidget(
  GetMaterialApp(
    theme: theme,
    getPages: [
      GetPage(
        name: '/',
        page: () => Scaffold(body: AwesomeBar(onScanRepeat: onScanRepeat)),
      ),
      ?itemPage,
    ],
  ),
);

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search or type a command'));
  await tester.pumpAndSettle();
}
