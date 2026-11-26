import 'dart:convert';

// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final itemIcon = searchTargetForDoctype('Item')!.icon;
  for (final (kind, label, icon) in [
    (ScanType.item, 'Sample item', itemIcon),
    (ScanType.batch, 'Sample item', itemIcon),
    (ScanType.rack, 'Rack WH-1-A', Icons.shelves),
    (
      ScanType.variant_of,
      'Variants of Original code',
      Icons.account_tree_outlined,
    ),
    (ScanType.multiple, 'Multiple items', Icons.list_alt_outlined),
  ]) {
    test(
      'records a successful ${kind.name} scan and restores its icon',
      () async {
        await AwesomeBarRecentStore.record(
          AwesomeBarOption.scan(
            code: 'Original code',
            kind: kind,
            outcome: ScanOutcome.ok,
            itemLabel: 'Sample item',
            rackId: 'WH-1-A',
          ),
        );

        final saved = (await AwesomeBarRecentStore.read()).single;
        expect(saved.type, 'Scan');
        expect(saved.value, 'Original code');
        expect(saved.scanKind, kind);
        expect(saved.scanOutcome, ScanOutcome.ok);
        expect(saved.label, label);
        expect(saved.description, 'Scanned Original code');
        expect(saved.icon, icon);
      },
    );
  }

  for (final (kind, outcome, description) in [
    (ScanType.error, ScanOutcome.notFound, 'Not found'),
    (ScanType.rack, ScanOutcome.invalid, 'Invalid rack code'),
    (ScanType.rack, ScanOutcome.empty, 'Empty rack'),
    (ScanType.error, ScanOutcome.error, 'Scan failed'),
  ]) {
    test(
      'records a ${outcome.name} scan with a descriptive subtitle',
      () async {
        await AwesomeBarRecentStore.record(
          AwesomeBarOption.scan(code: 'example', kind: kind, outcome: outcome),
        );

        final saved = (await AwesomeBarRecentStore.read()).single;
        expect(saved.value, 'example');
        expect(saved.scanKind, kind);
        expect(saved.scanOutcome, outcome);
        expect(saved.description, description);
        expect(saved.icon, isNotNull);
      },
    );
  }

  test(
    'repeat moves a normalised scan to the top and updates its kind and outcome',
    () async {
      await AwesomeBarRecentStore.record(
        AwesomeBarOption.scan(
          code: '  abc ',
          kind: ScanType.unknown,
          outcome: ScanOutcome.notFound,
        ),
      );
      await AwesomeBarRecentStore.record(
        AwesomeBarOption.fromGlobalSearchHit({
          'doctype': 'Item',
          'name': 'ABC',
        })!,
      );
      await AwesomeBarRecentStore.record(
        AwesomeBarOption.scan(
          code: 'ABC',
          kind: ScanType.item,
          outcome: ScanOutcome.ok,
          itemLabel: 'Item ABC',
        ),
      );

      final saved = await AwesomeBarRecentStore.read();
      expect(saved.map((option) => option.type), ['Scan', 'Item']);
      expect(saved.map((option) => option.value), ['ABC', 'ABC']);
      expect(saved.first.label, 'Item ABC');
      expect(saved.first.scanKind, ScanType.item);
      expect(saved.first.scanOutcome, ScanOutcome.ok);
    },
  );

  test('eleventh concurrent scan or pick evicts the oldest of ten', () async {
    final writes = <Future<void>>[];
    for (var index = 0; index < 11; index++) {
      final code = 'item-$index';
      final option = index.isEven
          ? AwesomeBarOption.scan(
              code: code,
              kind: ScanType.item,
              outcome: ScanOutcome.ok,
            )
          : AwesomeBarOption.fromGlobalSearchHit({
              'doctype': 'Item',
              'name': code,
            })!;
      writes.add(AwesomeBarRecentStore.record(option));
    }
    await Future.wait(writes);

    final saved = await AwesomeBarRecentStore.read();
    expect(saved, hasLength(10));
    expect(saved.map((option) => option.value), [
      for (var index = 10; index >= 1; index--) 'item-$index',
    ]);
  });

  test('scan JSON round-trips raw input, kind and outcome', () {
    final option = AwesomeBarOption.scan(
      code: ' miss ',
      kind: ScanType.unknown,
      outcome: ScanOutcome.notFound,
    );

    final json = option.toJson();
    expect(json, containsPair('outcome', 'not_found'));
    expect(json, isNot(contains('icon')));
    expect(json, isNot(contains('color')));
    final restored = AwesomeBarOption.fromJson(jsonDecode(jsonEncode(json)));
    expect(restored.toJson(), json);
    expect(restored.icon, Icons.qr_code_scanner);
  });

  test('loads legacy picks before and after recording a scan', () async {
    SharedPreferences.setMockInitialValues({
      'awesome_bar_recents': [
        jsonEncode({
          'type': 'Item',
          'value': 'ABC',
          'label': 'A saved Item',
          'route': '/app/Item/ABC',
          'isGlobalSearch': true,
        }),
      ],
    });

    final old = (await AwesomeBarRecentStore.read()).single;
    expect(old.label, 'A saved Item');
    expect(old.scanKind, isNull);
    expect(old.scanOutcome, isNull);
    expect(old.resolveNavigation()?.route, AppRoutes.ITEM_FORM);
    expect(old.icon, itemIcon);

    await AwesomeBarRecentStore.record(
      AwesomeBarOption.scan(
        code: 'DEF',
        kind: ScanType.variant_of,
        outcome: ScanOutcome.ok,
      ),
    );
    expect((await AwesomeBarRecentStore.read()).map((option) => option.value), [
      'DEF',
      'ABC',
    ]);
  });

  test('updates a controller already alive when a scan is recorded', () async {
    final controller = AwesomeBarController(
      globalSearch: (_) async {
        throw StateError('An empty overlay should not search');
      },
    );
    controller.onInit();
    addTearDown(controller.onClose);
    await Future<void>.delayed(Duration.zero);
    expect(controller.recentOptions, isEmpty);
    final startingRevision = AwesomeBarRecentStore.scanRevision;
    await AwesomeBarRecentStore.record(
      AwesomeBarOption.scan(
        code: 'ABC',
        kind: ScanType.variant_of,
        outcome: ScanOutcome.ok,
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(controller.recentOptions.single.value, 'ABC');
    expect(AwesomeBarRecentStore.scanRevision, startingRevision + 1);
    await AwesomeBarRecentStore.record(
      AwesomeBarOption.fromGlobalSearchHit({'doctype': 'Item', 'name': 'ABC'})!,
    );
    expect(AwesomeBarRecentStore.scanRevision, startingRevision + 1);
  });

  group('times, removal and saved searches', () {
    final now = DateTime(2026, 11, 26, 15, 30);
    setUp(() => AwesomeBarRecentStore.clock = () => now);
    tearDown(() => AwesomeBarRecentStore.clock = DateTime.now);

    test(
      'each save is stamped and survives a reload with its item code',
      () async {
        await AwesomeBarRecentStore.record(
          AwesomeBarOption.scan(
            code: '10048832',
            kind: ScanType.item,
            outcome: ScanOutcome.ok,
            itemLabel: 'POUCH',
            itemCode: ' ITM-1 ',
          ),
        );
        final [saved] = await AwesomeBarRecentStore.read();
        expect(saved.recordedAt, now);
        expect(saved.itemCode, 'ITM-1');
      },
    );

    test('a failed scan keeps no item code', () {
      final scan = AwesomeBarOption.scan(
        code: 'X',
        kind: ScanType.item,
        outcome: ScanOutcome.notFound,
        itemCode: 'ITM-1',
      );
      expect(scan.itemCode, isNull);
    });

    test(
      'remove drops one entry and clear can keep the ones it skips',
      () async {
        for (final code in ['A', 'B']) {
          await AwesomeBarRecentStore.record(
            AwesomeBarOption.scan(
              code: code,
              kind: ScanType.unknown,
              outcome: ScanOutcome.notFound,
            ),
          );
        }
        await AwesomeBarRecentStore.record(AwesomeBarOption.query('typed'));

        await AwesomeBarRecentStore.remove(
          AwesomeBarOption.scan(
            code: 'a',
            kind: ScanType.unknown,
            outcome: ScanOutcome.notFound,
          ),
        );
        expect((await AwesomeBarRecentStore.read()).map((o) => o.value), [
          'typed',
          'B',
        ]);

        await AwesomeBarRecentStore.clear(where: (option) => !option.isScan);
        expect((await AwesomeBarRecentStore.read()).map((o) => o.value), ['B']);

        await AwesomeBarRecentStore.clear();
        expect(await AwesomeBarRecentStore.read(), isEmpty);
      },
    );

    test(
      'saved searches de-duplicate regardless of case and keep no route',
      () async {
        await AwesomeBarRecentStore.record(AwesomeBarOption.query('Pouch'));
        await AwesomeBarRecentStore.record(AwesomeBarOption.query(' pouch '));
        final [saved] = await AwesomeBarRecentStore.read();
        expect(saved.isQuery, isTrue);
        expect(saved.value, 'pouch');
        expect(saved.description, 'No results');
        expect(saved.route, isEmpty);
        expect(saved.icon, Icons.manage_search);
      },
    );

    test('time labels and day groups', () {
      expect(
        recentTimeLabel(now.subtract(const Duration(seconds: 30)), now),
        'Just now',
      );
      expect(
        recentTimeLabel(now.subtract(const Duration(minutes: 59)), now),
        '59 min ago',
      );
      expect(recentTimeLabel(DateTime(2026, 11, 26, 0, 5), now), '00:05');
      expect(
        recentTimeLabel(DateTime(2026, 11, 25, 23, 59), now),
        'Yesterday 23:59',
      );
      expect(recentTimeLabel(DateTime(2026, 10, 2, 7, 0), now), '2 Oct 07:00');
      expect(recentDayGroup(null, now), RecentDayGroup.earlier);
      expect(
        recentDayGroup(DateTime(2026, 11, 26, 0, 1), now),
        RecentDayGroup.today,
      );
      expect(
        recentDayGroup(DateTime(2026, 11, 25, 23, 59), now),
        RecentDayGroup.yesterday,
      );
      expect(
        recentDayGroup(DateTime(2026, 11, 24, 12), now),
        RecentDayGroup.earlier,
      );
      // A clock set slightly behind still counts a save as today.
      expect(
        recentDayGroup(now.add(const Duration(minutes: 2)), now),
        RecentDayGroup.today,
      );
      expect(
        recentTimeLabel(now.add(const Duration(minutes: 2)), now),
        'Just now',
      );
    });
  });
}
